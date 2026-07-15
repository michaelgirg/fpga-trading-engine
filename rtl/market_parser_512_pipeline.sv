`default_nettype none
// =============================================================================
// Module: market_parser_512_pipeline
// =============================================================================
// Integrated 512-bit cut-through parallel parser path.
//
// The module connects:
//   1. market_parser_512_frontend      -> ITCH message descriptors
//   2. market_parser_512_window_buffer -> multi-beat packet windows
//   3. market_parser_512_event_extract -> normalized 256-bit events
//
// This is the first cut-through 100G-facing parallel path. It keeps a
// packet-local multi-beat window buffer, but it no longer waits for packet end
// before extracting events. Any descriptor whose required window beats have
// arrived can emit while later packet beats are still being accepted.
module market_parser_512_pipeline #(
    parameter int PACKET_BEATS_MAX = 16,
    parameter int DESC_FIFO_DEPTH  = 32,
    parameter int EXTRACTION_WINDOW_BYTES = 256
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         s_axis_rx_tvalid,
    output logic              s_axis_rx_tready,
    input  wire logic [511:0] s_axis_rx_tdata,
    input  wire logic [ 63:0] s_axis_rx_tkeep,
    input  wire logic         s_axis_rx_tlast,
    input  wire logic         s_axis_rx_tuser_bad_frame,

    output logic              event_valid,
    input  wire logic         event_ready,
    output logic [255:0]      event_data,
    output logic [ 63:0]      event_new_order_ref,
    output logic [ 31:0]      event_keep,
    output logic              event_last,

    output logic [31:0]       packet_count,
    output logic [31:0]       descriptor_count,
    output logic [31:0]       event_count,
    output logic [31:0]       extractor_error_count,
    output logic [31:0]       bad_frame_count
);
    localparam int DESC_IDX_WIDTH = (DESC_FIFO_DEPTH <= 1) ? 1 : $clog2(DESC_FIFO_DEPTH);
    localparam int BEAT_IDX_WIDTH = (PACKET_BEATS_MAX <= 1) ? 1 : $clog2(PACKET_BEATS_MAX);
    localparam int EXTRACTION_WINDOW_BEATS = EXTRACTION_WINDOW_BYTES / 64;
    localparam int FIELD_EXTRACT_BYTES = 40;
    localparam int FIELD_COARSE_BYTES  = FIELD_EXTRACT_BYTES + 8;

    localparam logic [7:0] DESC_FLAG_MALFORMED = 8'h02;
    localparam logic [7:0] DESC_FLAG_TRUNCATED = 8'h08;

    initial begin
        if (PACKET_BEATS_MAX < 2) begin
            $fatal(1, "PACKET_BEATS_MAX must be at least 2");
        end
        if (DESC_FIFO_DEPTH < 4) begin
            $fatal(1, "DESC_FIFO_DEPTH must be at least 4");
        end
        if (EXTRACTION_WINDOW_BYTES < 128 || (EXTRACTION_WINDOW_BYTES % 64) != 0) begin
            $fatal(1, "EXTRACTION_WINDOW_BYTES must be a multiple of 64 and at least 128");
        end
    end

    logic frontend_valid;
    logic frontend_ready;
    logic frontend_desc_valid;
    logic frontend_desc_ready;
    logic [63:0] frontend_desc_packet_sequence;
    logic [15:0] frontend_desc_message_index;
    logic [15:0] frontend_desc_message_length;
    logic [15:0] frontend_desc_message_start_byte;
    logic [15:0] frontend_desc_message_end_byte;
    logic [ 7:0] frontend_desc_message_type;
    logic [ 5:0] frontend_desc_message_type_lane;
    logic        frontend_desc_message_type_valid;
    logic [ 7:0] frontend_desc_flags;
    logic [31:0] frontend_packet_count;
    logic [31:0] frontend_descriptor_count;
    logic [31:0] frontend_error_count;

    logic [63:0] desc_packet_sequence_q [DESC_FIFO_DEPTH];
    logic [15:0] desc_message_index_q   [DESC_FIFO_DEPTH];
    logic [15:0] desc_message_length_q  [DESC_FIFO_DEPTH];
    logic [15:0] desc_message_start_q   [DESC_FIFO_DEPTH];
    logic [15:0] desc_message_end_q     [DESC_FIFO_DEPTH];
    logic [ 7:0] desc_flags_q           [DESC_FIFO_DEPTH];

    logic        desc_head_valid_r;
    logic [63:0] desc_head_packet_sequence_r;
    logic [15:0] desc_head_message_index_r;
    logic [15:0] desc_head_message_length_r;
    logic [15:0] desc_head_message_start_r;
    logic [15:0] desc_head_message_end_r;
    logic [ 7:0] desc_head_flags_r;
    logic [BEAT_IDX_WIDTH:0] desc_head_start_beat_r;
    logic [BEAT_IDX_WIDTH:0] desc_head_required_beat_r;
    logic                    desc_head_forced_ready_r;
    logic                    desc_head_window_ready_r;

    logic [DESC_IDX_WIDTH-1:0] desc_wr_ptr_r;
    logic [DESC_IDX_WIDTH-1:0] desc_rd_ptr_r;
    logic [DESC_IDX_WIDTH:0]   desc_count_r;

    logic [BEAT_IDX_WIDTH:0] packet_beat_count_r;
    logic [BEAT_IDX_WIDTH:0] packet_beats_stored_r;
    logic                    accepting_packet_r;
    logic                    packet_done_r;
    logic                    clear_window;
    logic                    input_accepted;
    logic                    packet_space_available;
    logic                    desc_space_available;
    logic                    desc_push;
    logic                    desc_pop;
    logic                    desc_head_load;
    logic                    desc_head_consume;
    logic                    desc_window_ready;
    logic                    desc_head_ready_next;
    logic                    possible_final_desc_blocked;
    logic [DESC_IDX_WIDTH:0] desc_visible_count;
    logic                    extract_req_ready;
    logic                    extract_coarse_ready;
    logic                    extract_field_ready;
    logic                    extract_result_ready;
    logic                    extract_req_to_coarse;
    logic                    extract_coarse_to_field;
    logic                    extract_field_to_result;
    logic                    extract_result_to_output;
    logic                    pipe_idle;

    logic [15:0] window_base_byte;
    logic [EXTRACTION_WINDOW_BYTES*8-1:0] window_data;
    logic [  EXTRACTION_WINDOW_BYTES-1:0] window_keep;
    logic          extract_desc_valid;
    logic          extract_event_valid;
    logic          extract_event_complete;
    logic          extract_event_supported;
    logic [255:0]  extract_event_data;
    logic [ 63:0]  extract_event_new_order_ref;
    logic [31:0]   extract_error_flags;

    logic          extract_req_valid_r;
    logic [15:0]   extract_req_window_base_byte_r;
    logic [EXTRACTION_WINDOW_BYTES*8-1:0] extract_req_window_data_r;
    logic [  EXTRACTION_WINDOW_BYTES-1:0] extract_req_window_keep_r;
    logic [15:0]   extract_req_message_length_r;
    logic [15:0]   extract_req_message_start_r;
    logic [15:0]   extract_req_message_end_r;
    logic [ 7:0]   extract_req_flags_r;
    logic          extract_req_last_r;

    logic          extract_coarse_valid_r;
    logic [FIELD_COARSE_BYTES*8-1:0] extract_coarse_data_r;
    logic [ 2:0]   extract_coarse_fine_lane_r;
    logic          extract_coarse_complete_r;
    logic [15:0]   extract_coarse_message_length_r;
    logic [ 7:0]   extract_coarse_flags_r;
    logic          extract_coarse_last_r;

    logic          extract_field_valid_r;
    logic [FIELD_EXTRACT_BYTES*8-1:0] extract_field_data_r;
    logic          extract_field_complete_r;
    logic [15:0]   extract_field_message_length_r;
    logic [ 7:0]   extract_field_flags_r;
    logic          extract_field_last_r;
    logic [15:0]   extract_field_extract_length;
    logic [ 7:0]   extract_field_extract_flags;
    logic [EXTRACTION_WINDOW_BYTES*8-1:0] extract_field_window_data;
    logic [  EXTRACTION_WINDOW_BYTES-1:0] extract_field_window_keep;

    logic          extract_result_valid_r;
    logic [255:0]  extract_result_data_r;
    logic [ 63:0]  extract_result_new_order_ref_r;
    logic [31:0]   extract_result_error_flags_r;
    logic          extract_result_last_r;

    logic          event_valid_r;
    logic [255:0]  event_data_r;
    logic [ 63:0]  event_new_order_ref_r;
    logic          event_last_r;
    logic [31:0]   packet_count_r;
    logic [31:0]   descriptor_count_r;
    logic [31:0]   event_count_r;
    logic [31:0]   extractor_error_count_r;
    logic [31:0]   bad_frame_count_r;

    assign packet_space_available = (int'(packet_beat_count_r) < PACKET_BEATS_MAX);
    assign desc_space_available   = (int'(desc_count_r) < DESC_FIFO_DEPTH);
    assign frontend_valid         = s_axis_rx_tvalid && accepting_packet_r && !clear_window &&
                                    packet_space_available && desc_space_available;
    assign s_axis_rx_tready       = frontend_ready && accepting_packet_r && !clear_window &&
                                    packet_space_available && desc_space_available;
    assign input_accepted         = s_axis_rx_tvalid && s_axis_rx_tready;
    assign frontend_desc_ready    = desc_space_available;
    assign desc_push              = frontend_desc_valid && frontend_desc_ready;
    assign desc_visible_count     = desc_count_r +
                                    (desc_head_valid_r ? (DESC_IDX_WIDTH+1)'(1) : '0);
    assign possible_final_desc_blocked = packet_done_r && !frontend_ready && (desc_visible_count == 1);
    assign extract_result_ready   = !extract_result_valid_r || (!event_valid_r || event_ready);
    assign extract_field_ready    = !extract_field_valid_r || extract_result_ready;
    assign extract_coarse_ready   = !extract_coarse_valid_r || extract_field_ready;
    assign extract_req_ready      = !extract_req_valid_r || extract_coarse_ready;
    assign extract_desc_valid     = extract_field_valid_r;
    assign extract_req_to_coarse  = extract_req_valid_r && extract_coarse_ready;
    assign extract_coarse_to_field = extract_coarse_valid_r && extract_field_ready;
    assign extract_field_to_result = extract_field_valid_r && extract_result_ready;
    assign extract_result_to_output = extract_result_valid_r && (!event_valid_r || event_ready);
    assign desc_head_load         = !desc_head_valid_r && (desc_count_r != '0);
    assign desc_head_consume      = extract_req_ready && desc_head_valid_r && desc_head_window_ready_r &&
                                    !possible_final_desc_blocked;
    assign desc_pop               = desc_head_consume;
    assign pipe_idle              = packet_done_r && frontend_ready && !frontend_desc_valid &&
                                    (desc_count_r == '0) && !desc_head_valid_r && !extract_req_valid_r &&
                                    !extract_coarse_valid_r && !extract_field_valid_r &&
                                    !extract_result_valid_r && !event_valid_r;

    assign event_valid = event_valid_r;
    assign event_data  = event_data_r;
    assign event_new_order_ref = event_new_order_ref_r;
    assign event_keep  = 32'hffff_ffff;
    assign event_last  = event_last_r;

    assign packet_count          = packet_count_r;
    assign descriptor_count      = descriptor_count_r;
    assign event_count           = event_count_r;
    assign extractor_error_count = extractor_error_count_r;
    assign bad_frame_count       = bad_frame_count_r;
    // Completeness is checked before final packing; keep the packer off the
    // wide length/keep timing path and carry incompleteness as a descriptor flag.
    assign extract_field_extract_length = 16'd1;
    assign extract_field_extract_flags  = extract_field_flags_r |
                                          (extract_field_complete_r ? 8'h00 : DESC_FLAG_TRUNCATED);

    always_comb begin
        extract_field_window_data = '0;
        extract_field_window_data[FIELD_EXTRACT_BYTES*8-1:0] = extract_field_data_r;
        extract_field_window_keep = {EXTRACTION_WINDOW_BYTES{1'b1}};
    end

    function automatic logic [BEAT_IDX_WIDTH:0] limited_required_beat(
        input logic [15:0] message_start_byte,
        input logic [15:0] message_end_byte
    );
        logic [BEAT_IDX_WIDTH:0] start_beat;
        logic [BEAT_IDX_WIDTH:0] end_beat;
        logic [BEAT_IDX_WIDTH:0] max_window_beat;

        start_beat      = (BEAT_IDX_WIDTH+1)'(message_start_byte[15:6]);
        end_beat        = (BEAT_IDX_WIDTH+1)'(message_end_byte[15:6]);
        max_window_beat = start_beat + (BEAT_IDX_WIDTH+1)'(EXTRACTION_WINDOW_BEATS - 1);
        if (end_beat > max_window_beat) begin
            limited_required_beat = max_window_beat;
        end else begin
            limited_required_beat = end_beat;
        end
    endfunction

    function automatic logic descriptor_window_ready(
        input logic [BEAT_IDX_WIDTH:0] start_beat,
        input logic [BEAT_IDX_WIDTH:0] required_beat,
        input logic forced_ready,
        input logic [BEAT_IDX_WIDTH:0] stored_beats,
        input logic packet_done
    );
        descriptor_window_ready =
            (start_beat < stored_beats) &&
            ((required_beat < stored_beats) ||
             packet_done ||
             forced_ready);
    endfunction

    function automatic logic request_range_complete(
        input logic [  EXTRACTION_WINDOW_BYTES-1:0] req_keep,
        input logic [                         15:0] message_length,
        input logic [                          5:0] start_lane
    );
        logic complete;
        int first_lane;
        int last_lane;

        first_lane = int'(start_lane);
        last_lane  = first_lane + int'(message_length) - 1;
        complete   = (message_length != 16'd0) && (last_lane < EXTRACTION_WINDOW_BYTES);
        if (complete) begin
            complete = req_keep[first_lane] && req_keep[last_lane];
        end
        request_range_complete = complete;
    endfunction

    function automatic logic [FIELD_COARSE_BYTES*8-1:0] select_coarse_field_data(
        input logic [EXTRACTION_WINDOW_BYTES*8-1:0] req_data,
        input logic [                         5:0] start_lane
    );
        logic [FIELD_COARSE_BYTES*8-1:0] selected;
        int coarse_lane;
        int source_lane;

        selected    = '0;
        coarse_lane = int'({start_lane[5:3], 3'b000});
        for (int lane = 0; lane < FIELD_COARSE_BYTES; lane++) begin
            source_lane = coarse_lane + lane;
            if (source_lane < EXTRACTION_WINDOW_BYTES) begin
                selected[lane*8 +: 8] = req_data[source_lane*8 +: 8];
            end
        end
        select_coarse_field_data = selected;
    endfunction

    function automatic logic [FIELD_EXTRACT_BYTES*8-1:0] select_fine_field_data(
        input logic [FIELD_COARSE_BYTES*8-1:0] coarse_data,
        input logic [                    2:0] fine_lane
    );
        logic [FIELD_EXTRACT_BYTES*8-1:0] selected;
        int source_lane;

        selected = '0;
        for (int lane = 0; lane < FIELD_EXTRACT_BYTES; lane++) begin
            source_lane = int'(fine_lane) + lane;
            if (source_lane < FIELD_COARSE_BYTES) begin
                selected[lane*8 +: 8] = coarse_data[source_lane*8 +: 8];
            end
        end
        select_fine_field_data = selected;
    endfunction

    assign desc_window_ready = descriptor_window_ready(
        desc_head_start_beat_r,
        desc_head_required_beat_r,
        desc_head_forced_ready_r,
        packet_beats_stored_r,
        packet_done_r
    );
    assign desc_head_ready_next = desc_head_window_ready_r || desc_window_ready;

    market_parser_512_frontend #(
        .DESC_QUEUE_DEPTH(8)
    ) frontend_i (
        .clk                       (clk),
        .rst                       (rst),
        .s_axis_rx_tvalid          (frontend_valid),
        .s_axis_rx_tready          (frontend_ready),
        .s_axis_rx_tdata           (s_axis_rx_tdata),
        .s_axis_rx_tkeep           (s_axis_rx_tkeep),
        .s_axis_rx_tlast           (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame (s_axis_rx_tuser_bad_frame),
        .desc_valid                (frontend_desc_valid),
        .desc_ready                (frontend_desc_ready),
        .desc_packet_sequence      (frontend_desc_packet_sequence),
        .desc_message_index        (frontend_desc_message_index),
        .desc_message_length       (frontend_desc_message_length),
        .desc_message_start_byte   (frontend_desc_message_start_byte),
        .desc_message_end_byte     (frontend_desc_message_end_byte),
        .desc_message_type         (frontend_desc_message_type),
        .desc_message_type_lane    (frontend_desc_message_type_lane),
        .desc_message_type_valid   (frontend_desc_message_type_valid),
        .desc_flags                (frontend_desc_flags),
        .packet_count              (frontend_packet_count),
        .descriptor_count          (frontend_descriptor_count),
        .error_count               (frontend_error_count)
    );

    market_parser_512_window_buffer #(
        .PACKET_BEATS_MAX(PACKET_BEATS_MAX),
        .WINDOW_BYTES    (EXTRACTION_WINDOW_BYTES)
    ) window_buffer_i (
        .clk                    (clk),
        .rst                    (rst),
        .clear                  (clear_window),
        .beat_write_en          (input_accepted),
        .beat_write_index       (16'(packet_beat_count_r)),
        .beat_write_data        (s_axis_rx_tdata),
        .beat_write_keep        (s_axis_rx_tkeep),
        .read_message_start_byte(desc_head_message_start_r),
        .window_base_byte       (window_base_byte),
        .window_data            (window_data),
        .window_keep            (window_keep)
    );

    market_parser_512_event_extract #(
        .WINDOW_BYTES(EXTRACTION_WINDOW_BYTES)
    ) extractor_i (
        .desc_valid             (extract_desc_valid),
        .window_base_byte       (16'd0),
        .window_data            (extract_field_window_data),
        .window_keep            (extract_field_window_keep),
        .desc_message_length    (extract_field_extract_length),
        .desc_message_start_byte(16'd0),
        .desc_message_end_byte  (16'd0),
        .desc_flags             (extract_field_extract_flags),
        .event_valid            (extract_event_valid),
        .event_complete         (extract_event_complete),
        .event_supported        (extract_event_supported),
        .event_data             (extract_event_data),
        .event_new_order_ref    (extract_event_new_order_ref),
        .extract_error_flags    (extract_error_flags)
    );

    function automatic logic [DESC_IDX_WIDTH-1:0] inc_desc_ptr(input logic [DESC_IDX_WIDTH-1:0] ptr);
        if (ptr == DESC_IDX_WIDTH'(DESC_FIFO_DEPTH - 1)) begin
            inc_desc_ptr = '0;
        end else begin
            inc_desc_ptr = ptr + 1'b1;
        end
    endfunction

    always_ff @(posedge clk) begin
        logic [DESC_IDX_WIDTH-1:0] desc_wr_ptr_next;
        logic [DESC_IDX_WIDTH-1:0] desc_rd_ptr_next;
        logic [DESC_IDX_WIDTH:0]   desc_count_next;
        logic                      event_last_next;

        if (rst) begin
            desc_wr_ptr_r           <= '0;
            desc_rd_ptr_r           <= '0;
            desc_count_r            <= '0;
            desc_head_valid_r       <= 1'b0;
            desc_head_packet_sequence_r <= '0;
            desc_head_message_index_r <= '0;
            desc_head_message_length_r <= '0;
            desc_head_message_start_r <= '0;
            desc_head_message_end_r <= '0;
            desc_head_flags_r       <= '0;
            desc_head_start_beat_r  <= '0;
            desc_head_required_beat_r <= '0;
            desc_head_forced_ready_r <= 1'b0;
            desc_head_window_ready_r <= 1'b0;
            packet_beat_count_r     <= '0;
            packet_beats_stored_r   <= '0;
            accepting_packet_r      <= 1'b1;
            packet_done_r           <= 1'b0;
            clear_window            <= 1'b1;
            extract_req_valid_r      <= 1'b0;
            extract_req_window_base_byte_r <= '0;
            extract_req_window_data_r <= '0;
            extract_req_window_keep_r <= '0;
            extract_req_message_length_r <= '0;
            extract_req_message_start_r <= '0;
            extract_req_message_end_r <= '0;
            extract_req_flags_r      <= '0;
            extract_req_last_r       <= 1'b0;
            extract_coarse_valid_r   <= 1'b0;
            extract_coarse_data_r    <= '0;
            extract_coarse_fine_lane_r <= '0;
            extract_coarse_complete_r <= 1'b0;
            extract_coarse_message_length_r <= '0;
            extract_coarse_flags_r   <= '0;
            extract_coarse_last_r    <= 1'b0;
            extract_field_valid_r    <= 1'b0;
            extract_field_data_r     <= '0;
            extract_field_complete_r <= 1'b0;
            extract_field_message_length_r <= '0;
            extract_field_flags_r    <= '0;
            extract_field_last_r     <= 1'b0;
            extract_result_valid_r   <= 1'b0;
            extract_result_data_r    <= '0;
            extract_result_new_order_ref_r <= '0;
            extract_result_error_flags_r <= '0;
            extract_result_last_r    <= 1'b0;
            event_valid_r           <= 1'b0;
            event_data_r            <= '0;
            event_new_order_ref_r   <= '0;
            event_last_r            <= 1'b0;
            packet_count_r          <= '0;
            descriptor_count_r      <= '0;
            event_count_r           <= '0;
            extractor_error_count_r <= '0;
            bad_frame_count_r       <= '0;
        end else begin
            desc_wr_ptr_next = desc_wr_ptr_r;
            desc_rd_ptr_next = desc_rd_ptr_r;
            desc_count_next  = desc_count_r;
            event_last_next  = 1'b0;
            clear_window <= 1'b0;

            if (extract_result_to_output) begin
                event_valid_r <= 1'b1;
                event_data_r  <= extract_result_data_r;
                event_new_order_ref_r <= extract_result_new_order_ref_r;
                event_last_r  <= extract_result_last_r;
                event_count_r <= event_count_r + 1'b1;
                if (extract_result_error_flags_r != 32'h0000_0000) begin
                    extractor_error_count_r <= extractor_error_count_r + 1'b1;
                end
            end else if (event_valid_r && event_ready) begin
                event_valid_r <= 1'b0;
                event_new_order_ref_r <= '0;
                event_last_r  <= 1'b0;
            end

            if (extract_field_to_result) begin
                extract_result_valid_r       <= extract_event_valid;
                extract_result_data_r        <= extract_event_data;
                extract_result_new_order_ref_r <= extract_event_new_order_ref;
                extract_result_error_flags_r <= extract_error_flags;
                extract_result_last_r        <= extract_field_last_r;
            end else if (extract_result_to_output) begin
                extract_result_valid_r <= 1'b0;
            end

            if (extract_coarse_to_field) begin
                extract_field_valid_r          <= 1'b1;
                extract_field_data_r           <= select_fine_field_data(extract_coarse_data_r,
                                                                         extract_coarse_fine_lane_r);
                extract_field_complete_r       <= extract_coarse_complete_r;
                extract_field_message_length_r <= extract_coarse_message_length_r;
                extract_field_flags_r          <= extract_coarse_flags_r;
                extract_field_last_r           <= extract_coarse_last_r;
            end else if (extract_field_to_result) begin
                extract_field_valid_r <= 1'b0;
            end

            if (extract_req_to_coarse) begin
                extract_coarse_valid_r          <= 1'b1;
                extract_coarse_data_r           <= select_coarse_field_data(extract_req_window_data_r,
                                                                            extract_req_message_start_r[5:0]);
                extract_coarse_fine_lane_r      <= extract_req_message_start_r[2:0];
                extract_coarse_complete_r       <= request_range_complete(extract_req_window_keep_r,
                                                                          extract_req_message_length_r,
                                                                          extract_req_message_start_r[5:0]);
                extract_coarse_message_length_r <= extract_req_message_length_r;
                extract_coarse_flags_r          <= extract_req_flags_r;
                extract_coarse_last_r           <= extract_req_last_r;
            end else if (extract_coarse_to_field) begin
                extract_coarse_valid_r <= 1'b0;
            end

            if (desc_push) begin
                desc_packet_sequence_q[desc_wr_ptr_r] <= frontend_desc_packet_sequence;
                desc_message_index_q  [desc_wr_ptr_r] <= frontend_desc_message_index;
                desc_message_length_q [desc_wr_ptr_r] <= frontend_desc_message_length;
                desc_message_start_q  [desc_wr_ptr_r] <= frontend_desc_message_start_byte;
                desc_message_end_q    [desc_wr_ptr_r] <= frontend_desc_message_end_byte;
                desc_flags_q          [desc_wr_ptr_r] <= frontend_desc_flags;
                desc_wr_ptr_next                      = inc_desc_ptr(desc_wr_ptr_r);
                desc_count_next                       = desc_count_next + 1'b1;
                descriptor_count_r                    <= descriptor_count_r + 1'b1;
            end

            if (input_accepted) begin
                packet_beats_stored_r <= packet_beats_stored_r + 1'b1;
                if (s_axis_rx_tuser_bad_frame) begin
                    bad_frame_count_r <= bad_frame_count_r + 1'b1;
                end

                if (s_axis_rx_tlast) begin
                    packet_count_r      <= packet_count_r + 1'b1;
                    packet_beat_count_r <= '0;
                    accepting_packet_r  <= 1'b0;
                    packet_done_r       <= 1'b1;
                end else begin
                    packet_beat_count_r <= packet_beat_count_r + 1'b1;
                end
            end

            if (desc_head_load) begin
                desc_head_valid_r          <= 1'b1;
                desc_head_packet_sequence_r <= desc_packet_sequence_q[desc_rd_ptr_r];
                desc_head_message_index_r  <= desc_message_index_q[desc_rd_ptr_r];
                desc_head_message_length_r <= desc_message_length_q[desc_rd_ptr_r];
                desc_head_message_start_r  <= desc_message_start_q[desc_rd_ptr_r];
                desc_head_message_end_r    <= desc_message_end_q[desc_rd_ptr_r];
                desc_head_flags_r          <= desc_flags_q[desc_rd_ptr_r];
                desc_head_start_beat_r     <= (BEAT_IDX_WIDTH+1)'(desc_message_start_q[desc_rd_ptr_r][15:6]);
                desc_head_required_beat_r  <= limited_required_beat(desc_message_start_q[desc_rd_ptr_r],
                                                                     desc_message_end_q[desc_rd_ptr_r]);
                desc_head_forced_ready_r   <= (desc_flags_q[desc_rd_ptr_r] &
                                               (DESC_FLAG_MALFORMED | DESC_FLAG_TRUNCATED)) != 8'h00;
                desc_head_window_ready_r   <= 1'b0;
                desc_rd_ptr_next           = inc_desc_ptr(desc_rd_ptr_r);
                desc_count_next            = desc_count_next - 1'b1;
            end else if (desc_head_valid_r && !desc_head_window_ready_r) begin
                desc_head_window_ready_r <= desc_head_ready_next;
            end

            if (desc_pop) begin
                event_last_next = packet_done_r && frontend_ready && !frontend_desc_valid &&
                                  (desc_count_next == 0);
                extract_req_valid_r            <= 1'b1;
                extract_req_window_base_byte_r <= window_base_byte;
                extract_req_window_data_r      <= window_data;
                extract_req_window_keep_r      <= window_keep;
                extract_req_message_length_r   <= desc_head_message_length_r;
                extract_req_message_start_r    <= desc_head_message_start_r;
                extract_req_message_end_r      <= desc_head_message_end_r;
                extract_req_flags_r            <= desc_head_flags_r;
                extract_req_last_r             <= event_last_next;
                desc_head_valid_r              <= 1'b0;
                desc_head_window_ready_r       <= 1'b0;
            end else if (extract_req_to_coarse) begin
                extract_req_valid_r <= 1'b0;
            end

            desc_wr_ptr_r <= desc_wr_ptr_next;
            desc_rd_ptr_r <= desc_rd_ptr_next;
            desc_count_r  <= desc_count_next;

            if (pipe_idle) begin
                clear_window          <= 1'b1;
                desc_wr_ptr_r         <= '0;
                desc_rd_ptr_r         <= '0;
                desc_count_r          <= '0;
                packet_beat_count_r   <= '0;
                packet_beats_stored_r <= '0;
                accepting_packet_r    <= 1'b1;
                packet_done_r         <= 1'b0;
                desc_head_valid_r     <= 1'b0;
                desc_head_window_ready_r <= 1'b0;
                extract_req_valid_r    <= 1'b0;
                extract_coarse_valid_r <= 1'b0;
                extract_field_valid_r  <= 1'b0;
                extract_result_valid_r <= 1'b0;
            end
        end
    end

endmodule
`default_nettype wire
