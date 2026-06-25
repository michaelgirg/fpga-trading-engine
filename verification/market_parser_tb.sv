`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_tb
// =============================================================================
module market_parser_tb #(
    parameter realtime CLK_PERIOD = 10ns,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int INPUT_BUS_WIDTH = 8;
    localparam int OUTPUT_BUS_WIDTH = 256;
    localparam int ADD_ORDER_PACKET_BYTES = 58;
    localparam int GAP_SYSTEM_PACKET_BYTES = 34;
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int TRUNCATED_PACKET_BYTES = 27;
    localparam int HEARTBEAT_PACKET_BYTES = 20;
    localparam int END_SESSION_PACKET_BYTES = 20;
    localparam int EXPECTED_EVENTS = 10;

    typedef logic [7:0] byte_t;
    typedef logic [OUTPUT_BUS_WIDTH-1:0] event_word_t;

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

    byte_t       add_order_packet_mem  [ADD_ORDER_PACKET_BYTES];
    byte_t       gap_system_packet_mem [GAP_SYSTEM_PACKET_BYTES];
    byte_t       mixed_packet_mem      [MIXED_PACKET_BYTES];
    byte_t       truncated_packet_mem  [TRUNCATED_PACKET_BYTES];
    byte_t       heartbeat_packet_mem  [HEARTBEAT_PACKET_BYTES];
    byte_t       end_session_packet_mem[END_SESSION_PACKET_BYTES];
    event_word_t expected_event_mem    [EXPECTED_EVENTS];

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

    task automatic load_vectors();
        string add_path;
        string gap_path;
        string mixed_path;
        string truncated_path;
        string heartbeat_path;
        string end_session_path;
        string expected_path;
        add_path       = {VECTOR_DIR, "/add_order_packet.hex"};
        gap_path       = {VECTOR_DIR, "/gap_system_event_packet.hex"};
        mixed_path     = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        truncated_path = {VECTOR_DIR, "/truncated_packet.hex"};
        heartbeat_path = {VECTOR_DIR, "/heartbeat_packet.hex"};
        end_session_path = {VECTOR_DIR, "/end_session_packet.hex"};
        expected_path  = {VECTOR_DIR, "/expected_events.hex"};
        $readmemh(add_path, add_order_packet_mem);
        $readmemh(gap_path, gap_system_packet_mem);
        $readmemh(mixed_path, mixed_packet_mem);
        $readmemh(truncated_path, truncated_packet_mem);
        $readmemh(heartbeat_path, heartbeat_packet_mem);
        $readmemh(end_session_path, end_session_packet_mem);
        $readmemh(expected_path, expected_event_mem);
    endtask

    task automatic send_packet_from_mem(input int packet_bytes, input byte_t packet_mem[]);
        for (int i = 0; i < packet_bytes; i++) begin
            send_byte(packet_mem[i], i == packet_bytes - 1);
        end
    endtask

    task automatic send_be16(input logic [15:0] value, input bit last);
        send_byte(value[15:8], 1'b0);
        send_byte(value[7:0], last);
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

    task automatic send_zero_length_message_packet(input logic [63:0] seq_num);
        send_header(seq_num, 16'd1);
        send_be16(16'd0, 1'b1);
    endtask

    task automatic wait_for_event(output logic [OUTPUT_BUS_WIDTH-1:0] event_data,
                                  input int ready_stall_cycles = 0);
        int cycles;
        cycles = 0;
        data_out_ready = 1'b0;
        while (!data_out_valid && cycles < 200) begin
            @(posedge clk);
            cycles++;
        end
        check(data_out_valid, "event became valid");
        repeat (ready_stall_cycles) @(posedge clk);
        event_data = data_out_data;
        data_out_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        data_out_ready = 1'b0;
    endtask

    task automatic check_no_event(input int cycles, input string msg);
        bit saw_event;
        saw_event = 1'b0;
        data_out_ready = 1'b0;
        repeat (cycles) begin
            @(posedge clk);
            if (data_out_valid) saw_event = 1'b1;
        end
        check(!saw_event, msg);
    endtask

    initial begin : run_tests
        logic [OUTPUT_BUS_WIDTH-1:0] event_data;

        passed = 0;
        failed = 0;
        reset_dut();
        load_vectors();

        $display("\n========================================================");
        $display("MARKET PARSER TESTS");
        $display("========================================================");

        send_packet_from_mem(ADD_ORDER_PACKET_BYTES, add_order_packet_mem);
        wait_for_event(event_data);
        check(event_data == expected_event_mem[0], "add order event matches generated vector");
        check(event_data[7:0]     == EVENT_ADD, "add order classified");
        check(event_data[15:8]    == "A", "ITCH message type A preserved");
        check(event_data[31:16]   == 16'h1234, "stock locate decoded");
        check(event_data[47:32]   == 16'h5678, "tracking number decoded");
        check(event_data[95:48]   == 48'h0102_0304_0506, "timestamp decoded");
        check(event_data[159:96]  == 64'h1111_2222_3333_4444, "order ref decoded");
        check(event_data[191:160] == 32'd100, "shares decoded");
        check(event_data[223:192] == 32'd1234500, "price decoded");
        check(event_data[231:224] == "B", "side decoded");

        send_packet_from_mem(GAP_SYSTEM_PACKET_BYTES, gap_system_packet_mem);
        wait_for_event(event_data, 3);
        check(event_data == expected_event_mem[1], "gap system event matches generated vector");
        check(event_data[7:0] == EVENT_SYSTEM, "system event classified");
        check((event_data[239:232] & FLAG_GAP) != 8'h00, "gap flag set on skipped sequence");
        check(gap_error, "sticky gap error output set");
        check(data_out_valid == 1'b0, "output handshake completed after backpressure");

        send_zero_length_message_packet(64'd4);
        repeat (10) @(posedge clk);
        check(malformed_error, "zero-length message sets malformed error");

        fork
            send_packet_from_mem(MIXED_PACKET_BYTES, mixed_packet_mem);
            begin
                for (int i = 2; i < EXPECTED_EVENTS; i++) begin
                    wait_for_event(event_data);
                    check(event_data == expected_event_mem[i],
                          $sformatf("mixed event %0d matches generated vector", i - 2));
                end
            end
        join
        check(expected_event_mem[2][7:0] == EVENT_ADD, "MPID add order event generated");
        check(expected_event_mem[3][7:0] == EVENT_EXECUTE, "execute event generated");
        check(expected_event_mem[4][7:0] == EVENT_EXECUTE, "execute-with-price event generated");
        check(expected_event_mem[5][7:0] == EVENT_CANCEL, "cancel event generated");
        check(expected_event_mem[6][7:0] == EVENT_DELETE, "delete event generated");
        check(expected_event_mem[7][7:0] == EVENT_REPLACE, "replace event generated");
        check(expected_event_mem[8][7:0] == EVENT_TRADE, "trade event generated");
        check(expected_event_mem[9][7:0] == EVENT_UNKNOWN, "unknown event generated");
        check((expected_event_mem[9][239:232] & FLAG_UNKNOWN) != 8'h00, "unknown event vector has unknown flag");
        check(unknown_msg_type, "sticky unknown message output set");

        send_packet_from_mem(TRUNCATED_PACKET_BYTES, truncated_packet_mem);
        repeat (10) @(posedge clk);
        check(malformed_error, "truncated message keeps malformed error set");

        send_packet_from_mem(HEARTBEAT_PACKET_BYTES, heartbeat_packet_mem);
        check_no_event(10, "heartbeat emits no event");
        check(expected_sequence == 64'd14, "heartbeat preserves next expected sequence");

        send_packet_from_mem(END_SESSION_PACKET_BYTES, end_session_packet_mem);
        check_no_event(10, "end-of-session emits no event");

        check(packet_count == 32'd7, "packet counter");
        check(message_count == 32'd10, "message counter");
        check(event_count == 32'd10, "event counter");
        check(error_count == 32'd4, "gap, zero-length, unknown, truncated error counter");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_tb failed");
    end

endmodule
`default_nettype wire
