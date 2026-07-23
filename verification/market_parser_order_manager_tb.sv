`timescale 1ns / 100ps
`default_nettype none

module market_parser_order_manager_tb;
    localparam realtime CLK_PERIOD = 2.500ns;
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    logic clk = 1'b0;
    logic rst;
    logic trading_enabled;
    logic cancel_all;
    logic intent_valid;
    logic intent_ready;
    logic [15:0] intent_stock_locate;
    logic intent_side;
    logic [31:0] intent_price;
    logic [31:0] intent_quantity;
    logic [47:0] intent_timestamp;
    logic order_cmd_valid;
    logic order_cmd_ready;
    logic order_cmd_cancel;
    logic [63:0] order_cmd_id;
    logic [15:0] order_cmd_stock_locate;
    logic order_cmd_side;
    logic [31:0] order_cmd_price;
    logic [31:0] order_cmd_quantity;
    logic [47:0] order_cmd_timestamp;
    logic exchange_event_valid;
    logic [1:0] exchange_event_type;
    logic [63:0] exchange_event_order_id;
    logic [31:0] exchange_event_price;
    logic [31:0] exchange_event_quantity;
    logic fill_valid;
    logic [15:0] fill_stock_locate;
    logic fill_side;
    logic [31:0] fill_price;
    logic [31:0] fill_quantity;
    logic [1:0] working_order_mask;
    logic [1:0] live_order_mask;
    logic [63:0] leaves_quantity_by_symbol;
    logic [15:0] outstanding_order_count;
    logic [31:0] accepted_intent_count;
    logic [31:0] busy_intent_count;
    logic [31:0] untracked_intent_count;
    logic [31:0] new_command_count;
    logic [31:0] acknowledged_order_count;
    logic [31:0] rejected_order_count;
    logic [31:0] cancel_command_count;
    logic [31:0] cancel_ack_count;
    logic [31:0] fill_event_count;
    logic [31:0] canceled_before_send_count;
    logic [31:0] protocol_error_count;
    int failed;

    always #HALF_CLK_PERIOD clk <= ~clk;

    market_parser_order_manager #(
        .NUM_SYMBOLS(2),
        .SYMBOL_LOCATES({16'h2222, 16'h1111})
    ) dut (
        .clk(clk),
        .rst(rst),
        .trading_enabled(trading_enabled),
        .cancel_all(cancel_all),
        .intent_valid(intent_valid),
        .intent_ready(intent_ready),
        .intent_stock_locate(intent_stock_locate),
        .intent_side(intent_side),
        .intent_price(intent_price),
        .intent_quantity(intent_quantity),
        .intent_timestamp(intent_timestamp),
        .order_cmd_valid(order_cmd_valid),
        .order_cmd_ready(order_cmd_ready),
        .order_cmd_cancel(order_cmd_cancel),
        .order_cmd_id(order_cmd_id),
        .order_cmd_stock_locate(order_cmd_stock_locate),
        .order_cmd_side(order_cmd_side),
        .order_cmd_price(order_cmd_price),
        .order_cmd_quantity(order_cmd_quantity),
        .order_cmd_timestamp(order_cmd_timestamp),
        .exchange_event_valid(exchange_event_valid),
        .exchange_event_ready(),
        .exchange_event_type(exchange_event_type),
        .exchange_event_order_id(exchange_event_order_id),
        .exchange_event_price(exchange_event_price),
        .exchange_event_quantity(exchange_event_quantity),
        .fill_valid(fill_valid),
        .fill_stock_locate(fill_stock_locate),
        .fill_side(fill_side),
        .fill_price(fill_price),
        .fill_quantity(fill_quantity),
        .working_order_mask(working_order_mask),
        .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(leaves_quantity_by_symbol),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(accepted_intent_count),
        .busy_intent_count(busy_intent_count),
        .untracked_intent_count(untracked_intent_count),
        .new_command_count(new_command_count),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(rejected_order_count),
        .cancel_command_count(cancel_command_count),
        .cancel_ack_count(cancel_ack_count),
        .fill_event_count(fill_event_count),
        .canceled_before_send_count(canceled_before_send_count),
        .protocol_error_count(protocol_error_count)
    );

    task automatic check(input bit condition, input string message);
        if (condition) begin
            $display("PASS: %s", message);
        end else begin
            $display("FAIL: %s", message);
            failed++;
        end
    endtask

    task automatic send_intent(
        input logic [15:0] locate,
        input logic side,
        input logic [31:0] price,
        input logic [31:0] quantity,
        input logic [47:0] timestamp
    );
        @(negedge clk);
        intent_valid        = 1'b1;
        intent_stock_locate = locate;
        intent_side         = side;
        intent_price        = price;
        intent_quantity     = quantity;
        intent_timestamp    = timestamp;
        while (!intent_ready) begin
            @(negedge clk);
        end
        @(negedge clk);
        intent_valid = 1'b0;
    endtask

    task automatic accept_command(
        input logic expected_cancel,
        output logic [63:0] accepted_id
    );
        while (!order_cmd_valid) begin
            @(negedge clk);
        end
        accepted_id = order_cmd_id;
        check(order_cmd_cancel == expected_cancel,
              expected_cancel ? "cancel command type" : "new command type");
        order_cmd_ready = 1'b1;
        @(negedge clk);
        order_cmd_ready = 1'b0;
    endtask

    task automatic send_event(
        input logic [1:0] event_type,
        input logic [63:0] order_id,
        input logic [31:0] price,
        input logic [31:0] quantity
    );
        @(negedge clk);
        exchange_event_valid    = 1'b1;
        exchange_event_type     = event_type;
        exchange_event_order_id = order_id;
        exchange_event_price    = price;
        exchange_event_quantity = quantity;
        @(negedge clk);
        exchange_event_valid = 1'b0;
        @(negedge clk);
    endtask

    initial begin
        logic [63:0] id_1;
        logic [63:0] id_2;
        logic [63:0] id_4;
        logic [127:0] stalled_payload;

        failed = 0;
        rst = 1'b1;
        trading_enabled = 1'b1;
        cancel_all = 1'b0;
        intent_valid = 1'b0;
        intent_stock_locate = '0;
        intent_side = 1'b0;
        intent_price = '0;
        intent_quantity = '0;
        intent_timestamp = '0;
        order_cmd_ready = 1'b0;
        exchange_event_valid = 1'b0;
        exchange_event_type = '0;
        exchange_event_order_id = '0;
        exchange_event_price = '0;
        exchange_event_quantity = '0;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        send_intent(16'h1111, 1'b0, 32'd101, 32'd10, 48'd1000);
        while (!order_cmd_valid) @(negedge clk);
        id_1 = order_cmd_id;
        stalled_payload = {order_cmd_id, order_cmd_stock_locate,
                           order_cmd_side, order_cmd_price[14:0],
                           order_cmd_quantity};
        repeat (3) begin
            @(negedge clk);
            check(order_cmd_valid &&
                  {order_cmd_id, order_cmd_stock_locate,
                   order_cmd_side, order_cmd_price[14:0],
                   order_cmd_quantity} == stalled_payload,
                  "new command remains stable under backpressure");
        end
        check(id_1 == 64'd1 && order_cmd_stock_locate == 16'h1111 &&
              !order_cmd_side && order_cmd_price == 32'd101 &&
              order_cmd_quantity == 32'd10,
              "first intent receives the expected client order ID and payload");

        send_intent(16'h1111, 1'b0, 32'd102, 32'd10, 48'd1001);
        check(busy_intent_count == 32'd1 && order_cmd_id == id_1,
              "duplicate intent is classified without disturbing the command");
        accept_command(1'b0, id_1);
        send_event(2'd0, id_1, 32'd0, 32'd0);
        check(live_order_mask[0] && acknowledged_order_count == 32'd1,
              "exchange acknowledgment makes the first order live");

        send_event(2'd2, id_1, 32'd101, 32'd4);
        check(fill_valid && fill_stock_locate == 16'h1111 && !fill_side &&
              fill_price == 32'd101 && fill_quantity == 32'd4,
              "partial fill is reconciled and emitted downstream");
        check(leaves_quantity_by_symbol[31:0] == 32'd6,
              "partial fill decrements leaves quantity");

        @(negedge clk);
        cancel_all = 1'b1;
        accept_command(1'b1, id_1);
        check(order_cmd_quantity == 32'd6,
              "cancel command carries remaining quantity");
        send_event(2'd3, id_1, 32'd0, 32'd0);
        check(outstanding_order_count == 16'd0 && cancel_ack_count == 32'd1,
              "cancel acknowledgment retires the live order");
        @(negedge clk);
        cancel_all = 1'b0;

        order_cmd_ready = 1'b0;
        send_intent(16'h2222, 1'b1, 32'd200, 32'd7, 48'd2000);
        accept_command(1'b0, id_2);
        check(id_2 == 64'd2, "client order IDs increase monotonically");
        send_event(2'd1, id_2, 32'd0, 32'd0);
        check(rejected_order_count == 32'd1 &&
              outstanding_order_count == 16'd0,
              "venue reject retires a pending new order");

        send_intent(16'h9999, 1'b0, 32'd300, 32'd1, 48'd3000);
        check(untracked_intent_count == 32'd1,
              "untracked intent is consumed and counted fail closed");
        send_event(2'd0, 64'hdead_beef, 32'd0, 32'd0);
        check(protocol_error_count == 32'd1,
              "unmatched exchange event increments protocol errors");

        order_cmd_ready = 1'b0;
        send_intent(16'h1111, 1'b0, 32'd103, 32'd3, 48'd4000);
        check(order_cmd_valid && order_cmd_id == 64'd3,
              "third tracked intent is queued for transmission");
        @(negedge clk);
        cancel_all = 1'b1;
        @(negedge clk);
        check(!order_cmd_valid && outstanding_order_count == 16'd0 &&
              canceled_before_send_count == 32'd1,
              "cancel-all withdraws an unsent new command");
        cancel_all = 1'b0;

        send_intent(16'h1111, 1'b0, 32'd104, 32'd5, 48'd5000);
        accept_command(1'b0, id_4);
        check(id_4 == 64'd4, "aborted transmission does not reuse an order ID");
        send_event(2'd0, id_4, 32'd0, 32'd0);
        send_event(2'd2, id_4, 32'd104, 32'd6);
        check(fill_valid && fill_quantity == 32'd5 &&
              outstanding_order_count == 16'd0,
              "overfill is clamped to leaves and retires the order");
        check(protocol_error_count == 32'd2,
              "overfill is retained as a protocol error");

        check(accepted_intent_count == 32'd4 &&
              busy_intent_count == 32'd1 &&
              untracked_intent_count == 32'd1,
              "intent accounting separates accepted, busy, and untracked work");
        check(new_command_count == 32'd3 &&
              acknowledged_order_count == 32'd2 &&
              rejected_order_count == 32'd1,
              "new-order lifecycle counters are exact");
        check(cancel_command_count == 32'd1 &&
              cancel_ack_count == 32'd1 && fill_event_count == 32'd2,
              "cancel and fill lifecycle counters are exact");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
