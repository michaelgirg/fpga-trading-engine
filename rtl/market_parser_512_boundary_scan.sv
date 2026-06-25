`default_nettype none
// =============================================================================
// Module: market_parser_512_boundary_scan
// =============================================================================
// First-beat parallel boundary scanner for a 512-bit MoldUDP64/ITCH packet beat.
//
// This module does not parse full messages. It extracts packet header fields and
// finds early ITCH message boundaries in parallel from one 64-byte beat. It is a
// building block for a future sustained 100G parser frontend.
module market_parser_512_boundary_scan #(
    parameter int MAX_CANDIDATES = 4
) (
    input  wire logic                             beat_valid,
    input  wire logic [511:0]                     beat_data,
    input  wire logic [ 63:0]                     beat_keep,
    input  wire logic                             beat_start_of_packet,

    output logic                                  scan_valid,
    output logic                                  truncated_header,
    output logic [                  63:0]         packet_sequence,
    output logic [                  15:0]         packet_message_count,
    output logic [    MAX_CANDIDATES-1:0]         candidate_valid,
    output logic [    MAX_CANDIDATES-1:0]         candidate_malformed,
    output logic [    MAX_CANDIDATES-1:0]         candidate_fits_in_beat,
    output logic [  MAX_CANDIDATES*8-1:0]         candidate_start_byte,
    output logic [ MAX_CANDIDATES*16-1:0]         candidate_length,
    output logic [  MAX_CANDIDATES*8-1:0]         candidate_end_byte
);
    function automatic logic [7:0] get_byte(input logic [511:0] data, input int idx);
        get_byte = data[idx*8 +: 8];
    endfunction

    function automatic logic keep_range_valid(input logic [63:0] keep, input int first_byte, input int last_byte);
        logic valid;
        valid = 1'b1;
        for (int i = first_byte; i <= last_byte; i++) begin
            if (i < 0 || i >= 64 || !keep[i]) valid = 1'b0;
        end
        keep_range_valid = valid;
    endfunction

    always_comb begin
        int len_lane;
        int payload_start;
        int payload_end;
        logic [15:0] msg_len;
        logic continue_scan;

        scan_valid           = beat_valid && beat_start_of_packet;
        truncated_header     = scan_valid && !keep_range_valid(beat_keep, 0, 19);
        packet_sequence      = '0;
        packet_message_count = '0;
        candidate_valid      = '0;
        candidate_malformed  = '0;
        candidate_fits_in_beat = '0;
        candidate_start_byte = '0;
        candidate_length     = '0;
        candidate_end_byte   = '0;

        if (scan_valid && !truncated_header) begin
            packet_sequence = {
                get_byte(beat_data, 10), get_byte(beat_data, 11),
                get_byte(beat_data, 12), get_byte(beat_data, 13),
                get_byte(beat_data, 14), get_byte(beat_data, 15),
                get_byte(beat_data, 16), get_byte(beat_data, 17)
            };
            packet_message_count = {get_byte(beat_data, 18), get_byte(beat_data, 19)};

            len_lane      = 20;
            continue_scan = (packet_message_count != 16'd0 && packet_message_count != 16'hFFFF);

            for (int c = 0; c < MAX_CANDIDATES; c++) begin
                if (continue_scan && c < packet_message_count &&
                    len_lane + 1 < 64 && keep_range_valid(beat_keep, len_lane, len_lane + 1)) begin
                    msg_len       = {get_byte(beat_data, len_lane), get_byte(beat_data, len_lane + 1)};
                    payload_start = len_lane + 2;
                    payload_end   = payload_start + int'(msg_len) - 1;

                    candidate_valid[c] = 1'b1;
                    candidate_malformed[c] = (msg_len == 16'd0);
                    candidate_fits_in_beat[c] = (msg_len != 16'd0 &&
                                                  payload_start < 64 &&
                                                  payload_end < 64 &&
                                                  keep_range_valid(beat_keep, payload_start, payload_end));
                    candidate_start_byte[c*8 +: 8] = 8'(payload_start);
                    candidate_length[c*16 +: 16]   = msg_len;
                    candidate_end_byte[c*8 +: 8]   = 8'(payload_end);

                    continue_scan = candidate_fits_in_beat[c];
                    len_lane      = payload_end + 1;
                end else begin
                    continue_scan = 1'b0;
                end
            end
        end
    end

endmodule
`default_nettype wire
