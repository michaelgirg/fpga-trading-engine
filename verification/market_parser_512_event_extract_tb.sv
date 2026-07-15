`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_512_event_extract_tb
// =============================================================================
// Unit test for descriptor-to-normalized-event parallel extraction.
module market_parser_512_event_extract_tb #(
    parameter string VECTOR_DIR = "verification/vectors"
);
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int EXPECTED_EVENTS = 10;
    localparam int MIXED_EVENTS = 8;
    localparam int WINDOW_BYTES = 128;

    localparam logic [7:0] DESC_FLAG_CROSSES_BEAT = 8'h01;
    localparam logic [7:0] DESC_FLAG_BAD_FRAME    = 8'h04;

    typedef logic [7:0] byte_t;
    typedef logic [255:0] event_word_t;

    logic                  desc_valid;
    logic [          15:0] window_base_byte;
    logic [WINDOW_BYTES*8-1:0] window_data;
    logic [  WINDOW_BYTES-1:0] window_keep;
    logic [          15:0] desc_message_length;
    logic [          15:0] desc_message_start_byte;
    logic [          15:0] desc_message_end_byte;
    logic [           7:0] desc_flags;

    logic              event_valid;
    logic              event_complete;
    logic              event_supported;
    logic [255:0]      event_data;
    logic [63:0]       event_new_order_ref;
    logic [31:0]       extract_error_flags;

    int passed;
    int failed;

    byte_t       mixed_packet_mem  [MIXED_PACKET_BYTES];
    event_word_t expected_event_mem[EXPECTED_EVENTS];

    int expected_start[MIXED_EVENTS];
    int expected_end  [MIXED_EVENTS];
    int expected_len  [MIXED_EVENTS];
    logic [7:0] expected_desc_flags[MIXED_EVENTS];

    market_parser_512_event_extract #(
        .WINDOW_BYTES(WINDOW_BYTES)
    ) DUT (
        .desc_valid             (desc_valid),
        .window_base_byte       (window_base_byte),
        .window_data            (window_data),
        .window_keep            (window_keep),
        .desc_message_length    (desc_message_length),
        .desc_message_start_byte(desc_message_start_byte),
        .desc_message_end_byte  (desc_message_end_byte),
        .desc_flags             (desc_flags),
        .event_valid            (event_valid),
        .event_complete         (event_complete),
        .event_supported        (event_supported),
        .event_data             (event_data),
        .event_new_order_ref    (event_new_order_ref),
        .extract_error_flags    (extract_error_flags)
    );

    task automatic check(input bit condition, input string msg);
        if (condition) begin
            passed++;
            $display("PASS: %s", msg);
        end else begin
            failed++;
            $error("FAIL: %s", msg);
        end
    endtask

    task automatic load_vectors();
        string mixed_path;
        string expected_path;
        mixed_path    = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        expected_path = {VECTOR_DIR, "/expected_events.hex"};
        $readmemh(mixed_path, mixed_packet_mem);
        $readmemh(expected_path, expected_event_mem);
    endtask

    task automatic init_expected_descs();
        expected_start[0] = 22;  expected_end[0] = 61;  expected_len[0] = 40; expected_desc_flags[0] = 8'h00;
        expected_start[1] = 64;  expected_end[1] = 94;  expected_len[1] = 31; expected_desc_flags[1] = 8'h00;
        expected_start[2] = 97;  expected_end[2] = 132; expected_len[2] = 36; expected_desc_flags[2] = DESC_FLAG_CROSSES_BEAT;
        expected_start[3] = 135; expected_end[3] = 157; expected_len[3] = 23; expected_desc_flags[3] = 8'h00;
        expected_start[4] = 160; expected_end[4] = 178; expected_len[4] = 19; expected_desc_flags[4] = 8'h00;
        expected_start[5] = 181; expected_end[5] = 215; expected_len[5] = 35; expected_desc_flags[5] = DESC_FLAG_CROSSES_BEAT;
        expected_start[6] = 218; expected_end[6] = 261; expected_len[6] = 44; expected_desc_flags[6] = DESC_FLAG_CROSSES_BEAT;
        expected_start[7] = 264; expected_end[7] = 275; expected_len[7] = 12; expected_desc_flags[7] = 8'h00;
    endtask

    task automatic build_window(input int base_offset, input bit include_next_beat);
        int packet_idx;
        window_base_byte = base_offset[15:0];
        window_data = '0;
        window_keep = '0;
        for (int lane = 0; lane < WINDOW_BYTES; lane++) begin
            packet_idx = base_offset + lane;
            if (packet_idx < MIXED_PACKET_BYTES && (include_next_beat || lane < 64)) begin
                window_data[lane*8 +: 8] = mixed_packet_mem[packet_idx];
                window_keep[lane] = 1'b1;
            end
        end
    endtask

    task automatic drive_desc(input int msg_idx, input bit include_next_beat, input logic [7:0] extra_flags);
        int base_offset;
        base_offset = (expected_start[msg_idx] / 64) * 64;
        build_window(base_offset, include_next_beat);
        desc_valid              = 1'b1;
        desc_message_length     = expected_len[msg_idx][15:0];
        desc_message_start_byte = expected_start[msg_idx][15:0];
        desc_message_end_byte   = expected_end[msg_idx][15:0];
        desc_flags              = expected_desc_flags[msg_idx] | extra_flags;
        #1;
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        desc_valid = 1'b0;
        window_base_byte = '0;
        window_data = '0;
        window_keep = '0;
        desc_message_length = '0;
        desc_message_start_byte = '0;
        desc_message_end_byte = '0;
        desc_flags = '0;

        load_vectors();
        init_expected_descs();

        $display("\n========================================================");
        $display("MARKET PARSER 512-BIT EVENT EXTRACT TESTS");
        $display("========================================================");

        for (int i = 0; i < MIXED_EVENTS; i++) begin
            drive_desc(i, 1'b1, 8'h00);
            check(event_valid, $sformatf("event %0d valid", i));
            check(event_complete, $sformatf("event %0d complete", i));
            check(event_data == expected_event_mem[i + 2],
                  $sformatf("event %0d matches golden normalized vector", i));
            if (i == 5) begin
                check(event_new_order_ref == 64'h9999_AAAA_BBBB_CCCC,
                      "replace event extracts new order reference");
            end else begin
                check(event_new_order_ref == 64'd0,
                      $sformatf("event %0d has no replacement reference", i));
            end
            if (i == 7) begin
                check(!event_supported, "unknown ITCH message marked unsupported");
                check(extract_error_flags[3], "unknown ITCH message sets extractor unknown error");
            end else begin
                check(event_supported, $sformatf("event %0d supported", i));
            end
        end

        drive_desc(2, 1'b0, 8'h00);
        check(event_valid, "cross-beat event valid with incomplete window");
        check(!event_complete, "cross-beat event incomplete without next beat");
        check((event_data[239:232] & FLAG_MALFORMED) != 8'h00, "incomplete window sets malformed event flag");
        check(extract_error_flags[0], "incomplete window sets extractor incomplete error");

        drive_desc(0, 1'b1, DESC_FLAG_BAD_FRAME);
        check(event_valid, "bad-frame event valid");
        check(event_complete, "bad-frame event complete");
        check((event_data[239:232] & FLAG_MALFORMED) != 8'h00, "bad-frame descriptor maps to malformed event flag");
        check(extract_error_flags[2], "bad-frame descriptor sets extractor bad-frame error");

        desc_valid = 1'b0;
        #1;
        check(!event_valid, "event valid drops when descriptor is not valid");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_event_extract_tb failed");
    end

endmodule
`default_nettype wire
