`default_nettype none
// =============================================================================
// Module: market_parser_udp_payload_strip
// =============================================================================
// Ethernet II / IPv4 / UDP filter and fixed-header stripper for 512-bit CMAC
// receive streams. The output stream starts at byte 0 of the UDP payload, which
// is the MoldUDP64 header for the parser pipeline.
module market_parser_udp_payload_strip #(
    parameter logic [15:0] FEED_UDP_PORT = 16'd5000,
    parameter int          FIFO_DEPTH    = 8
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         s_axis_rx_tvalid,
    output logic              s_axis_rx_tready,
    input  wire logic [511:0] s_axis_rx_tdata,
    input  wire logic [ 63:0] s_axis_rx_tkeep,
    input  wire logic         s_axis_rx_tlast,
    input  wire logic         s_axis_rx_tuser_bad_frame,

    output logic              m_axis_payload_tvalid,
    input  wire logic         m_axis_payload_tready,
    output logic [511:0]      m_axis_payload_tdata,
    output logic [ 63:0]      m_axis_payload_tkeep,
    output logic              m_axis_payload_tlast,
    output logic              m_axis_payload_tuser_bad_frame,

    output logic [31:0]       accepted_frame_count,
    output logic [31:0]       dropped_frame_count,
    output logic [31:0]       header_error_count,
    output logic [31:0]       payload_packet_count,
    output logic [15:0]       payload_fifo_level
);
    localparam int HEADER_BYTES = 42;
    localparam int CARRY_BYTES  = 64 - HEADER_BYTES;
    localparam int HEADER_BITS  = HEADER_BYTES * 8;
    localparam int CARRY_BITS   = CARRY_BYTES * 8;
    localparam int PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    initial begin
        if (FIFO_DEPTH < 4) begin
            $fatal(1, "FIFO_DEPTH must be at least 4");
        end
    end

    typedef enum logic [1:0] {
        STATE_FIRST = 2'd0,
        STATE_PASS  = 2'd1,
        STATE_DROP  = 2'd2
    } state_t;

    state_t state_r;

    logic [511:0] data_q[FIFO_DEPTH];
    logic [ 63:0] keep_q[FIFO_DEPTH];
    logic         last_q[FIFO_DEPTH];
    logic         bad_q [FIFO_DEPTH];

    logic [PTR_WIDTH-1:0] wr_ptr_r;
    logic [PTR_WIDTH-1:0] rd_ptr_r;
    logic [PTR_WIDTH:0]   count_r;

    logic [CARRY_BITS-1:0] carry_data_r;
    logic [ 5:0]  carry_count_r;
    logic         bad_frame_seen_r;

    logic [31:0] accepted_frame_count_r;
    logic [31:0] dropped_frame_count_r;
    logic [31:0] header_error_count_r;
    logic [31:0] payload_packet_count_r;

    logic        fifo_pop_i;
    logic        rx_fire_i;
    logic [1:0]  push_count_i;
    logic [511:0] push0_data_i;
    logic [ 63:0] push0_keep_i;
    logic         push0_last_i;
    logic         push0_bad_i;
    logic [511:0] push1_data_i;
    logic [ 63:0] push1_keep_i;
    logic         push1_last_i;
    logic         push1_bad_i;

    assign m_axis_payload_tvalid         = (count_r != '0);
    assign m_axis_payload_tdata          = data_q[rd_ptr_r];
    assign m_axis_payload_tkeep          = keep_q[rd_ptr_r];
    assign m_axis_payload_tlast          = last_q[rd_ptr_r];
    assign m_axis_payload_tuser_bad_frame = bad_q[rd_ptr_r];

    assign fifo_pop_i = m_axis_payload_tvalid && m_axis_payload_tready;
    assign rx_fire_i  = s_axis_rx_tvalid && s_axis_rx_tready;

    assign s_axis_rx_tready = (state_r == STATE_DROP) ||
                              (int'(count_r) <= (FIFO_DEPTH - 2));

    assign accepted_frame_count = accepted_frame_count_r;
    assign dropped_frame_count  = dropped_frame_count_r;
    assign header_error_count   = header_error_count_r;
    assign payload_packet_count = payload_packet_count_r;
    assign payload_fifo_level   = 16'(count_r);

    function automatic int unsigned leading_keep_count(input logic [63:0] keep);
        bit stopped;
        leading_keep_count = 0;
        stopped = 1'b0;
        for (int lane = 0; lane < 64; lane++) begin
            if (!stopped && keep[lane]) begin
                leading_keep_count++;
            end else begin
                stopped = 1'b1;
            end
        end
    endfunction

    function automatic logic [63:0] keep_for_count(input int unsigned byte_count);
        keep_for_count = '0;
        for (int lane = 0; lane < 64; lane++) begin
            if (lane < byte_count) begin
                keep_for_count[lane] = 1'b1;
            end
        end
    endfunction

    function automatic logic [511:0] header_tail_payload(input logic [511:0] data);
        header_tail_payload = '0;
        header_tail_payload[0 +: CARRY_BITS] = data[HEADER_BITS +: CARRY_BITS];
    endfunction

    function automatic logic [511:0] combined_payload(input logic [CARRY_BITS-1:0] carry,
                                                      input logic [511:0] data);
        combined_payload = '0;
        combined_payload[0 +: CARRY_BITS] = carry;
        combined_payload[CARRY_BITS +: HEADER_BITS] = data[0 +: HEADER_BITS];
    endfunction

    function automatic logic header_matches(input logic [511:0] data,
                                            input logic [ 63:0] keep,
                                            input logic         bad_frame);
        header_matches =
            !bad_frame &&
            (&keep[0 +: HEADER_BYTES]) &&
            (data[12*8 +: 8] == 8'h08) &&
            (data[13*8 +: 8] == 8'h00) &&
            (data[14*8 +: 8] == 8'h45) &&
            (data[20*8 +: 5] == 5'd0) &&
            (data[21*8 +: 8] == 8'h00) &&
            (data[23*8 +: 8] == 8'h11) &&
            (data[36*8 +: 8] == FEED_UDP_PORT[15:8]) &&
            (data[37*8 +: 8] == FEED_UDP_PORT[7:0]);
    endfunction

    function automatic logic [PTR_WIDTH-1:0] inc_ptr(input logic [PTR_WIDTH-1:0] ptr);
        if (ptr == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
            inc_ptr = '0;
        end else begin
            inc_ptr = ptr + 1'b1;
        end
    endfunction

    always_comb begin
        int unsigned byte_count;
        int unsigned first_tail_count;
        int unsigned lower_count;
        int unsigned tail_count;
        int unsigned combined_count;
        logic [511:0] first_tail_data;
        logic [511:0] tail_data;

        byte_count       = leading_keep_count(s_axis_rx_tkeep);
        first_tail_count = (byte_count > HEADER_BYTES) ? (byte_count - HEADER_BYTES) : 0;
        lower_count      = (byte_count >= HEADER_BYTES) ? HEADER_BYTES : byte_count;
        tail_count       = (byte_count > HEADER_BYTES) ? (byte_count - HEADER_BYTES) : 0;
        combined_count   = carry_count_r + lower_count;
        first_tail_data  = header_tail_payload(s_axis_rx_tdata);
        tail_data        = header_tail_payload(s_axis_rx_tdata);

        push_count_i = 2'd0;
        push0_data_i = '0;
        push0_keep_i = '0;
        push0_last_i = 1'b0;
        push0_bad_i  = 1'b0;
        push1_data_i = '0;
        push1_keep_i = '0;
        push1_last_i = 1'b0;
        push1_bad_i  = 1'b0;

        if (rx_fire_i && (state_r == STATE_FIRST) &&
            header_matches(s_axis_rx_tdata, s_axis_rx_tkeep, s_axis_rx_tuser_bad_frame) &&
            s_axis_rx_tlast && (first_tail_count != 0)) begin
            push_count_i = 2'd1;
            push0_data_i = first_tail_data;
            push0_keep_i = keep_for_count(first_tail_count);
            push0_last_i = 1'b1;
            push0_bad_i  = s_axis_rx_tuser_bad_frame;
        end else if (rx_fire_i && (state_r == STATE_PASS)) begin
            if (combined_count != 0) begin
                push_count_i = 2'd1;
                push0_data_i = combined_payload(carry_data_r, s_axis_rx_tdata);
                push0_keep_i = keep_for_count(combined_count);
                push0_last_i = s_axis_rx_tlast && (tail_count == 0);
                push0_bad_i  = bad_frame_seen_r || s_axis_rx_tuser_bad_frame;
            end

            if (s_axis_rx_tlast && (tail_count != 0)) begin
                if (combined_count != 0) begin
                    push_count_i = 2'd2;
                    push1_data_i = tail_data;
                    push1_keep_i = keep_for_count(tail_count);
                    push1_last_i = 1'b1;
                    push1_bad_i  = bad_frame_seen_r || s_axis_rx_tuser_bad_frame;
                end else begin
                    push_count_i = 2'd1;
                    push0_data_i = tail_data;
                    push0_keep_i = keep_for_count(tail_count);
                    push0_last_i = 1'b1;
                    push0_bad_i  = bad_frame_seen_r || s_axis_rx_tuser_bad_frame;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        logic [PTR_WIDTH-1:0] wr_ptr_next;

        if (rst) begin
            state_r                  <= STATE_FIRST;
            wr_ptr_r                 <= '0;
            rd_ptr_r                 <= '0;
            count_r                  <= '0;
            carry_data_r             <= '0;
            carry_count_r            <= '0;
            bad_frame_seen_r         <= 1'b0;
            accepted_frame_count_r   <= '0;
            dropped_frame_count_r    <= '0;
            header_error_count_r     <= '0;
            payload_packet_count_r   <= '0;
        end else begin
            wr_ptr_next = wr_ptr_r;

            if (push_count_i != 0) begin
                data_q[wr_ptr_next] <= push0_data_i;
                keep_q[wr_ptr_next] <= push0_keep_i;
                last_q[wr_ptr_next] <= push0_last_i;
                bad_q [wr_ptr_next] <= push0_bad_i;
                wr_ptr_next = inc_ptr(wr_ptr_next);
            end

            if (push_count_i == 2) begin
                data_q[wr_ptr_next] <= push1_data_i;
                keep_q[wr_ptr_next] <= push1_keep_i;
                last_q[wr_ptr_next] <= push1_last_i;
                bad_q [wr_ptr_next] <= push1_bad_i;
                wr_ptr_next = inc_ptr(wr_ptr_next);
            end

            if (push_count_i != 0) begin
                wr_ptr_r <= wr_ptr_next;
            end

            if (fifo_pop_i) begin
                rd_ptr_r <= inc_ptr(rd_ptr_r);
            end

            count_r <= count_r + (PTR_WIDTH+1)'(push_count_i) - (PTR_WIDTH+1)'(fifo_pop_i);

            if (rx_fire_i) begin
                int unsigned byte_count;
                int unsigned first_tail_count;
                int unsigned tail_count;

                byte_count       = leading_keep_count(s_axis_rx_tkeep);
                first_tail_count = (byte_count > HEADER_BYTES) ? (byte_count - HEADER_BYTES) : 0;
                tail_count       = (byte_count > HEADER_BYTES) ? (byte_count - HEADER_BYTES) : 0;

                unique case (state_r)
                    STATE_FIRST: begin
                        if (header_matches(s_axis_rx_tdata, s_axis_rx_tkeep,
                                           s_axis_rx_tuser_bad_frame)) begin
                            accepted_frame_count_r <= accepted_frame_count_r + 1'b1;
                            carry_data_r           <= s_axis_rx_tdata[HEADER_BITS +: CARRY_BITS];
                            carry_count_r          <= 6'(first_tail_count);
                            bad_frame_seen_r       <= s_axis_rx_tuser_bad_frame;
                            if (s_axis_rx_tlast) begin
                                state_r          <= STATE_FIRST;
                                carry_data_r     <= '0;
                                carry_count_r    <= '0;
                                bad_frame_seen_r <= 1'b0;
                                if (first_tail_count != 0) begin
                                    payload_packet_count_r <= payload_packet_count_r + 1'b1;
                                end
                            end else begin
                                state_r <= STATE_PASS;
                            end
                        end else begin
                            dropped_frame_count_r <= dropped_frame_count_r + 1'b1;
                            header_error_count_r  <= header_error_count_r + 1'b1;
                            carry_data_r          <= '0;
                            carry_count_r         <= '0;
                            bad_frame_seen_r      <= 1'b0;
                            state_r               <= s_axis_rx_tlast ? STATE_FIRST : STATE_DROP;
                        end
                    end

                    STATE_PASS: begin
                        bad_frame_seen_r <= bad_frame_seen_r || s_axis_rx_tuser_bad_frame;
                        if (s_axis_rx_tlast) begin
                            state_r          <= STATE_FIRST;
                            carry_data_r     <= '0;
                            carry_count_r    <= '0;
                            bad_frame_seen_r <= 1'b0;
                            payload_packet_count_r <= payload_packet_count_r + 1'b1;
                        end else begin
                            carry_data_r    <= s_axis_rx_tdata[HEADER_BITS +: CARRY_BITS];
                            carry_count_r   <= 6'(tail_count);
                        end
                    end

                    default: begin
                        if (s_axis_rx_tlast) begin
                            state_r <= STATE_FIRST;
                        end
                    end
                endcase
            end
        end
    end

endmodule
`default_nettype wire
