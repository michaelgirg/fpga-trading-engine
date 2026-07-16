`default_nettype none
// =============================================================================
// Module: market_parser_cmac_axis_rx_bridge
// =============================================================================
// Packet-preserving bridge from the AMD CMAC AXIS RX interface to the internal
// ready/valid stream used by the parser shell.
//
// The CMAC RX AXIS template exposes tvalid/data/keep/last/user, but no
// tready. This bridge therefore buffers complete packets before presenting them
// to the downstream ready/valid shell. If the packet buffer fills, the current
// packet is discarded through tlast so the downstream parser never sees a
// truncated frame.
module market_parser_cmac_axis_rx_bridge #(
    parameter int DATA_WIDTH = 512,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int FIFO_DEPTH = 64
) (
    input  wire logic                  clk,
    input  wire logic                  rst,

    input  wire logic                  rx_axis_tvalid,
    input  wire logic [DATA_WIDTH-1:0] rx_axis_tdata,
    input  wire logic [KEEP_WIDTH-1:0] rx_axis_tkeep,
    input  wire logic                  rx_axis_tlast,
    input  wire logic                  rx_axis_tuser,

    output logic                       m_axis_tvalid,
    input  wire logic                  m_axis_tready,
    output logic [DATA_WIDTH-1:0]      m_axis_tdata,
    output logic [KEEP_WIDTH-1:0]      m_axis_tkeep,
    output logic                       m_axis_tlast,
    output logic                       m_axis_tuser_bad_frame,

    output logic [31:0]                accepted_packet_count,
    output logic [31:0]                overflow_packet_count,
    output logic [31:0]                dropped_beat_count,
    output logic [15:0]                fifo_level,
    output logic [15:0]                fifo_high_watermark,
    output logic [15:0]                buffered_packet_count,
    output logic                       overflow_event
);
    localparam int PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    initial begin
        if (FIFO_DEPTH < 4) begin
            $fatal(1, "FIFO_DEPTH must be at least 4");
        end
    end

    logic [DATA_WIDTH-1:0] data_q[FIFO_DEPTH];
    logic [KEEP_WIDTH-1:0] keep_q[FIFO_DEPTH];
    logic                  last_q[FIFO_DEPTH];
    logic                  user_q[FIFO_DEPTH];

    logic [PTR_WIDTH-1:0] wr_ptr_r;
    logic [PTR_WIDTH-1:0] rd_ptr_r;
    logic [PTR_WIDTH-1:0] packet_start_ptr_r;
    logic [PTR_WIDTH:0]   count_r;
    logic [PTR_WIDTH:0]   partial_count_r;
    logic [PTR_WIDTH:0]   complete_packet_count_r;
    logic [PTR_WIDTH:0]   high_watermark_r;

    logic                 dropping_packet_r;
    logic [31:0]          accepted_packet_count_r;
    logic [31:0]          overflow_packet_count_r;
    logic [31:0]          dropped_beat_count_r;

    logic                 pop_i;

    assign m_axis_tvalid          = (complete_packet_count_r != '0) && (count_r != '0);
    assign m_axis_tdata           = data_q[rd_ptr_r];
    assign m_axis_tkeep           = keep_q[rd_ptr_r];
    assign m_axis_tlast           = last_q[rd_ptr_r];
    assign m_axis_tuser_bad_frame = user_q[rd_ptr_r];

    assign pop_i = m_axis_tvalid && m_axis_tready;

    assign accepted_packet_count = accepted_packet_count_r;
    assign overflow_packet_count = overflow_packet_count_r;
    assign dropped_beat_count    = dropped_beat_count_r;
    assign fifo_level            = 16'(count_r);
    assign fifo_high_watermark   = 16'(high_watermark_r);
    assign buffered_packet_count = 16'(complete_packet_count_r);

    function automatic logic [PTR_WIDTH-1:0] inc_ptr(input logic [PTR_WIDTH-1:0] ptr);
        if (ptr == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
            inc_ptr = '0;
        end else begin
            inc_ptr = ptr + 1'b1;
        end
    endfunction

    always_ff @(posedge clk) begin
        logic [PTR_WIDTH-1:0] wr_next;
        logic [PTR_WIDTH-1:0] rd_next;
        logic [PTR_WIDTH-1:0] packet_start_next;
        logic [PTR_WIDTH:0]   count_next;
        logic [PTR_WIDTH:0]   partial_next;
        logic [PTR_WIDTH:0]   complete_next;
        logic                 dropping_next;

        if (rst) begin
            wr_ptr_r                <= '0;
            rd_ptr_r                <= '0;
            packet_start_ptr_r      <= '0;
            count_r                 <= '0;
            partial_count_r         <= '0;
            complete_packet_count_r <= '0;
            high_watermark_r         <= '0;
            dropping_packet_r       <= 1'b0;
            accepted_packet_count_r <= '0;
            overflow_packet_count_r <= '0;
            dropped_beat_count_r    <= '0;
            overflow_event          <= 1'b0;
        end else begin
            overflow_event    <= 1'b0;
            wr_next           = wr_ptr_r;
            rd_next           = rd_ptr_r;
            packet_start_next = packet_start_ptr_r;
            count_next        = count_r;
            partial_next      = partial_count_r;
            complete_next     = complete_packet_count_r;
            dropping_next     = dropping_packet_r;

            if (pop_i) begin
                rd_next    = inc_ptr(rd_next);
                count_next = count_next - 1'b1;
                if (last_q[rd_ptr_r]) begin
                    complete_next = complete_next - 1'b1;
                end
            end

            if (rx_axis_tvalid) begin
                if (dropping_next) begin
                    dropped_beat_count_r <= dropped_beat_count_r + 1'b1;
                    if (rx_axis_tlast) begin
                        dropping_next = 1'b0;
                    end
                end else if (count_next >= (PTR_WIDTH+1)'(FIFO_DEPTH)) begin
                    wr_next                 = packet_start_next;
                    count_next              = count_next - partial_next;
                    dropped_beat_count_r    <= dropped_beat_count_r + 32'(partial_next) + 1'b1;
                    partial_next            = '0;
                    overflow_packet_count_r <= overflow_packet_count_r + 1'b1;
                    overflow_event          <= 1'b1;
                    dropping_next           = !rx_axis_tlast;
                end else begin
                    if (partial_next == '0) begin
                        packet_start_next = wr_next;
                    end

                    data_q[wr_next] <= rx_axis_tdata;
                    keep_q[wr_next] <= rx_axis_tkeep;
                    last_q[wr_next] <= rx_axis_tlast;
                    user_q[wr_next] <= rx_axis_tuser;

                    wr_next      = inc_ptr(wr_next);
                    count_next   = count_next + 1'b1;
                    partial_next = partial_next + 1'b1;

                    if (rx_axis_tlast) begin
                        partial_next           = '0;
                        packet_start_next      = wr_next;
                        complete_next          = complete_next + 1'b1;
                        accepted_packet_count_r <= accepted_packet_count_r + 1'b1;
                    end
                end
            end

            wr_ptr_r                <= wr_next;
            rd_ptr_r                <= rd_next;
            packet_start_ptr_r      <= packet_start_next;
            count_r                 <= count_next;
            partial_count_r         <= partial_next;
            complete_packet_count_r <= complete_next;
            if (count_next > high_watermark_r) begin
                high_watermark_r <= count_next;
            end
            dropping_packet_r       <= dropping_next;
        end
    end

endmodule
`default_nettype wire
