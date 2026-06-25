`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_512_boundary_scan_tb
// =============================================================================
// Unit test for the first-beat 512-bit MoldUDP64/ITCH boundary scanner.
module market_parser_512_boundary_scan_tb #(
    parameter string VECTOR_DIR = "verification/vectors"
);
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int MAX_CANDIDATES = 4;

    typedef logic [7:0] byte_t;

    logic                     beat_valid;
    logic [511:0]             beat_data;
    logic [ 63:0]             beat_keep;
    logic                     beat_start_of_packet;
    logic                     scan_valid;
    logic                     truncated_header;
    logic [63:0]              packet_sequence;
    logic [15:0]              packet_message_count;
    logic [MAX_CANDIDATES-1:0] candidate_valid;
    logic [MAX_CANDIDATES-1:0] candidate_malformed;
    logic [MAX_CANDIDATES-1:0] candidate_fits_in_beat;
    logic [MAX_CANDIDATES*8-1:0] candidate_start_byte;
    logic [MAX_CANDIDATES*16-1:0] candidate_length;
    logic [MAX_CANDIDATES*8-1:0] candidate_end_byte;

    int passed;
    int failed;

    byte_t mixed_packet_mem[MIXED_PACKET_BYTES];

    market_parser_512_boundary_scan #(
        .MAX_CANDIDATES(MAX_CANDIDATES)
    ) DUT (
        .beat_valid           (beat_valid),
        .beat_data            (beat_data),
        .beat_keep            (beat_keep),
        .beat_start_of_packet (beat_start_of_packet),
        .scan_valid           (scan_valid),
        .truncated_header     (truncated_header),
        .packet_sequence      (packet_sequence),
        .packet_message_count (packet_message_count),
        .candidate_valid      (candidate_valid),
        .candidate_malformed  (candidate_malformed),
        .candidate_fits_in_beat(candidate_fits_in_beat),
        .candidate_start_byte (candidate_start_byte),
        .candidate_length     (candidate_length),
        .candidate_end_byte   (candidate_end_byte)
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
        mixed_path = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        $readmemh(mixed_path, mixed_packet_mem);
    endtask

    task automatic build_first_beat();
        beat_data = '0;
        beat_keep = '0;
        for (int i = 0; i < 64; i++) begin
            beat_data[i*8 +: 8] = mixed_packet_mem[i];
            beat_keep[i] = 1'b1;
        end
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        beat_valid = 1'b0;
        beat_data = '0;
        beat_keep = '0;
        beat_start_of_packet = 1'b0;

        load_vectors();

        $display("\n========================================================");
        $display("MARKET PARSER 512-BIT BOUNDARY SCAN TESTS");
        $display("========================================================");

        build_first_beat();
        beat_valid = 1'b1;
        beat_start_of_packet = 1'b1;
        #1;

        check(scan_valid, "scan valid on first packet beat");
        check(!truncated_header, "full MoldUDP64 header present");
        check(packet_sequence == 64'd5, "packet sequence decoded in parallel");
        check(packet_message_count == 16'd8, "packet message count decoded in parallel");

        check(candidate_valid[0], "candidate 0 length field valid");
        check(candidate_length[0*16 +: 16] == 16'd40, "candidate 0 length decoded");
        check(candidate_start_byte[0*8 +: 8] == 8'd22, "candidate 0 payload start byte");
        check(candidate_end_byte[0*8 +: 8] == 8'd61, "candidate 0 payload end byte");
        check(candidate_fits_in_beat[0], "candidate 0 fits in first beat");
        check(!candidate_malformed[0], "candidate 0 is not malformed");

        check(candidate_valid[1], "candidate 1 length field valid at beat edge");
        check(candidate_length[1*16 +: 16] == 16'd31, "candidate 1 length decoded");
        check(candidate_start_byte[1*8 +: 8] == 8'd64, "candidate 1 payload starts next beat");
        check(candidate_end_byte[1*8 +: 8] == 8'd94, "candidate 1 projected payload end byte");
        check(!candidate_fits_in_beat[1], "candidate 1 does not fit in first beat");
        check(!candidate_valid[2], "candidate 2 not scanned after boundary leaves beat");

        beat_keep = 64'h0000_0000_0000_03ff;
        #1;
        check(truncated_header, "truncated header detected from keep mask");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_boundary_scan_tb failed");
    end

endmodule
`default_nettype wire
