`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_512_pipeline_tb
// =============================================================================
// Integrated test for the cut-through 512-bit parallel event pipeline.
module market_parser_512_pipeline_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter int      EXTRACTION_WINDOW_BYTES = 256,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int CUSTOM_PACKET_BYTES = 256;
    localparam int LONG_PACKET_BYTES = 202;
    localparam int DENSE_SYSTEM_EVENTS = 10;
    localparam int DENSE_PACKET_BYTES = 20 + (DENSE_SYSTEM_EVENTS * 14);
    localparam int EXPECTED_EVENTS = 10;
    localparam int MIXED_EVENTS = 8;

    typedef logic [7:0] byte_t;
    typedef logic [255:0] event_word_t;

    logic clk = 1'b0;
    logic rst;

    logic         s_axis_rx_tvalid;
    logic         s_axis_rx_tready;
    logic [511:0] s_axis_rx_tdata;
    logic [ 63:0] s_axis_rx_tkeep;
    logic         s_axis_rx_tlast;
    logic         s_axis_rx_tuser_bad_frame;

    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;
    logic [ 63:0] event_new_order_ref;
    logic [ 31:0] event_keep;
    logic         event_last;

    logic [31:0] packet_count;
    logic [31:0] descriptor_count;
    logic [31:0] event_count;
    logic [31:0] extractor_error_count;
    logic [31:0] bad_frame_count;

    int passed;
    int failed;

    byte_t       mixed_packet_mem  [MIXED_PACKET_BYTES];
    byte_t       custom_packet_mem [CUSTOM_PACKET_BYTES];
    event_word_t expected_event_mem[EXPECTED_EVENTS];

    market_parser_512_pipeline #(
        .EXTRACTION_WINDOW_BYTES(EXTRACTION_WINDOW_BYTES)
    ) DUT (
        .clk                       (clk),
        .rst                       (rst),
        .sequence_rearm            (1'b0),
        .s_axis_rx_tvalid          (s_axis_rx_tvalid),
        .s_axis_rx_tready          (s_axis_rx_tready),
        .s_axis_rx_tdata           (s_axis_rx_tdata),
        .s_axis_rx_tkeep           (s_axis_rx_tkeep),
        .s_axis_rx_tlast           (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame (s_axis_rx_tuser_bad_frame),
        .event_valid               (event_valid),
        .event_ready               (event_ready),
        .event_data                (event_data),
        .event_new_order_ref       (event_new_order_ref),
        .event_keep                (event_keep),
        .event_last                (event_last),
        .packet_count              (packet_count),
        .descriptor_count          (descriptor_count),
        .event_count               (event_count),
        .extractor_error_count     (extractor_error_count),
        .bad_frame_count           (bad_frame_count),
        .session_change_pulse      (),
        .end_of_session_pulse      ()
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic reset_dut();
        rst                       = 1'b1;
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
        event_ready               = 1'b0;
        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);
    endtask

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

    task automatic send_beat(input logic [511:0] beat_data,
                             input logic [ 63:0] beat_keep,
                             input bit           beat_last,
                             input bit           beat_bad);
        @(negedge clk);
        s_axis_rx_tvalid          = 1'b1;
        s_axis_rx_tdata           = beat_data;
        s_axis_rx_tkeep           = beat_keep;
        s_axis_rx_tlast           = beat_last;
        s_axis_rx_tuser_bad_frame = beat_bad;
        while (!s_axis_rx_tready) @(negedge clk);
        @(negedge clk);
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
    endtask

    task automatic send_packet(input int packet_bytes,
                               input byte_t packet_mem[],
                               input bit bad_first_beat,
                               input bit insert_gap);
        send_packet_slice(packet_bytes, packet_mem, 0, bad_first_beat, insert_gap);
    endtask

    task automatic send_packet_slice(input int packet_bytes,
                                     input byte_t packet_mem[],
                                     input int start_offset,
                                     input bit bad_first_beat,
                                     input bit insert_gap);
        int offset;
        int bytes_left;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [ 63:0] beat_keep;

        offset = start_offset;
        while (offset < packet_bytes) begin
            bytes_left = packet_bytes - offset;
            beat_bytes = (bytes_left >= 64) ? 64 : bytes_left;
            beat_data = '0;
            beat_keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                beat_keep[lane] = 1'b1;
            end
            send_beat(beat_data, beat_keep, offset + beat_bytes >= packet_bytes,
                      bad_first_beat && offset == 0);
            offset += beat_bytes;
            if (insert_gap) begin
                repeat ((offset / 64) % 3) @(posedge clk);
            end
        end
    endtask

    task automatic send_packet_beat_at(input int packet_bytes,
                                       input byte_t packet_mem[],
                                       input int offset,
                                       input bit beat_bad);
        int bytes_left;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [ 63:0] beat_keep;

        bytes_left = packet_bytes - offset;
        beat_bytes = (bytes_left >= 64) ? 64 : bytes_left;
        beat_data = '0;
        beat_keep = '0;
        for (int lane = 0; lane < beat_bytes; lane++) begin
            beat_data[lane*8 +: 8] = packet_mem[offset + lane];
            beat_keep[lane] = 1'b1;
        end
        send_beat(beat_data, beat_keep, offset + beat_bytes >= packet_bytes, beat_bad);
    endtask

    task automatic wait_event(input string msg);
        int cycles;
        cycles = 0;
        while (!event_valid && cycles < 400) begin
            @(posedge clk);
            cycles++;
        end
        check(event_valid, {msg, " event valid"});
    endtask

    task automatic accept_current_event();
        @(negedge clk);
        event_ready = 1'b1;
        @(negedge clk);
        event_ready = 1'b0;
    endtask

    task automatic check_and_accept_event(input int expected_idx, input bit expected_last);
        wait_event($sformatf("event %0d", expected_idx));
        check(event_keep == 32'hffff_ffff, $sformatf("event %0d keep all bytes", expected_idx));
        check(event_data == expected_event_mem[expected_idx],
              $sformatf("event %0d matches golden normalized vector", expected_idx));
        check(event_new_order_ref == ((expected_idx == 7) ? 64'h9999_AAAA_BBBB_CCCC : 64'd0),
              $sformatf("event %0d replacement reference", expected_idx));
        check(event_last == expected_last, $sformatf("event %0d last flag", expected_idx));
        accept_current_event();
    endtask

    task automatic check_first_event_backpressure();
        logic [255:0] held_data;
        logic held_last;

        wait_event("first mixed");
        held_data = event_data;
        held_last = event_last;
        repeat (3) begin
            @(posedge clk);
            check(event_valid, "event valid stays high during output backpressure");
            check(event_data == held_data, "event data stable during output backpressure");
            check(event_last == held_last, "event last stable during output backpressure");
        end
        check(event_data == expected_event_mem[2], "first mixed event matches golden vector");
        check(!event_last, "first mixed event is not last");
        accept_current_event();
    endtask

    task automatic check_cutthrough_first_event_then_finish_packet();
        logic [255:0] held_data;
        logic         held_last;

        send_packet_beat_at(MIXED_PACKET_BYTES, mixed_packet_mem, 0, 1'b0);
        wait_event("cut-through first mixed before packet end");

        held_data = event_data;
        held_last = event_last;
        check(packet_count == 32'd0, "cut-through event appears before packet counter increments");
        check(event_count == 32'd1, "cut-through event counter increments before packet end");
        check(event_data == expected_event_mem[2], "cut-through first event matches golden vector");
        check(!event_last, "cut-through first event is not last");

        send_packet_slice(MIXED_PACKET_BYTES, mixed_packet_mem, 64, 1'b0, 1'b1);
        repeat (3) begin
            @(posedge clk);
            check(event_valid, "held cut-through event remains valid while later beats arrive");
            check(event_data == held_data, "held cut-through event data stable while later beats arrive");
            check(event_last == held_last, "held cut-through event last stable while later beats arrive");
        end

        check(packet_count == 32'd1, "packet counter increments after cut-through packet end");
        accept_current_event();
    endtask

    task automatic build_bad_frame_packet();
        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd20;
        custom_packet_mem[19] = 8'd1;
        custom_packet_mem[21] = 8'd12;
        custom_packet_mem[22] = "S";
        for (int i = 23; i <= 33; i++) custom_packet_mem[i] = 8'h11;
    endtask

    task automatic build_truncated_packet();
        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd21;
        custom_packet_mem[19] = 8'd1;
        custom_packet_mem[21] = 8'd40;
        custom_packet_mem[22] = "A";
        for (int i = 23; i < 40; i++) custom_packet_mem[i] = 8'h22;
    endtask

    task automatic build_dense_system_event_packet();
        int len_offset;
        int msg_start;

        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd64;
        custom_packet_mem[19] = DENSE_SYSTEM_EVENTS[7:0];

        for (int i = 0; i < DENSE_SYSTEM_EVENTS; i++) begin
            len_offset = 20 + (i * 14);
            msg_start = len_offset + 2;
            custom_packet_mem[len_offset] = 8'h00;
            custom_packet_mem[len_offset + 1] = 8'd12;
            custom_packet_mem[msg_start] = "S";
            custom_packet_mem[msg_start + 1] = 8'h01;
            custom_packet_mem[msg_start + 2] = 8'(i);
            custom_packet_mem[msg_start + 3] = 8'h02;
            custom_packet_mem[msg_start + 4] = 8'(i);
            custom_packet_mem[msg_start + 5] = 8'h00;
            custom_packet_mem[msg_start + 6] = 8'h00;
            custom_packet_mem[msg_start + 7] = 8'h00;
            custom_packet_mem[msg_start + 8] = 8'h00;
            custom_packet_mem[msg_start + 9] = 8'h40;
            custom_packet_mem[msg_start + 10] = 8'(i);
            custom_packet_mem[msg_start + 11] = "O";
        end
    endtask

    task automatic check_and_accept_dense_system_event(input int idx, input bit expected_last);
        logic [15:0] expected_stock_locate;
        logic [15:0] expected_tracking_number;
        logic [47:0] expected_timestamp;

        expected_stock_locate = {8'h01, idx[7:0]};
        expected_tracking_number = {8'h02, idx[7:0]};
        expected_timestamp = {40'h0000000040, idx[7:0]};

        wait_event($sformatf("dense system event %0d", idx));
        check(event_keep == 32'hffff_ffff, $sformatf("dense system event %0d keep all bytes", idx));
        check(event_data[7:0] == EVENT_SYSTEM, $sformatf("dense system event %0d kind", idx));
        check(event_data[15:8] == "S", $sformatf("dense system event %0d message type", idx));
        check(event_data[31:16] == expected_stock_locate,
              $sformatf("dense system event %0d stock locate", idx));
        check(event_data[47:32] == expected_tracking_number,
              $sformatf("dense system event %0d tracking number", idx));
        check(event_data[95:48] == expected_timestamp,
              $sformatf("dense system event %0d timestamp", idx));
        check(event_data[239:232] == 8'h00, $sformatf("dense system event %0d flags", idx));
        check(event_last == expected_last, $sformatf("dense system event %0d last flag", idx));
        accept_current_event();
    endtask

    task automatic build_long_unknown_packet();
        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd22;
        custom_packet_mem[19] = 8'd1;
        custom_packet_mem[20] = 8'd0;
        custom_packet_mem[21] = 8'd180;
        custom_packet_mem[22] = "Z";
        custom_packet_mem[23] = 8'h12;
        custom_packet_mem[24] = 8'h34;
        custom_packet_mem[25] = 8'h56;
        custom_packet_mem[26] = 8'h78;
        for (int i = 27; i < LONG_PACKET_BYTES; i++) begin
            custom_packet_mem[i] = 8'(i);
        end
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        load_vectors();
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER 512-BIT PIPELINE TESTS");
        $display("Extraction window bytes: %0d", EXTRACTION_WINDOW_BYTES);
        $display("========================================================");

        check_cutthrough_first_event_then_finish_packet();
        for (int i = 1; i < MIXED_EVENTS; i++) begin
            check_and_accept_event(i + 2, i == MIXED_EVENTS - 1);
        end
        repeat (4) @(posedge clk);
        check(packet_count == 32'd1, "mixed packet count");
        check(descriptor_count == 32'd8, "mixed descriptor count");
        check(event_count == 32'd8, "mixed event count");
        check(extractor_error_count == 32'd1, "mixed unknown message increments extractor error count");
        check(bad_frame_count == 32'd0, "mixed bad-frame count");

        reset_dut();
        build_bad_frame_packet();
        send_packet(34, custom_packet_mem, 1'b1, 1'b0);
        wait_event("bad-frame");
        check((event_data[239:232] & FLAG_MALFORMED) != 8'h00,
              "bad-frame input maps to malformed event flag");
        accept_current_event();
        repeat (3) @(posedge clk);
        check(packet_count == 32'd1, "bad-frame packet count");
        check(descriptor_count == 32'd1, "bad-frame descriptor count");
        check(event_count == 32'd1, "bad-frame event count");
        check(extractor_error_count == 32'd1, "bad-frame increments extractor error count");
        check(bad_frame_count == 32'd1, "bad-frame beat count");

        reset_dut();
        build_truncated_packet();
        send_packet(40, custom_packet_mem, 1'b0, 1'b0);
        wait_event("truncated");
        check((event_data[239:232] & FLAG_MALFORMED) != 8'h00,
              "truncated packet maps to malformed event flag");
        check(event_last, "truncated packet emits one last event");
        accept_current_event();
        repeat (3) @(posedge clk);
        check(packet_count == 32'd1, "truncated packet count");
        check(descriptor_count == 32'd1, "truncated descriptor count");
        check(event_count == 32'd1, "truncated event count");
        check(extractor_error_count == 32'd1, "truncated packet increments extractor error count");

        reset_dut();
        build_dense_system_event_packet();
        fork
            send_packet(DENSE_PACKET_BYTES, custom_packet_mem, 1'b0, 1'b0);
            begin
                for (int i = 0; i < DENSE_SYSTEM_EVENTS; i++) begin
                    check_and_accept_dense_system_event(i, i == DENSE_SYSTEM_EVENTS - 1);
                end
            end
        join
        repeat (4) @(posedge clk);
        check(packet_count == 32'd1, "dense system packet count");
        check(descriptor_count == DENSE_SYSTEM_EVENTS[31:0], "dense system descriptor count");
        check(event_count == DENSE_SYSTEM_EVENTS[31:0], "dense system event count");
        check(extractor_error_count == 32'd0, "dense system extractor error count");

        reset_dut();
        build_long_unknown_packet();
        send_packet(LONG_PACKET_BYTES, custom_packet_mem, 1'b0, 1'b0);
        wait_event("long four-beat unknown");
        check((event_data[239:232] & FLAG_UNKNOWN) != 8'h00,
              "long four-beat unknown message sets unknown flag");
        if (EXTRACTION_WINDOW_BYTES >= 256) begin
            check((event_data[239:232] & FLAG_MALFORMED) == 8'h00,
                  "long four-beat message is complete with expanded window");
        end else begin
            check((event_data[239:232] & FLAG_MALFORMED) != 8'h00,
                  "long four-beat message is malformed when window is too small");
        end
        if (EXTRACTION_WINDOW_BYTES >= 256) begin
            check(event_last, "long four-beat packet emits one last event");
        end else begin
            check(!event_last, "long four-beat incomplete early event is not marked last");
        end
        accept_current_event();
        repeat (3) @(posedge clk);
        check(packet_count == 32'd1, "long four-beat packet count");
        check(descriptor_count == 32'd1, "long four-beat descriptor count");
        check(event_count == 32'd1, "long four-beat event count");
        check(extractor_error_count == 32'd1, "long four-beat unknown increments extractor error count only once");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_pipeline_tb failed");
    end

endmodule
`default_nettype wire
