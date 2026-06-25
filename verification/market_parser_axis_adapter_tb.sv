`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_axis_adapter_tb
// =============================================================================
// Parameterized smoke test for wide AXI-stream-style input profiles.
module market_parser_axis_adapter_tb #(
    parameter realtime CLK_PERIOD = 10ns,
    parameter string   VECTOR_DIR = "verification/vectors",
    parameter int      DATA_WIDTH = 256
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int OUTPUT_BUS_WIDTH = 256;
    localparam int KEEP_WIDTH = DATA_WIDTH / 8;
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int EXPECTED_EVENTS = 10;

    typedef logic [7:0] byte_t;
    typedef logic [OUTPUT_BUS_WIDTH-1:0] event_word_t;

    logic clk = 1'b0;
    logic rst;

    logic                         data_in_valid;
    logic                         data_in_ready;
    logic [    DATA_WIDTH-1:0]    data_in_data;
    logic [    KEEP_WIDTH-1:0]    data_in_keep;
    logic                         data_in_last;

    logic                          data_out_valid;
    logic                          data_out_ready;
    logic [  OUTPUT_BUS_WIDTH-1:0] data_out_data;
    logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep;
    logic                          data_out_last;

    logic        gap_error;
    logic        malformed_error;
    logic        unknown_msg_type;
    logic [63:0] expected_sequence;
    logic [63:0] packet_sequence;
    logic [31:0] packet_count;
    logic [31:0] message_count;
    logic [31:0] event_count;
    logic [31:0] error_count;

    int passed;
    int failed;
    int input_beat_count;
    int expected_beat_count;
    longint cycle_count;
    longint packet_start_cycle;
    int event_wait_total_cycles;
    int event_wait_count;
    int event_wait_min_cycles;
    int event_wait_max_cycles;
    int first_event_latency_cycles;

    byte_t       mixed_packet_mem  [MIXED_PACKET_BYTES];
    event_word_t expected_event_mem[EXPECTED_EVENTS];

    market_parser_axis_adapter #(
        .DATA_WIDTH      (DATA_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) DUT (
        .clk              (clk),
        .rst              (rst),
        .data_in_valid    (data_in_valid),
        .data_in_ready    (data_in_ready),
        .data_in_data     (data_in_data),
        .data_in_keep     (data_in_keep),
        .data_in_last     (data_in_last),
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

    initial begin
        if (DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0) begin
            $fatal(1, "DATA_WIDTH must be a positive multiple of 8");
        end
    end

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    always_ff @(posedge clk) begin
        if (rst) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end

    task automatic reset_dut();
        rst            = 1'b1;
        data_in_valid  = 1'b0;
        data_in_data   = '0;
        data_in_keep   = '0;
        data_in_last   = 1'b0;
        data_out_ready = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
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

    task automatic send_word(input logic [DATA_WIDTH-1:0] word_data,
                             input logic [KEEP_WIDTH-1:0] word_keep,
                             input bit                    word_last);
        @(negedge clk);
        data_in_valid = 1'b1;
        data_in_data  = word_data;
        data_in_keep  = word_keep;
        data_in_last  = word_last;
        while (!data_in_ready) @(negedge clk);
        @(negedge clk);
        input_beat_count++;
        data_in_valid = 1'b0;
        data_in_data  = '0;
        data_in_keep  = '0;
        data_in_last  = 1'b0;
    endtask

    task automatic send_packet_axis(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int bytes_left;
        int beat_bytes;
        logic [DATA_WIDTH-1:0] word_data;
        logic [KEEP_WIDTH-1:0] word_keep;

        offset = 0;
        packet_start_cycle = cycle_count;
        while (offset < packet_bytes) begin
            bytes_left = packet_bytes - offset;
            beat_bytes = (bytes_left >= KEEP_WIDTH) ? KEEP_WIDTH : bytes_left;
            word_data  = '0;
            word_keep  = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                word_data[lane*8 +: 8] = packet_mem[offset + lane];
                word_keep[lane]        = 1'b1;
            end
            send_word(word_data, word_keep, offset + beat_bytes >= packet_bytes);
            offset += beat_bytes;
        end
    endtask

    task automatic wait_for_event(output logic [OUTPUT_BUS_WIDTH-1:0] event_data,
                                  input string msg);
        int cycles;
        cycles = 0;
        data_out_ready = 1'b0;
        while (!data_out_valid && cycles < 800) begin
            @(posedge clk);
            cycles++;
        end
        check(data_out_valid, {msg, " became valid"});
        record_event_wait(cycles);
        event_data = data_out_data;
        data_out_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        data_out_ready = 1'b0;
    endtask

    task automatic record_event_wait(input int wait_cycles);
        if (event_wait_count == 0) first_event_latency_cycles = int'(cycle_count - packet_start_cycle);
        if (event_wait_count == 0 || wait_cycles < event_wait_min_cycles) event_wait_min_cycles = wait_cycles;
        if (wait_cycles > event_wait_max_cycles) event_wait_max_cycles = wait_cycles;
        event_wait_total_cycles += wait_cycles;
        event_wait_count++;
    endtask

    task automatic report_stats();
        $display("========================================================");
        $display("MARKET PARSER AXIS ADAPTER REPORT (%0d-bit input)", DATA_WIDTH);
        $display("========================================================");
        $display("Input beats: observed=%0d expected=%0d keep_width=%0d",
                 input_beat_count, expected_beat_count, KEEP_WIDTH);
        $display("DUT counters: packets=%0d messages=%0d events=%0d errors=%0d",
                 packet_count, message_count, event_count, error_count);
        $display("Sticky flags: gap=%0b malformed=%0b unknown=%0b",
                 gap_error, malformed_error, unknown_msg_type);
        $display("First-event latency from first input beat: %0d cycles", first_event_latency_cycles);
        if (event_wait_count > 0) begin
            $display("Event wait after request: min=%0d max=%0d avg=%0d cycles over %0d waits",
                     event_wait_min_cycles, event_wait_max_cycles,
                     event_wait_total_cycles / event_wait_count, event_wait_count);
        end
        $display("========================================================");
    endtask

    initial begin : run_tests
        logic [OUTPUT_BUS_WIDTH-1:0] event_data;

        passed = 0;
        failed = 0;
        input_beat_count = 0;
        expected_beat_count = (MIXED_PACKET_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
        packet_start_cycle = 0;
        event_wait_total_cycles = 0;
        event_wait_count = 0;
        event_wait_min_cycles = 0;
        event_wait_max_cycles = 0;
        first_event_latency_cycles = 0;
        reset_dut();
        load_vectors();

        $display("\n========================================================");
        $display("MARKET PARSER AXIS ADAPTER TESTS (%0d-bit input)", DATA_WIDTH);
        $display("========================================================");

        fork
            send_packet_axis(MIXED_PACKET_BYTES, mixed_packet_mem);
            begin
                for (int i = 2; i < EXPECTED_EVENTS; i++) begin
                    wait_for_event(event_data, $sformatf("%0d-bit axis event %0d", DATA_WIDTH, i - 2));
                    check(event_data == expected_event_mem[i],
                          $sformatf("%0d-bit axis event %0d matches generated vector", DATA_WIDTH, i - 2));
                end
            end
        join

        check(input_beat_count == expected_beat_count, "axis input beat count");
        check(packet_count == 32'd1, "axis packet counter");
        check(message_count == 32'd8, "axis message counter");
        check(event_count == 32'd8, "axis event counter");
        check(error_count == 32'd1, "axis unknown-message error counter");
        check(unknown_msg_type, "axis sticky unknown output set");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");
        report_stats();

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_axis_adapter_tb failed");
    end

endmodule
`default_nettype wire
