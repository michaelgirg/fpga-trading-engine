`default_nettype none
// =============================================================================
// Module: market_parser_512_frontend
// =============================================================================
// Multi-beat 512-bit descriptor frontend for a future sustained-line-rate parser.
//
// The frontend tracks MoldUDP64 packet byte offsets across 512-bit beats and
// emits one descriptor per ITCH message. It does not parse full ITCH payload
// fields yet; descriptors are the handoff point to a future parallel extractor.
module market_parser_512_frontend #(
    parameter int DESC_QUEUE_DEPTH = 8
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         s_axis_rx_tvalid,
    output logic              s_axis_rx_tready,
    input  wire logic [511:0] s_axis_rx_tdata,
    input  wire logic [ 63:0] s_axis_rx_tkeep,
    input  wire logic         s_axis_rx_tlast,
    input  wire logic         s_axis_rx_tuser_bad_frame,

    output logic              desc_valid,
    input  wire logic         desc_ready,
    output logic [63:0]       desc_packet_sequence,
    output logic [15:0]       desc_message_index,
    output logic [15:0]       desc_message_length,
    output logic [15:0]       desc_message_start_byte,
    output logic [15:0]       desc_message_end_byte,
    output logic [ 7:0]       desc_message_type,
    output logic [ 5:0]       desc_message_type_lane,
    output logic              desc_message_type_valid,
    output logic [ 7:0]       desc_flags,

    output logic [31:0]       packet_count,
    output logic [31:0]       descriptor_count,
    output logic [31:0]       error_count
);
    localparam int DESC_IDX_WIDTH = (DESC_QUEUE_DEPTH <= 1) ? 1 : $clog2(DESC_QUEUE_DEPTH);

    localparam logic [7:0] DESC_FLAG_CROSSES_BEAT = 8'h01;
    localparam logic [7:0] DESC_FLAG_MALFORMED    = 8'h02;
    localparam logic [7:0] DESC_FLAG_BAD_FRAME    = 8'h04;
    localparam logic [7:0] DESC_FLAG_TRUNCATED    = 8'h08;

    initial begin
        if (DESC_QUEUE_DEPTH < 4) begin
            $fatal(1, "DESC_QUEUE_DEPTH must be at least 4");
        end
    end

    logic [63:0] desc_packet_sequence_q [DESC_QUEUE_DEPTH];
    logic [15:0] desc_message_index_q   [DESC_QUEUE_DEPTH];
    logic [15:0] desc_message_length_q  [DESC_QUEUE_DEPTH];
    logic [15:0] desc_message_start_q   [DESC_QUEUE_DEPTH];
    logic [15:0] desc_message_end_q     [DESC_QUEUE_DEPTH];
    logic [ 7:0] desc_message_type_q    [DESC_QUEUE_DEPTH];
    logic [ 5:0] desc_message_lane_q    [DESC_QUEUE_DEPTH];
    logic        desc_type_valid_q      [DESC_QUEUE_DEPTH];
    logic [ 7:0] desc_flags_q           [DESC_QUEUE_DEPTH];

    logic [DESC_IDX_WIDTH-1:0] q_head_r;
    logic [DESC_IDX_WIDTH-1:0] q_tail_r;
    logic [DESC_IDX_WIDTH:0]   q_count_r;

    logic        in_packet_r;
    logic [15:0] beat_base_offset_r;
    logic [63:0] packet_sequence_r;
    logic [15:0] packet_message_count_r;
    logic [15:0] message_index_r;
    logic [15:0] next_length_offset_r;
    logic        pending_len_hi_valid_r;
    logic [ 7:0] pending_len_hi_r;

    logic [31:0] packet_count_r;
    logic [31:0] descriptor_count_r;
    logic [31:0] error_count_r;

    assign desc_valid              = (q_count_r != '0);
    assign desc_packet_sequence    = desc_packet_sequence_q[q_head_r];
    assign desc_message_index      = desc_message_index_q[q_head_r];
    assign desc_message_length     = desc_message_length_q[q_head_r];
    assign desc_message_start_byte = desc_message_start_q[q_head_r];
    assign desc_message_end_byte   = desc_message_end_q[q_head_r];
    assign desc_message_type       = desc_message_type_q[q_head_r];
    assign desc_message_type_lane  = desc_message_lane_q[q_head_r];
    assign desc_message_type_valid = desc_type_valid_q[q_head_r];
    assign desc_flags              = desc_flags_q[q_head_r];

    assign s_axis_rx_tready = (q_count_r == '0);
    assign packet_count     = packet_count_r;
    assign descriptor_count = descriptor_count_r;
    assign error_count      = error_count_r;

    function automatic logic [7:0] get_byte(input logic [511:0] data, input int lane);
        get_byte = data[lane*8 +: 8];
    endfunction

    function automatic int count_valid_lanes(input logic [63:0] keep);
        int count;
        count = 0;
        for (int i = 0; i < 64; i++) begin
            if (keep[i]) count++;
        end
        count_valid_lanes = count;
    endfunction

    function automatic logic lane_valid_for_offset(input logic [63:0] keep,
                                                   input int base_offset,
                                                   input int abs_offset);
        int lane;
        lane = abs_offset - base_offset;
        lane_valid_for_offset = (lane >= 0 && lane < 64 && keep[lane]);
    endfunction

    always_ff @(posedge clk) begin
        int q_tail_next;
        int q_count_next;
        int base_offset;
        int valid_lanes;
        int scan_len_offset;
        int scan_msg_index;
        int msg_len;
        int msg_start;
        int msg_end;
        int type_lane;
        int low_lane;
        int packet_count_inc;
        int descriptor_count_inc;
        int error_count_inc;
        logic local_in_packet;
        logic local_pending_len_hi_valid;
        logic [7:0] local_pending_len_hi;
        logic [63:0] local_packet_sequence;
        logic [15:0] local_message_count;
        logic stop_scan;
        logic [7:0] local_flags;

        if (rst) begin
            q_head_r               <= '0;
            q_tail_r               <= '0;
            q_count_r              <= '0;
            in_packet_r            <= 1'b0;
            beat_base_offset_r     <= '0;
            packet_sequence_r      <= '0;
            packet_message_count_r <= '0;
            message_index_r        <= '0;
            next_length_offset_r   <= '0;
            pending_len_hi_valid_r <= 1'b0;
            pending_len_hi_r       <= '0;
            packet_count_r         <= '0;
            descriptor_count_r     <= '0;
            error_count_r          <= '0;
        end else begin
            q_tail_next  = int'(q_tail_r);
            q_count_next = int'(q_count_r);
            packet_count_inc = 0;
            descriptor_count_inc = 0;
            error_count_inc = 0;

            if (desc_valid && desc_ready) begin
                q_head_r     <= q_head_r + 1'b1;
                q_count_next = q_count_next - 1;
            end

            if (s_axis_rx_tvalid && s_axis_rx_tready) begin
                base_offset                 = int'(beat_base_offset_r);
                valid_lanes                 = count_valid_lanes(s_axis_rx_tkeep);
                local_in_packet             = in_packet_r;
                local_packet_sequence       = packet_sequence_r;
                local_message_count         = packet_message_count_r;
                scan_msg_index              = int'(message_index_r);
                scan_len_offset             = int'(next_length_offset_r);
                local_pending_len_hi_valid  = pending_len_hi_valid_r;
                local_pending_len_hi        = pending_len_hi_r;
                stop_scan                   = 1'b0;

                if (!local_in_packet) begin
                    base_offset = 0;
                    if (valid_lanes < 20) begin
                        error_count_inc++;
                        stop_scan = 1'b1;
                    end else begin
                        local_packet_sequence = {
                            get_byte(s_axis_rx_tdata, 10), get_byte(s_axis_rx_tdata, 11),
                            get_byte(s_axis_rx_tdata, 12), get_byte(s_axis_rx_tdata, 13),
                            get_byte(s_axis_rx_tdata, 14), get_byte(s_axis_rx_tdata, 15),
                            get_byte(s_axis_rx_tdata, 16), get_byte(s_axis_rx_tdata, 17)
                        };
                        local_message_count = {get_byte(s_axis_rx_tdata, 18), get_byte(s_axis_rx_tdata, 19)};
                        packet_sequence_r      <= local_packet_sequence;
                        packet_message_count_r <= local_message_count;
                        packet_count_inc++;
                        scan_msg_index         = 0;
                        scan_len_offset        = 20;
                        local_in_packet        = (local_message_count != 16'd0 &&
                                                  local_message_count != 16'hffff);
                    end
                end

                if (local_in_packet && !stop_scan) begin
                    for (int c = 0; c < 4; c++) begin
                        if (!stop_scan && scan_msg_index < local_message_count &&
                            q_count_next < DESC_QUEUE_DEPTH) begin
                            if (local_pending_len_hi_valid) begin
                                if (lane_valid_for_offset(s_axis_rx_tkeep, base_offset, scan_len_offset + 1)) begin
                                    low_lane = (scan_len_offset + 1) - base_offset;
                                    msg_len = int'({local_pending_len_hi, get_byte(s_axis_rx_tdata, low_lane)});
                                    local_pending_len_hi_valid = 1'b0;
                                end else begin
                                    stop_scan = 1'b1;
                                    msg_len = 0;
                                end
                            end else if (lane_valid_for_offset(s_axis_rx_tkeep, base_offset, scan_len_offset)) begin
                                if (lane_valid_for_offset(s_axis_rx_tkeep, base_offset, scan_len_offset + 1)) begin
                                    low_lane = (scan_len_offset + 1) - base_offset;
                                    msg_len = int'({get_byte(s_axis_rx_tdata, scan_len_offset - base_offset),
                                                    get_byte(s_axis_rx_tdata, low_lane)});
                                end else begin
                                    local_pending_len_hi_valid = 1'b1;
                                    local_pending_len_hi = get_byte(s_axis_rx_tdata, scan_len_offset - base_offset);
                                    stop_scan = 1'b1;
                                    msg_len = 0;
                                end
                            end else begin
                                stop_scan = 1'b1;
                                msg_len = 0;
                            end

                            if (!stop_scan) begin
                                msg_start = scan_len_offset + 2;
                                msg_end   = msg_start + msg_len - 1;
                                type_lane = msg_start - base_offset;
                                local_flags = '0;
                                if (msg_len == 0) local_flags = local_flags | DESC_FLAG_MALFORMED;
                                if ((msg_start / 64) != (msg_end / 64)) begin
                                    local_flags = local_flags | DESC_FLAG_CROSSES_BEAT;
                                end
                                if (s_axis_rx_tuser_bad_frame) local_flags = local_flags | DESC_FLAG_BAD_FRAME;
                                if (s_axis_rx_tlast && msg_end >= base_offset + valid_lanes) begin
                                    local_flags = local_flags | DESC_FLAG_TRUNCATED;
                                end

                                desc_packet_sequence_q[q_tail_next[DESC_IDX_WIDTH-1:0]] <= local_packet_sequence;
                                desc_message_index_q  [q_tail_next[DESC_IDX_WIDTH-1:0]] <= 16'(scan_msg_index);
                                desc_message_length_q [q_tail_next[DESC_IDX_WIDTH-1:0]] <= 16'(msg_len);
                                desc_message_start_q  [q_tail_next[DESC_IDX_WIDTH-1:0]] <= 16'(msg_start);
                                desc_message_end_q    [q_tail_next[DESC_IDX_WIDTH-1:0]] <= 16'(msg_end);
                                desc_message_type_q   [q_tail_next[DESC_IDX_WIDTH-1:0]] <=
                                    (type_lane >= 0 && type_lane < 64 && s_axis_rx_tkeep[type_lane]) ?
                                    get_byte(s_axis_rx_tdata, type_lane) : 8'h00;
                                desc_message_lane_q   [q_tail_next[DESC_IDX_WIDTH-1:0]] <= 6'(type_lane);
                                desc_type_valid_q     [q_tail_next[DESC_IDX_WIDTH-1:0]] <=
                                    (type_lane >= 0 && type_lane < 64 && s_axis_rx_tkeep[type_lane]);
                                desc_flags_q          [q_tail_next[DESC_IDX_WIDTH-1:0]] <= local_flags;

                                q_tail_next = (q_tail_next + 1) % DESC_QUEUE_DEPTH;
                                q_count_next++;
                                descriptor_count_inc++;
                                if ((local_flags & (DESC_FLAG_MALFORMED | DESC_FLAG_TRUNCATED | DESC_FLAG_BAD_FRAME)) != 8'h00) begin
                                    error_count_inc++;
                                end

                                scan_msg_index  = scan_msg_index + 1;
                                scan_len_offset = msg_end + 1;
                                if (msg_len == 0) stop_scan = 1'b1;
                            end
                        end
                    end
                end

                pending_len_hi_valid_r <= local_pending_len_hi_valid;
                pending_len_hi_r       <= local_pending_len_hi;
                message_index_r        <= 16'(scan_msg_index);
                next_length_offset_r   <= 16'(scan_len_offset);

                if (s_axis_rx_tlast) begin
                    in_packet_r            <= 1'b0;
                    beat_base_offset_r     <= '0;
                    pending_len_hi_valid_r <= 1'b0;
                end else begin
                    in_packet_r        <= local_in_packet;
                    beat_base_offset_r <= 16'(base_offset + valid_lanes);
                end
            end

            q_tail_r  <= q_tail_next[DESC_IDX_WIDTH-1:0];
            q_count_r <= q_count_next[DESC_IDX_WIDTH:0];
            packet_count_r     <= packet_count_r + packet_count_inc;
            descriptor_count_r <= descriptor_count_r + descriptor_count_inc;
            error_count_r      <= error_count_r + error_count_inc;
        end
    end

endmodule
`default_nettype wire
