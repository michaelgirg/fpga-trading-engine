`timescale 1ns / 100ps
`default_nettype none

module market_parser_order_latency_monitor_tb;
    logic clk = 1'b0;
    logic rst;
    logic clear;
    logic command_valid;
    logic command_ready;
    logic command_cancel;
    logic [63:0] command_id;
    logic [31:0] command_quantity;
    logic tx_valid;
    logic tx_ready;
    logic tx_is_new;
    logic [63:0] tx_order_id;
    logic response_valid;
    logic response_ready;
    logic [1:0] response_type;
    logic [63:0] response_order_id;
    logic [31:0] response_quantity;
    logic [15:0] tracked_order_count;
    logic [31:0] activity_hash;
    logic [31:0] new_to_tx_last_cycles;
    logic [31:0] new_to_tx_min_cycles;
    logic [31:0] new_to_tx_max_cycles;
    logic [31:0] new_to_tx_sample_count;
    logic [31:0] new_to_ack_last_cycles;
    logic [31:0] new_to_ack_min_cycles;
    logic [31:0] new_to_ack_max_cycles;
    logic [31:0] new_to_ack_sample_count;
    logic [31:0] new_to_fill_last_cycles;
    logic [31:0] new_to_fill_min_cycles;
    logic [31:0] new_to_fill_max_cycles;
    logic [31:0] new_to_fill_sample_count;
    logic [31:0] duplicate_order_count;
    logic [31:0] duplicate_tx_count;
    logic [31:0] duplicate_response_count;
    logic [31:0] unmatched_tx_count;
    logic [31:0] unmatched_response_count;
    logic [31:0] table_full_count;
    logic [31:0] anomaly_count;
    int failed;

    always #1.551ns clk = ~clk;

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    task automatic send_new(input logic [63:0] id, input logic [31:0] quantity);
        @(negedge clk);
        command_valid = 1'b1;
        command_cancel = 1'b0;
        command_id = id;
        command_quantity = quantity;
        @(negedge clk);
        command_valid = 1'b0;
    endtask

    task automatic send_tx(input logic [63:0] id, input int stall_cycles);
        @(negedge clk);
        tx_valid = 1'b1;
        tx_is_new = 1'b1;
        tx_order_id = id;
        repeat (stall_cycles) @(negedge clk);
        tx_ready = 1'b1;
        @(negedge clk);
        tx_valid = 1'b0;
        tx_ready = 1'b0;
    endtask

    task automatic send_response(
        input logic [1:0] event_type,
        input logic [63:0] id,
        input logic [31:0] quantity
    );
        @(negedge clk);
        response_valid = 1'b1;
        response_type = event_type;
        response_order_id = id;
        response_quantity = quantity;
        @(negedge clk);
        response_valid = 1'b0;
    endtask

    market_parser_order_latency_monitor #(.TABLE_DEPTH(2)) dut (
        .clk(clk), .rst(rst), .clear(clear),
        .command_valid(command_valid), .command_ready(command_ready),
        .command_cancel(command_cancel), .command_id(command_id),
        .command_quantity(command_quantity), .tx_valid(tx_valid),
        .tx_ready(tx_ready), .tx_is_new(tx_is_new),
        .tx_order_id(tx_order_id), .response_valid(response_valid),
        .response_ready(response_ready), .response_type(response_type),
        .response_order_id(response_order_id),
        .response_quantity(response_quantity), .cycle_count(),
        .tracked_order_count(tracked_order_count),
        .activity_hash(activity_hash),
        .new_to_tx_last_cycles(new_to_tx_last_cycles),
        .new_to_tx_min_cycles(new_to_tx_min_cycles),
        .new_to_tx_max_cycles(new_to_tx_max_cycles),
        .new_to_tx_sample_count(new_to_tx_sample_count),
        .new_to_ack_last_cycles(new_to_ack_last_cycles),
        .new_to_ack_min_cycles(new_to_ack_min_cycles),
        .new_to_ack_max_cycles(new_to_ack_max_cycles),
        .new_to_ack_sample_count(new_to_ack_sample_count),
        .new_to_fill_last_cycles(new_to_fill_last_cycles),
        .new_to_fill_min_cycles(new_to_fill_min_cycles),
        .new_to_fill_max_cycles(new_to_fill_max_cycles),
        .new_to_fill_sample_count(new_to_fill_sample_count),
        .duplicate_order_count(duplicate_order_count),
        .duplicate_tx_count(duplicate_tx_count),
        .duplicate_response_count(duplicate_response_count),
        .unmatched_tx_count(unmatched_tx_count),
        .unmatched_response_count(unmatched_response_count),
        .table_full_count(table_full_count), .anomaly_count(anomaly_count)
    );

    initial begin
        failed = 0;
        rst = 1'b1;
        clear = 1'b0;
        command_valid = 1'b0;
        command_ready = 1'b1;
        command_cancel = 1'b0;
        command_id = '0;
        command_quantity = '0;
        tx_valid = 1'b0;
        tx_ready = 1'b0;
        tx_is_new = 1'b0;
        tx_order_id = '0;
        response_valid = 1'b0;
        response_ready = 1'b1;
        response_type = '0;
        response_order_id = '0;
        response_quantity = '0;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        send_new(64'd1, 32'd1);
        send_new(64'd3, 32'd1);
        repeat (3) @(negedge clk);
        check(table_full_count == 1 && tracked_order_count == 1 &&
              anomaly_count == 1,
              "direct-index collision is observable while another slot is free");
        @(negedge clk);
        clear = 1'b1;
        @(negedge clk);
        clear = 1'b0;

        send_new(64'd11, 32'd10);
        repeat (2) @(negedge clk);
        send_tx(64'd11, 3);
        repeat (4) @(negedge clk);
        check(new_to_tx_sample_count == 1 && new_to_tx_last_cycles >= 5,
              "wire latency includes Soup output backpressure");
        send_response(2'd0, 64'd11, 32'd0);
        send_response(2'd2, 64'd11, 32'd4);
        repeat (4) @(negedge clk);
        check(new_to_ack_sample_count == 1 && new_to_fill_sample_count == 1 &&
              tracked_order_count == 1,
              "ACK and first partial fill are correlated without retiring order");
        send_response(2'd2, 64'd11, 32'd6);
        repeat (4) @(negedge clk);
        check(new_to_fill_sample_count == 1 && tracked_order_count == 0,
              "final fill retires telemetry slot without double-counting latency");

        send_new(64'd21, 32'd1);
        send_new(64'd22, 32'd1);
        send_new(64'd23, 32'd1);
        repeat (3) @(negedge clk);
        check(table_full_count == 1 && tracked_order_count == 2,
              "bounded table fails observably when full");
        send_new(64'd21, 32'd1);
        repeat (3) @(negedge clk);
        check(duplicate_order_count == 1,
              "duplicate client order ID is counted");
        send_tx(64'd99, 0);
        send_response(2'd0, 64'd99, 32'd0);
        repeat (3) @(negedge clk);
        check(unmatched_tx_count == 1 && unmatched_response_count == 1,
              "unmatched wire and response events are counted");

        send_tx(64'd21, 0);
        send_tx(64'd21, 0);
        send_response(2'd0, 64'd21, 32'd0);
        send_response(2'd0, 64'd21, 32'd0);
        repeat (4) @(negedge clk);
        check(duplicate_tx_count == 1 && duplicate_response_count == 1,
              "duplicate wire and ACK events are counted");
        check(anomaly_count == 6,
              "aggregate anomaly count covers every injected monitor fault");
        check(new_to_tx_min_cycles <= new_to_tx_last_cycles &&
              new_to_tx_last_cycles <= new_to_tx_max_cycles &&
              new_to_ack_min_cycles <= new_to_ack_last_cycles &&
              new_to_ack_last_cycles <= new_to_ack_max_cycles,
              "latency extrema bracket the latest samples");

        @(negedge clk);
        clear = 1'b1;
        @(negedge clk);
        clear = 1'b0;
        check(tracked_order_count == 0 && new_to_tx_sample_count == 0 &&
              new_to_tx_min_cycles == 32'hffff_ffff && table_full_count == 0 &&
              anomaly_count == 0 && activity_hash == 0,
              "clear resets samples, anomaly counters, and tracked slots");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
