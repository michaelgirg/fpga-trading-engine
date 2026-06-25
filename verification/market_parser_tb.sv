`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_tb
// =============================================================================
module market_parser_tb #(
    parameter realtime CLK_PERIOD = 10ns
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int INPUT_BUS_WIDTH = 8;
    localparam int OUTPUT_BUS_WIDTH = 256;

    logic clk = 1'b0;
    logic rst;

    logic                         data_in_valid;
    logic                         data_in_ready;
    logic [   INPUT_BUS_WIDTH-1:0] data_in_data;
    logic [ INPUT_BUS_WIDTH/8-1:0] data_in_keep;
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

    market_parser #(
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
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

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic reset_dut();
        rst            = 1'b1;
        data_in_valid  = 1'b0;
        data_in_data   = '0;
        data_in_keep   = '0;
        data_in_last   = 1'b0;
        data_out_ready = 1'b1;
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

    task automatic send_byte(input logic [7:0] value, input bit last);
        @(negedge clk);
        data_in_valid = 1'b1;
        data_in_data  = value;
        data_in_keep  = 1'b1;
        data_in_last  = last;
        while (!data_in_ready) @(negedge clk);
        @(negedge clk);
        data_in_valid = 1'b0;
        data_in_data  = '0;
        data_in_keep  = '0;
        data_in_last  = 1'b0;
    endtask

    task automatic send_be16(input logic [15:0] value, input bit last);
        send_byte(value[15:8], 1'b0);
        send_byte(value[7:0], last);
    endtask

    task automatic send_be32(input logic [31:0] value, input bit last);
        send_byte(value[31:24], 1'b0);
        send_byte(value[23:16], 1'b0);
        send_byte(value[15:8], 1'b0);
        send_byte(value[7:0], last);
    endtask

    task automatic send_be48(input logic [47:0] value);
        send_byte(value[47:40], 1'b0);
        send_byte(value[39:32], 1'b0);
        send_byte(value[31:24], 1'b0);
        send_byte(value[23:16], 1'b0);
        send_byte(value[15:8], 1'b0);
        send_byte(value[7:0], 1'b0);
    endtask

    task automatic send_be64(input logic [63:0] value);
        send_byte(value[63:56], 1'b0);
        send_byte(value[55:48], 1'b0);
        send_byte(value[47:40], 1'b0);
        send_byte(value[39:32], 1'b0);
        send_byte(value[31:24], 1'b0);
        send_byte(value[23:16], 1'b0);
        send_byte(value[15:8], 1'b0);
        send_byte(value[7:0], 1'b0);
    endtask

    task automatic send_header(input logic [63:0] seq_num, input logic [15:0] msg_count);
        send_byte("S", 1'b0);
        send_byte("I", 1'b0);
        send_byte("M", 1'b0);
        send_byte("0", 1'b0);
        send_byte("0", 1'b0);
        send_byte("0", 1'b0);
        send_byte("0", 1'b0);
        send_byte("0", 1'b0);
        send_byte("0", 1'b0);
        send_byte("1", 1'b0);
        send_be64(seq_num);
        send_be16(msg_count, 1'b0);
    endtask

    task automatic send_add_order_packet(input logic [63:0] seq_num);
        send_header(seq_num, 16'd1);
        send_be16(16'd36, 1'b0);
        send_byte("A", 1'b0);
        send_be16(16'h1234, 1'b0);
        send_be16(16'h5678, 1'b0);
        send_be48(48'h0102_0304_0506);
        send_be64(64'h1111_2222_3333_4444);
        send_byte("B", 1'b0);
        send_be32(32'd100, 1'b0);
        send_byte("A", 1'b0);
        send_byte("B", 1'b0);
        send_byte("C", 1'b0);
        send_byte("D", 1'b0);
        send_byte(" ", 1'b0);
        send_byte(" ", 1'b0);
        send_byte(" ", 1'b0);
        send_byte(" ", 1'b0);
        send_be32(32'd1234500, 1'b1);
    endtask

    task automatic send_system_event_packet(input logic [63:0] seq_num);
        send_header(seq_num, 16'd1);
        send_be16(16'd12, 1'b0);
        send_byte("S", 1'b0);
        send_be16(16'h0001, 1'b0);
        send_be16(16'h0002, 1'b0);
        send_be48(48'h0000_0000_0010);
        send_byte("O", 1'b1);
    endtask

    task automatic wait_for_event(output logic [OUTPUT_BUS_WIDTH-1:0] event_data);
        int cycles;
        cycles = 0;
        while (!data_out_valid && cycles < 200) begin
            @(posedge clk);
            cycles++;
        end
        check(data_out_valid, "event became valid");
        event_data = data_out_data;
        @(posedge clk);
    endtask

    initial begin : run_tests
        logic [OUTPUT_BUS_WIDTH-1:0] event_data;

        passed = 0;
        failed = 0;
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER TESTS");
        $display("========================================================");

        send_add_order_packet(64'd1);
        wait_for_event(event_data);
        check(event_data[7:0]     == EVENT_ADD, "add order classified");
        check(event_data[15:8]    == "A", "ITCH message type A preserved");
        check(event_data[31:16]   == 16'h1234, "stock locate decoded");
        check(event_data[47:32]   == 16'h5678, "tracking number decoded");
        check(event_data[95:48]   == 48'h0102_0304_0506, "timestamp decoded");
        check(event_data[159:96]  == 64'h1111_2222_3333_4444, "order ref decoded");
        check(event_data[191:160] == 32'd100, "shares decoded");
        check(event_data[223:192] == 32'd1234500, "price decoded");
        check(event_data[231:224] == "B", "side decoded");

        send_system_event_packet(64'd3);
        wait_for_event(event_data);
        check(event_data[7:0] == EVENT_SYSTEM, "system event classified");
        check((event_data[239:232] & FLAG_GAP) != 8'h00, "gap flag set on skipped sequence");
        check(gap_error, "sticky gap error output set");

        check(packet_count == 32'd2, "packet counter");
        check(message_count == 32'd2, "message counter");
        check(event_count == 32'd2, "event counter");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_tb failed");
    end

endmodule
`default_nettype wire
