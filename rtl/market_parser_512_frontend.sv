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

    logic        beat_valid_r;
    logic        beat_header_done_r;
    logic [511:0] beat_data_r;
    logic [ 63:0] beat_keep_r;
    logic         beat_last_r;
    logic         beat_bad_frame_r;
    logic [ 15:0] beat_scan_base_offset_r;
    logic [  6:0] beat_valid_lanes_r;

    logic         cand_valid_r;
    logic [63:0] cand_packet_sequence_r;
    logic [15:0] cand_message_index_r;
    logic [15:0] cand_message_length_r;
    logic [15:0] cand_message_start_r;
    logic [15:0] cand_message_end_r;
    logic [ 5:0] cand_message_lane_r;
    logic        cand_type_valid_r;
    logic [ 7:0] cand_flags_r;

    logic        len_stage_valid_r;
    logic        len_stage_has_desc_r;
    logic [15:0] len_stage_message_index_r;
    logic [15:0] len_stage_length_offset_r;
    logic [15:0] len_stage_message_length_r;
    logic        len_stage_pending_hi_valid_r;
    logic [ 7:0] len_stage_pending_hi_r;

    logic [31:0] packet_count_r;
    logic [31:0] descriptor_count_r;
    logic [31:0] error_count_r;
    logic        packet_count_pending_r;
    logic        descriptor_count_pending_r;
    logic        error_count_pending_r;

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

    assign s_axis_rx_tready = !beat_valid_r && !cand_valid_r && !len_stage_valid_r &&
                              (int'(q_count_r) < DESC_QUEUE_DEPTH);
    assign packet_count     = packet_count_r + 32'(packet_count_pending_r);
    assign descriptor_count = descriptor_count_r + 32'(descriptor_count_pending_r);
    assign error_count      = error_count_r + 32'(error_count_pending_r);

    function automatic logic [7:0] get_byte(input logic [511:0] data, input int lane);
        get_byte = data[lane*8 +: 8];
    endfunction

    function automatic logic [7:0] get_byte_safe(input logic [511:0] data, input int lane);
        if (lane >= 0 && lane < 64) begin
            get_byte_safe = data[lane*8 +: 8];
        end else begin
            get_byte_safe = 8'h00;
        end
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
        lane = abs_offset & 63;
        lane_valid_for_offset = ((abs_offset >> 6) == (base_offset >> 6)) &&
                                keep[lane];
    endfunction

    always_ff @(posedge clk) begin
        int q_tail_next;
        int q_count_next;
        int scan_len_offset;
        int scan_msg_index;
        int msg_len;
        int msg_start;
        int msg_end;
        int type_lane;
        int high_lane;
        int low_lane;
        logic local_in_packet;
        logic local_pending_len_hi_valid;
        logic [7:0] local_pending_len_hi;
        logic [63:0] local_packet_sequence;
        logic [15:0] local_message_count;
        logic [15:0] accepted_base_offset;
        int accepted_valid_lanes;
        logic finish_beat;
        logic type_valid;
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
            beat_valid_r           <= 1'b0;
            beat_header_done_r     <= 1'b0;
            beat_data_r            <= '0;
            beat_keep_r            <= '0;
            beat_last_r            <= 1'b0;
            beat_bad_frame_r       <= 1'b0;
            beat_scan_base_offset_r <= '0;
            beat_valid_lanes_r     <= '0;
            cand_valid_r           <= 1'b0;
            cand_packet_sequence_r <= '0;
            cand_message_index_r   <= '0;
            cand_message_length_r  <= '0;
            cand_message_start_r   <= '0;
            cand_message_end_r     <= '0;
            cand_message_lane_r    <= '0;
            cand_type_valid_r      <= 1'b0;
            cand_flags_r           <= '0;
            len_stage_valid_r      <= 1'b0;
            len_stage_has_desc_r   <= 1'b0;
            len_stage_message_index_r <= '0;
            len_stage_length_offset_r <= '0;
            len_stage_message_length_r <= '0;
            len_stage_pending_hi_valid_r <= 1'b0;
            len_stage_pending_hi_r <= '0;
            packet_count_r         <= '0;
            descriptor_count_r     <= '0;
            error_count_r          <= '0;
            packet_count_pending_r <= 1'b0;
            descriptor_count_pending_r <= 1'b0;
            error_count_pending_r  <= 1'b0;
        end else begin
            q_tail_next  = int'(q_tail_r);
            q_count_next = int'(q_count_r);
            packet_count_r     <= packet_count_r + 32'(packet_count_pending_r);
            descriptor_count_r <= descriptor_count_r + 32'(descriptor_count_pending_r);
            error_count_r      <= error_count_r + 32'(error_count_pending_r);
            packet_count_pending_r     <= 1'b0;
            descriptor_count_pending_r <= 1'b0;
            error_count_pending_r      <= 1'b0;

            if (desc_valid && desc_ready) begin
                q_head_r     <= q_head_r + 1'b1;
                q_count_next = q_count_next - 1;
            end

            if (cand_valid_r && q_count_next < DESC_QUEUE_DEPTH) begin
                desc_packet_sequence_q[q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_packet_sequence_r;
                desc_message_index_q  [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_message_index_r;
                desc_message_length_q [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_message_length_r;
                desc_message_start_q  [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_message_start_r;
                desc_message_end_q    [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_message_end_r;
                desc_message_type_q   [q_tail_next[DESC_IDX_WIDTH-1:0]] <=
                    cand_type_valid_r ? get_byte(beat_data_r, int'(cand_message_lane_r)) : 8'h00;
                desc_message_lane_q   [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_message_lane_r;
                desc_type_valid_q     [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_type_valid_r;
                desc_flags_q          [q_tail_next[DESC_IDX_WIDTH-1:0]] <= cand_flags_r;

                q_tail_next = (q_tail_next + 1) % DESC_QUEUE_DEPTH;
                q_count_next++;
                cand_valid_r <= 1'b0;
                descriptor_count_pending_r <= 1'b1;
                if ((cand_flags_r & (DESC_FLAG_MALFORMED | DESC_FLAG_TRUNCATED | DESC_FLAG_BAD_FRAME)) != 8'h00) begin
                    error_count_pending_r <= 1'b1;
                end
            end

            if (s_axis_rx_tvalid && s_axis_rx_tready) begin
                accepted_base_offset = in_packet_r ? beat_base_offset_r : 16'd0;
                accepted_valid_lanes = count_valid_lanes(s_axis_rx_tkeep);
                beat_valid_r            <= 1'b1;
                beat_header_done_r      <= in_packet_r;
                beat_data_r             <= s_axis_rx_tdata;
                beat_keep_r             <= s_axis_rx_tkeep;
                beat_last_r             <= s_axis_rx_tlast;
                beat_bad_frame_r        <= s_axis_rx_tuser_bad_frame;
                beat_scan_base_offset_r <= accepted_base_offset;
                beat_valid_lanes_r      <= 7'(accepted_valid_lanes);
            end

            if (beat_valid_r && !cand_valid_r && !len_stage_valid_r) begin
                local_in_packet             = in_packet_r;
                local_packet_sequence       = packet_sequence_r;
                local_message_count         = packet_message_count_r;
                scan_msg_index              = int'(message_index_r);
                scan_len_offset             = int'(next_length_offset_r);
                local_pending_len_hi_valid  = pending_len_hi_valid_r;
                local_pending_len_hi        = pending_len_hi_r;
                finish_beat                 = 1'b0;

                if (!beat_header_done_r) begin
                    if (beat_valid_lanes_r < 7'd20) begin
                        error_count_pending_r <= 1'b1;
                        in_packet_r <= 1'b0;
                        local_in_packet = 1'b0;
                        local_pending_len_hi_valid = 1'b0;
                        local_pending_len_hi = '0;
                        scan_msg_index = 0;
                        scan_len_offset = 0;
                        finish_beat = 1'b1;
                    end else begin
                        local_packet_sequence = {
                            get_byte(beat_data_r, 10), get_byte(beat_data_r, 11),
                            get_byte(beat_data_r, 12), get_byte(beat_data_r, 13),
                            get_byte(beat_data_r, 14), get_byte(beat_data_r, 15),
                            get_byte(beat_data_r, 16), get_byte(beat_data_r, 17)
                        };
                        local_message_count = {get_byte(beat_data_r, 18), get_byte(beat_data_r, 19)};
                        packet_sequence_r      <= local_packet_sequence;
                        packet_message_count_r <= local_message_count;
                        packet_count_pending_r <= 1'b1;
                        scan_msg_index         = 0;
                        scan_len_offset        = 20;
                        local_pending_len_hi_valid = 1'b0;
                        local_pending_len_hi       = '0;
                        local_in_packet        = (local_message_count != 16'd0 &&
                                                  local_message_count != 16'hffff);
                        in_packet_r            <= local_in_packet;
                        beat_header_done_r     <= 1'b1;
                        if (!local_in_packet) begin
                            finish_beat = 1'b1;
                        end
                    end
                end else if (!local_in_packet || scan_msg_index >= local_message_count) begin
                    finish_beat = 1'b1;
                end else begin
                    len_stage_valid_r           <= 1'b1;
                    len_stage_has_desc_r        <= 1'b0;
                    len_stage_message_index_r   <= 16'(scan_msg_index);
                    len_stage_length_offset_r   <= 16'(scan_len_offset);
                    len_stage_pending_hi_valid_r <= local_pending_len_hi_valid;
                    len_stage_pending_hi_r      <= local_pending_len_hi;

                    if (local_pending_len_hi_valid) begin
                        low_lane = (scan_len_offset + 1) & 63;
                        msg_len = int'({local_pending_len_hi, get_byte_safe(beat_data_r, low_lane)});
                        len_stage_message_length_r <= 16'(msg_len);
                        if (lane_valid_for_offset(beat_keep_r, int'(beat_scan_base_offset_r),
                                                  scan_len_offset + 1)) begin
                            len_stage_has_desc_r <= 1'b1;
                            len_stage_pending_hi_valid_r <= 1'b0;
                        end else begin
                            // No descriptor this cycle; the next stage will finish the beat.
                        end
                    end else begin
                        high_lane = scan_len_offset & 63;
                        low_lane  = (scan_len_offset + 1) & 63;
                        msg_len = int'({
                            get_byte_safe(beat_data_r, high_lane),
                            get_byte_safe(beat_data_r, low_lane)
                        });
                        len_stage_message_length_r <= 16'(msg_len);
                        if (lane_valid_for_offset(beat_keep_r, int'(beat_scan_base_offset_r),
                                                  scan_len_offset)) begin
                            if (lane_valid_for_offset(beat_keep_r, int'(beat_scan_base_offset_r),
                                                      scan_len_offset + 1)) begin
                                len_stage_has_desc_r <= 1'b1;
                            end else begin
                                len_stage_pending_hi_valid_r <= 1'b1;
                                len_stage_pending_hi_r <= get_byte_safe(beat_data_r, high_lane);
                                // Carry the high byte into the next beat; no descriptor yet.
                            end
                        end else begin
                            // Length field is outside this beat, so the next stage finishes it.
                        end
                    end
                end

                if (!len_stage_valid_r) begin
                    pending_len_hi_valid_r <= local_pending_len_hi_valid;
                    pending_len_hi_r       <= local_pending_len_hi;
                    message_index_r        <= 16'(scan_msg_index);
                    next_length_offset_r   <= 16'(scan_len_offset);
                end

                if (finish_beat) begin
                    beat_valid_r       <= 1'b0;

                    if (beat_last_r) begin
                        in_packet_r            <= 1'b0;
                        beat_base_offset_r     <= '0;
                    end else begin
                        beat_base_offset_r <= 16'(int'(beat_scan_base_offset_r) +
                                                  int'(beat_valid_lanes_r));
                    end
                end
            end

            if (len_stage_valid_r && !cand_valid_r) begin
                scan_msg_index = int'(len_stage_message_index_r);
                scan_len_offset = int'(len_stage_length_offset_r);
                msg_len = int'(len_stage_message_length_r);
                finish_beat = !len_stage_has_desc_r;

                pending_len_hi_valid_r <= len_stage_pending_hi_valid_r;
                pending_len_hi_r       <= len_stage_pending_hi_r;

                if (len_stage_has_desc_r) begin
                    msg_start = scan_len_offset + 2;
                    msg_end   = msg_start + msg_len - 1;
                    type_lane = msg_start & 63;
                    type_valid = lane_valid_for_offset(beat_keep_r, int'(beat_scan_base_offset_r), msg_start);
                    local_flags = '0;
                    if (msg_len == 0) local_flags = local_flags | DESC_FLAG_MALFORMED;
                    if ((msg_start / 64) != (msg_end / 64)) begin
                        local_flags = local_flags | DESC_FLAG_CROSSES_BEAT;
                    end
                    if (beat_bad_frame_r) local_flags = local_flags | DESC_FLAG_BAD_FRAME;
                    if (beat_last_r && msg_end >= int'(beat_scan_base_offset_r) + int'(beat_valid_lanes_r)) begin
                        local_flags = local_flags | DESC_FLAG_TRUNCATED;
                    end

                    cand_valid_r           <= 1'b1;
                    cand_packet_sequence_r <= packet_sequence_r;
                    cand_message_index_r   <= 16'(scan_msg_index);
                    cand_message_length_r  <= 16'(msg_len);
                    cand_message_start_r   <= 16'(msg_start);
                    cand_message_end_r     <= 16'(msg_end);
                    cand_message_lane_r    <= 6'(type_lane);
                    cand_type_valid_r      <= type_valid;
                    cand_flags_r           <= local_flags;

                    scan_msg_index  = scan_msg_index + 1;
                    scan_len_offset = msg_end + 1;
                    if (msg_len == 0 || scan_msg_index >= int'(packet_message_count_r) ||
                        scan_len_offset >= int'(beat_scan_base_offset_r) + int'(beat_valid_lanes_r)) begin
                        finish_beat = 1'b1;
                    end
                end

                message_index_r      <= 16'(scan_msg_index);
                next_length_offset_r <= 16'(scan_len_offset);
                len_stage_valid_r    <= 1'b0;

                if (finish_beat) begin
                    beat_valid_r <= 1'b0;
                    if (beat_last_r) begin
                        in_packet_r        <= 1'b0;
                        beat_base_offset_r <= '0;
                    end else begin
                        beat_base_offset_r <= 16'(int'(beat_scan_base_offset_r) +
                                                  int'(beat_valid_lanes_r));
                    end
                end
            end

            q_tail_r  <= q_tail_next[DESC_IDX_WIDTH-1:0];
            q_count_r <= q_count_next[DESC_IDX_WIDTH:0];
        end
    end

endmodule
`default_nettype wire
