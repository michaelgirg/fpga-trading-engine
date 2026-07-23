`timescale 1ns/1ps
`default_nettype none
module market_parser_order_risk_guard_tb;
    localparam time HALF = 1ns;
    logic clk = 1'b0;
    logic rst;
    logic risk_enable;
    logic session_active;
    logic kill_switch;
    logic [31:0] max_order_quantity;
    logic [31:0] min_order_price;
    logic [31:0] max_order_price;
    logic [15:0] max_outstanding_orders;
    logic [15:0] max_new_orders_per_window;
    logic [15:0] outstanding_order_count;
    logic command_valid;
    logic command_ready;
    logic command_cancel;
    logic [63:0] command_id;
    logic [15:0] command_stock_locate;
    logic command_side;
    logic [31:0] command_price;
    logic [31:0] command_quantity;
    logic [47:0] command_timestamp;
    logic guarded_command_valid;
    logic guarded_command_ready;
    logic guarded_command_cancel;
    logic [63:0] guarded_command_id;
    logic [15:0] guarded_command_stock_locate;
    logic guarded_command_side;
    logic [31:0] guarded_command_price;
    logic [31:0] guarded_command_quantity;
    logic [47:0] guarded_command_timestamp;
    logic local_reject_valid;
    logic local_reject_ready;
    logic [63:0] local_reject_order_id;
    logic [2:0] local_reject_reason;
    logic [31:0] passed_new_count;
    logic [31:0] passed_cancel_count;
    logic [31:0] control_reject_count;
    logic [31:0] quantity_reject_count;
    logic [31:0] price_reject_count;
    logic [31:0] outstanding_reject_count;
    logic [31:0] rate_reject_count;
    int failed;

    always #HALF clk = ~clk;

    market_parser_order_risk_guard #(.RATE_WINDOW_CYCLES(256)) dut (.*);

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    task automatic send_command(
        input logic cancel,
        input logic [63:0] id,
        input logic [31:0] price,
        input logic [31:0] quantity
    );
        @(negedge clk);
        command_valid = 1'b1;
        command_cancel = cancel;
        command_id = id;
        command_price = price;
        command_quantity = quantity;
        while (!command_ready) @(negedge clk);
        @(negedge clk);
        command_valid = 1'b0;
    endtask

    task automatic consume_guarded(input logic cancel, input logic [63:0] id);
        while (!guarded_command_valid) @(negedge clk);
        check(guarded_command_cancel == cancel && guarded_command_id == id,
              "guarded command payload");
        guarded_command_ready = 1'b1;
        @(negedge clk);
        guarded_command_ready = 1'b0;
    endtask

    task automatic consume_reject(input logic [63:0] id, input logic [2:0] reason);
        while (!local_reject_valid) @(negedge clk);
        check(local_reject_order_id == id && local_reject_reason == reason,
              "local reject payload and reason");
        local_reject_ready = 1'b1;
        @(negedge clk);
        local_reject_ready = 1'b0;
    endtask

    initial begin
        logic [201:0] held_payload;
        failed = 0;
        rst = 1'b1;
        risk_enable = 1'b1;
        session_active = 1'b1;
        kill_switch = 1'b0;
        max_order_quantity = 32'd10;
        min_order_price = 32'd90;
        max_order_price = 32'd110;
        max_outstanding_orders = 16'd4;
        max_new_orders_per_window = 16'd2;
        outstanding_order_count = 16'd1;
        command_valid = 1'b0;
        command_cancel = 1'b0;
        command_id = '0;
        command_stock_locate = 16'h1111;
        command_side = 1'b0;
        command_price = 32'd100;
        command_quantity = 32'd2;
        command_timestamp = 48'd1234;
        guarded_command_ready = 1'b0;
        local_reject_ready = 1'b0;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        send_command(1'b0, 64'd1, 32'd100, 32'd2);
        while (!guarded_command_valid) @(negedge clk);
        held_payload = {guarded_command_id, guarded_command_stock_locate,
                        guarded_command_side, guarded_command_price,
                        guarded_command_quantity, guarded_command_timestamp,
                        guarded_command_cancel, 8'd0};
        repeat (3) begin
            @(negedge clk);
            check(guarded_command_valid &&
                  {guarded_command_id, guarded_command_stock_locate,
                   guarded_command_side, guarded_command_price,
                   guarded_command_quantity, guarded_command_timestamp,
                   guarded_command_cancel, 8'd0} == held_payload,
                  "allowed command remains stable under backpressure");
        end
        consume_guarded(1'b0, 64'd1);

        session_active = 1'b0;
        send_command(1'b0, 64'd2, 32'd100, 32'd2);
        consume_reject(64'd2, 3'd1);
        send_command(1'b1, 64'd1, 32'd100, 32'd2);
        consume_guarded(1'b1, 64'd1);
        check(passed_cancel_count == 32'd1,
              "cancel bypasses inactive-session controls");
        session_active = 1'b1;

        send_command(1'b0, 64'd3, 32'd100, 32'd11);
        consume_reject(64'd3, 3'd2);
        send_command(1'b0, 64'd4, 32'd120, 32'd2);
        consume_reject(64'd4, 3'd3);
        outstanding_order_count = 16'd5;
        send_command(1'b0, 64'd5, 32'd100, 32'd2);
        consume_reject(64'd5, 3'd4);
        outstanding_order_count = 16'd1;

        send_command(1'b0, 64'd6, 32'd100, 32'd2);
        consume_guarded(1'b0, 64'd6);
        send_command(1'b0, 64'd7, 32'd100, 32'd2);
        consume_reject(64'd7, 3'd5);

        kill_switch = 1'b1;
        send_command(1'b0, 64'd8, 32'd100, 32'd2);
        consume_reject(64'd8, 3'd1);
        kill_switch = 1'b0;

        check(passed_new_count == 32'd2 && passed_cancel_count == 32'd1,
              "passed command counters are exact");
        check(control_reject_count == 32'd2 &&
              quantity_reject_count == 32'd1 &&
              price_reject_count == 32'd1 &&
              outstanding_reject_count == 32'd1 &&
              rate_reject_count == 32'd1,
              "risk rejection counters are exact by cause");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
