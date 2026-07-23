`timescale 1ns / 100ps
`default_nettype none

module market_parser_order_risk_integration_tb;
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

    logic lifecycle_cmd_valid;
    logic lifecycle_cmd_ready;
    logic lifecycle_cmd_cancel;
    logic [63:0] lifecycle_cmd_id;
    logic [15:0] lifecycle_cmd_stock_locate;
    logic lifecycle_cmd_side;
    logic [31:0] lifecycle_cmd_price;
    logic [31:0] lifecycle_cmd_quantity;
    logic [47:0] lifecycle_cmd_timestamp;

    logic guarded_command_valid;
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
    logic external_event_valid;
    logic [1:0] external_event_type;
    logic [63:0] external_event_order_id;
    logic exchange_event_ready;

    logic [0:0] working_order_mask;
    logic [0:0] live_order_mask;
    logic [31:0] leaves_quantity_by_symbol;
    logic [15:0] outstanding_order_count;
    logic [31:0] accepted_intent_count;
    logic [31:0] new_command_count;
    logic [31:0] acknowledged_order_count;
    logic [31:0] rejected_order_count;
    logic [31:0] cancel_command_count;
    logic [31:0] cancel_ack_count;
    logic [31:0] protocol_error_count;

    logic risk_enable;
    logic session_active;
    logic kill_switch;
    logic [31:0] max_order_quantity;
    logic [31:0] min_order_price;
    logic [31:0] max_order_price;
    logic [15:0] max_outstanding_orders;
    logic [15:0] max_new_orders_per_window;
    logic [31:0] passed_new_count;
    logic [31:0] passed_cancel_count;
    logic [31:0] control_reject_count;
    logic [31:0] quantity_reject_count;
    logic [31:0] price_reject_count;
    logic [31:0] outstanding_reject_count;
    logic [31:0] rate_reject_count;

    int failed;
    int guarded_new_seen;
    int guarded_cancel_seen;
    int local_reject_seen;
    logic [63:0] last_guarded_order_id;
    logic [2:0] last_local_reject_reason;

    always #HALF_CLK_PERIOD clk <= ~clk;

    assign local_reject_ready = exchange_event_ready;

    market_parser_order_manager #(
        .NUM_SYMBOLS(1),
        .SYMBOL_LOCATES(16'h1111)
    ) manager_i (
        .clk(clk), .rst(rst), .trading_enabled(trading_enabled),
        .cancel_all(cancel_all), .intent_valid(intent_valid),
        .intent_ready(intent_ready),
        .intent_stock_locate(intent_stock_locate),
        .intent_side(intent_side), .intent_price(intent_price),
        .intent_quantity(intent_quantity),
        .intent_timestamp(intent_timestamp),
        .order_cmd_valid(lifecycle_cmd_valid),
        .order_cmd_ready(lifecycle_cmd_ready),
        .order_cmd_cancel(lifecycle_cmd_cancel),
        .order_cmd_id(lifecycle_cmd_id),
        .order_cmd_stock_locate(lifecycle_cmd_stock_locate),
        .order_cmd_side(lifecycle_cmd_side),
        .order_cmd_price(lifecycle_cmd_price),
        .order_cmd_quantity(lifecycle_cmd_quantity),
        .order_cmd_timestamp(lifecycle_cmd_timestamp),
        .exchange_event_valid(local_reject_valid || external_event_valid),
        .exchange_event_ready(exchange_event_ready),
        .exchange_event_type(local_reject_valid ? 2'd1 :
                                                external_event_type),
        .exchange_event_order_id(local_reject_valid ?
                                 local_reject_order_id :
                                 external_event_order_id),
        .exchange_event_price(32'd0),
        .exchange_event_quantity(32'd0),
        .fill_valid(), .fill_stock_locate(), .fill_side(),
        .fill_price(), .fill_quantity(),
        .working_order_mask(working_order_mask),
        .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(leaves_quantity_by_symbol),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(accepted_intent_count),
        .busy_intent_count(), .untracked_intent_count(),
        .new_command_count(new_command_count),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(rejected_order_count),
        .cancel_command_count(cancel_command_count),
        .cancel_ack_count(cancel_ack_count), .fill_event_count(),
        .canceled_before_send_count(),
        .protocol_error_count(protocol_error_count)
    );

    market_parser_order_risk_guard #(
        .RATE_WINDOW_CYCLES(256)
    ) guard_i (
        .clk(clk), .rst(rst), .risk_enable(risk_enable),
        .session_active(session_active), .kill_switch(kill_switch),
        .max_order_quantity(max_order_quantity),
        .min_order_price(min_order_price),
        .max_order_price(max_order_price),
        .max_outstanding_orders(max_outstanding_orders),
        .max_new_orders_per_window(max_new_orders_per_window),
        .outstanding_order_count(outstanding_order_count),
        .command_valid(lifecycle_cmd_valid),
        .command_ready(lifecycle_cmd_ready),
        .command_cancel(lifecycle_cmd_cancel),
        .command_id(lifecycle_cmd_id),
        .command_stock_locate(lifecycle_cmd_stock_locate),
        .command_side(lifecycle_cmd_side),
        .command_price(lifecycle_cmd_price),
        .command_quantity(lifecycle_cmd_quantity),
        .command_timestamp(lifecycle_cmd_timestamp),
        .guarded_command_valid(guarded_command_valid),
        .guarded_command_ready(1'b1),
        .guarded_command_cancel(guarded_command_cancel),
        .guarded_command_id(guarded_command_id),
        .guarded_command_stock_locate(guarded_command_stock_locate),
        .guarded_command_side(guarded_command_side),
        .guarded_command_price(guarded_command_price),
        .guarded_command_quantity(guarded_command_quantity),
        .guarded_command_timestamp(guarded_command_timestamp),
        .local_reject_valid(local_reject_valid),
        .local_reject_ready(local_reject_ready),
        .local_reject_order_id(local_reject_order_id),
        .local_reject_reason(local_reject_reason),
        .passed_new_count(passed_new_count),
        .passed_cancel_count(passed_cancel_count),
        .control_reject_count(control_reject_count),
        .quantity_reject_count(quantity_reject_count),
        .price_reject_count(price_reject_count),
        .outstanding_reject_count(outstanding_reject_count),
        .rate_reject_count(rate_reject_count)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            guarded_new_seen         <= 0;
            guarded_cancel_seen      <= 0;
            local_reject_seen        <= 0;
            last_guarded_order_id    <= '0;
            last_local_reject_reason <= '0;
        end else begin
            if (guarded_command_valid) begin
                last_guarded_order_id <= guarded_command_id;
                if (guarded_command_cancel) begin
                    guarded_cancel_seen <= guarded_cancel_seen + 1;
                end else begin
                    guarded_new_seen <= guarded_new_seen + 1;
                end
            end
            if (local_reject_valid && local_reject_ready) begin
                local_reject_seen        <= local_reject_seen + 1;
                last_local_reject_reason <= local_reject_reason;
            end
        end
    end

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    task automatic send_intent(input logic [31:0] quantity);
        @(negedge clk);
        intent_valid    = 1'b1;
        intent_quantity = quantity;
        while (!intent_ready) @(negedge clk);
        @(negedge clk);
        intent_valid = 1'b0;
    endtask

    task automatic send_external_event(
        input logic [1:0] event_type,
        input logic [63:0] order_id
    );
        while (local_reject_valid) @(negedge clk);
        @(negedge clk);
        external_event_valid    = 1'b1;
        external_event_type     = event_type;
        external_event_order_id = order_id;
        @(negedge clk);
        external_event_valid = 1'b0;
    endtask

    initial begin
        logic [63:0] live_order_id;

        failed = 0;
        rst = 1'b1;
        trading_enabled = 1'b1;
        cancel_all = 1'b0;
        intent_valid = 1'b0;
        intent_stock_locate = 16'h1111;
        intent_side = 1'b0;
        intent_price = 32'd100;
        intent_quantity = '0;
        intent_timestamp = 48'd1000;
        external_event_valid = 1'b0;
        external_event_type = '0;
        external_event_order_id = '0;
        risk_enable = 1'b1;
        session_active = 1'b1;
        kill_switch = 1'b0;
        max_order_quantity = 32'd4;
        min_order_price = 32'd90;
        max_order_price = 32'd110;
        max_outstanding_orders = 16'd1;
        max_new_orders_per_window = 16'd8;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        send_intent(32'd5);
        wait (rejected_order_count == 32'd1);
        @(negedge clk);
        check(local_reject_seen == 1 &&
              last_local_reject_reason == 3'd2,
              "quantity violation produces one classified local reject");
        check(guarded_new_seen == 0 && passed_new_count == 32'd0,
              "rejected new order never reaches the venue interface");
        check(outstanding_order_count == 16'd0 &&
              working_order_mask == '0 && protocol_error_count == 32'd0,
              "local reject retires lifecycle state without a protocol error");

        max_order_quantity = 32'd10;
        send_intent(32'd3);
        wait (guarded_new_seen == 1);
        live_order_id = last_guarded_order_id;
        check(live_order_id == 64'd2 && passed_new_count == 32'd1,
              "next valid order crosses with a monotonic client ID");
        send_external_event(2'd0, live_order_id);
        wait (acknowledged_order_count == 32'd1);
        @(negedge clk);
        check(live_order_mask == 1'b1 && outstanding_order_count == 16'd1,
              "venue acknowledgment makes the guarded order live");

        @(negedge clk);
        session_active = 1'b0;
        cancel_all = 1'b1;
        wait (guarded_cancel_seen == 1);
        check(passed_cancel_count == 32'd1,
              "cancel crosses even when the venue session is inactive");
        send_external_event(2'd3, live_order_id);
        wait (cancel_ack_count == 32'd1);
        @(negedge clk);
        check(outstanding_order_count == 16'd0 &&
              protocol_error_count == 32'd0,
              "cancel acknowledgment retires fail-closed exposure");

        check(accepted_intent_count == 32'd2 &&
              new_command_count == 32'd2 &&
              rejected_order_count == 32'd1 &&
              cancel_command_count == 32'd1,
              "lifecycle and guard accounting agree");
        check(quantity_reject_count == 32'd1 &&
              control_reject_count == 32'd0 &&
              price_reject_count == 32'd0 &&
              outstanding_reject_count == 32'd0 &&
              rate_reject_count == 32'd0,
              "only the intended risk rule fires");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
