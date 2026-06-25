`default_nettype none
// =============================================================================
// Module: market_parser_100g_ingress
// =============================================================================
// 512-bit AXI-stream-style ingress shell for a 100G MAC-facing datapath.
//
// This block accepts wide RX beats into a small FIFO and drains them into the
// reusable parser adapter. It is intended as the hardware-facing integration
// point for a future board with a 100G-capable MAC. The parser stage behind this
// shell is still byte-serial, so sustained worst-case 100G parsing requires a
// future parallel boundary/parser stage.
module market_parser_100g_ingress #(
    parameter int OUTPUT_BUS_WIDTH = 256,
    parameter int FIFO_DEPTH       = 16
) (
    input  wire logic                         clk,
    input  wire logic                         rst,

    input  wire logic                         s_axis_rx_tvalid,
    output logic                              s_axis_rx_tready,
    input  wire logic [511:0]                 s_axis_rx_tdata,
    input  wire logic [ 63:0]                 s_axis_rx_tkeep,
    input  wire logic                         s_axis_rx_tlast,
    input  wire logic                         s_axis_rx_tuser_bad_frame,

    output logic                              data_out_valid,
    input  wire logic                         data_out_ready,
    output logic [  OUTPUT_BUS_WIDTH-1:0]     data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0]     data_out_keep,
    output logic                              data_out_last,

    output logic                              gap_error,
    output logic                              malformed_error,
    output logic                              unknown_msg_type,
    output logic [                  63:0]     expected_sequence,
    output logic [                  63:0]     packet_sequence,
    output logic [                  31:0]     packet_count,
    output logic [                  31:0]     message_count,
    output logic [                  31:0]     event_count,
    output logic [                  31:0]     error_count,

    output logic [                  31:0]     ingress_beat_count,
    output logic [                  31:0]     ingress_packet_count,
    output logic [                  31:0]     ingress_backpressure_count,
    output logic [                  31:0]     ingress_bad_frame_count,
    output logic [                  15:0]     ingress_fifo_level
);
    localparam int ADDR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    initial begin
        if (FIFO_DEPTH < 2) begin
            $fatal(1, "FIFO_DEPTH must be at least 2");
        end
    end

    logic [511:0]              fifo_data_r [FIFO_DEPTH];
    logic [ 63:0]              fifo_keep_r [FIFO_DEPTH];
    logic                      fifo_last_r [FIFO_DEPTH];
    logic                      fifo_bad_r  [FIFO_DEPTH];
    logic [ADDR_WIDTH-1:0]     wr_ptr_r;
    logic [ADDR_WIDTH-1:0]     rd_ptr_r;
    logic [ADDR_WIDTH:0]       fifo_count_r;

    logic                      fifo_empty_i;
    logic                      fifo_full_i;
    logic                      adapter_in_valid_i;
    logic                      adapter_in_ready_i;
    logic                      fifo_push_i;
    logic                      fifo_pop_i;

    logic [31:0]               ingress_beat_count_r;
    logic [31:0]               ingress_packet_count_r;
    logic [31:0]               ingress_backpressure_count_r;
    logic [31:0]               ingress_bad_frame_count_r;

    assign fifo_empty_i = (fifo_count_r == '0);
    assign fifo_full_i  = (fifo_count_r == FIFO_DEPTH[ADDR_WIDTH:0]);

    assign adapter_in_valid_i = !fifo_empty_i;
    assign fifo_pop_i        = adapter_in_valid_i && adapter_in_ready_i;

    assign s_axis_rx_tready = !fifo_full_i || fifo_pop_i;
    assign fifo_push_i      = s_axis_rx_tvalid && s_axis_rx_tready;

    assign ingress_beat_count         = ingress_beat_count_r;
    assign ingress_packet_count       = ingress_packet_count_r;
    assign ingress_backpressure_count = ingress_backpressure_count_r;
    assign ingress_bad_frame_count    = ingress_bad_frame_count_r;
    assign ingress_fifo_level         = 16'(fifo_count_r);

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr_r                     <= '0;
            rd_ptr_r                     <= '0;
            fifo_count_r                 <= '0;
            ingress_beat_count_r         <= '0;
            ingress_packet_count_r       <= '0;
            ingress_backpressure_count_r <= '0;
            ingress_bad_frame_count_r    <= '0;
        end else begin
            if (s_axis_rx_tvalid && !s_axis_rx_tready) begin
                ingress_backpressure_count_r <= ingress_backpressure_count_r + 1'b1;
            end

            if (fifo_push_i) begin
                fifo_data_r[wr_ptr_r] <= s_axis_rx_tdata;
                fifo_keep_r[wr_ptr_r] <= s_axis_rx_tkeep;
                fifo_last_r[wr_ptr_r] <= s_axis_rx_tlast;
                fifo_bad_r [wr_ptr_r] <= s_axis_rx_tuser_bad_frame;
                wr_ptr_r              <= wr_ptr_r + 1'b1;
                ingress_beat_count_r  <= ingress_beat_count_r + 1'b1;
                if (s_axis_rx_tlast) ingress_packet_count_r <= ingress_packet_count_r + 1'b1;
                if (s_axis_rx_tuser_bad_frame) ingress_bad_frame_count_r <= ingress_bad_frame_count_r + 1'b1;
            end

            if (fifo_pop_i) begin
                rd_ptr_r <= rd_ptr_r + 1'b1;
            end

            case ({fifo_push_i, fifo_pop_i})
                2'b10: fifo_count_r <= fifo_count_r + 1'b1;
                2'b01: fifo_count_r <= fifo_count_r - 1'b1;
                default: begin
                end
            endcase
        end
    end

    market_parser_axis_adapter #(
        .DATA_WIDTH      (512),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) u_axis_adapter (
        .clk              (clk),
        .rst              (rst),
        .data_in_valid    (adapter_in_valid_i),
        .data_in_ready    (adapter_in_ready_i),
        .data_in_data     (fifo_data_r[rd_ptr_r]),
        .data_in_keep     (fifo_keep_r[rd_ptr_r] & {64{!fifo_bad_r[rd_ptr_r]}}),
        .data_in_last     (fifo_last_r[rd_ptr_r]),
        .data_out_valid   (data_out_valid),
        .data_out_ready   (data_out_ready),
        .data_out_data    (data_out_data),
        .data_out_keep    (data_out_keep),
        .data_out_last    (data_out_last),
        .gap_error        (gap_error),
        .malformed_error  (malformed_error),
        .unknown_msg_type (unknown_msg_type),
        .expected_sequence(expected_sequence),
        .packet_sequence  (packet_sequence),
        .packet_count     (packet_count),
        .message_count    (message_count),
        .event_count      (event_count),
        .error_count      (error_count)
    );

endmodule
`default_nettype wire
