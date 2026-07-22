`timescale 1ns/1ps
`default_nettype none

module market_parser_signal_engine_tb;
    localparam int NUM_SYMBOLS = 2;
    localparam logic [31:0] SYMBOL_LOCATES = {16'h2222, 16'h1111};

    logic clk = 1'b0;
    logic rst;
    logic quote_valid;
    logic quote_ready;
    logic [15:0] quote_stock_locate;
    logic [31:0] quote_bid_price;
    logic [31:0] quote_bid_shares;
    logic [31:0] quote_ask_price;
    logic [31:0] quote_ask_shares;
    logic [47:0] quote_timestamp;
    logic feed_healthy;
    logic strategy_enable;
    logic kill_switch;
    logic position_clear;
    logic [31:0] max_spread_ticks;
    logic [31:0] min_top_shares;
    logic [2:0] imbalance_shift;
    logic [31:0] order_quantity;
    logic [31:0] max_abs_position;
    logic fill_valid;
    logic [15:0] fill_stock_locate;
    logic fill_side;
    logic [31:0] fill_quantity;
    logic intent_valid;
    logic intent_ready;
    logic [15:0] intent_stock_locate;
    logic intent_side;
    logic [31:0] intent_price;
    logic [31:0] intent_quantity;
    logic [47:0] intent_timestamp;
    logic [NUM_SYMBOLS*32-1:0] position_by_symbol;
    logic [31:0] evaluated_quote_count;
    logic [31:0] generated_intent_count;
    logic [31:0] control_suppressed_count;
    logic [31:0] market_suppressed_count;
    logic [31:0] risk_suppressed_count;
    logic [31:0] applied_fill_count;
    logic [31:0] untracked_fill_count;
    int failed;
    int base_evaluated;
    int base_market_suppressed;
    int wait_cycles;

    always #5 clk = ~clk;

    market_parser_signal_engine #(
        .NUM_SYMBOLS(NUM_SYMBOLS),
        .SYMBOL_LOCATES(SYMBOL_LOCATES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .quote_valid(quote_valid),
        .quote_ready(quote_ready),
        .quote_stock_locate(quote_stock_locate),
        .quote_bid_price(quote_bid_price),
        .quote_bid_shares(quote_bid_shares),
        .quote_ask_price(quote_ask_price),
        .quote_ask_shares(quote_ask_shares),
        .quote_timestamp(quote_timestamp),
        .feed_healthy(feed_healthy),
        .strategy_enable(strategy_enable),
        .kill_switch(kill_switch),
        .position_clear(position_clear),
        .max_spread_ticks(max_spread_ticks),
        .min_top_shares(min_top_shares),
        .imbalance_shift(imbalance_shift),
        .order_quantity(order_quantity),
        .max_abs_position(max_abs_position),
        .fill_valid(fill_valid),
        .fill_stock_locate(fill_stock_locate),
        .fill_side(fill_side),
        .fill_quantity(fill_quantity),
        .intent_valid(intent_valid),
        .intent_ready(intent_ready),
        .intent_stock_locate(intent_stock_locate),
        .intent_side(intent_side),
        .intent_price(intent_price),
        .intent_quantity(intent_quantity),
        .intent_timestamp(intent_timestamp),
        .position_by_symbol(position_by_symbol),
        .evaluated_quote_count(evaluated_quote_count),
        .generated_intent_count(generated_intent_count),
        .control_suppressed_count(control_suppressed_count),
        .market_suppressed_count(market_suppressed_count),
        .risk_suppressed_count(risk_suppressed_count),
        .applied_fill_count(applied_fill_count),
        .untracked_fill_count(untracked_fill_count)
    );

    task automatic check(input bit condition, input string message);
        if (condition) begin
            $display("PASS: %s", message);
        end else begin
            $display("FAIL: %s", message);
            failed++;
        end
    endtask

    task automatic send_quote(
        input logic [15:0] locate,
        input logic [31:0] bid_price,
        input logic [31:0] bid_shares,
        input logic [31:0] ask_price,
        input logic [31:0] ask_shares,
        input logic [47:0] timestamp
    );
        while (!quote_ready) @(posedge clk);
        quote_stock_locate = locate;
        quote_bid_price = bid_price;
        quote_bid_shares = bid_shares;
        quote_ask_price = ask_price;
        quote_ask_shares = ask_shares;
        quote_timestamp = timestamp;
        quote_valid = 1'b1;
        @(posedge clk);
        #1 quote_valid = 1'b0;
        repeat (3) @(posedge clk);
        #1;
    endtask

    task automatic send_fill(
        input logic [15:0] locate,
        input logic side,
        input logic [31:0] quantity
    );
        fill_stock_locate = locate;
        fill_side = side;
        fill_quantity = quantity;
        fill_valid = 1'b1;
        @(posedge clk);
        #1 fill_valid = 1'b0;
    endtask

    task automatic accept_intent(
        input logic [15:0] locate,
        input logic side,
        input logic [31:0] price,
        input logic [31:0] quantity,
        input logic [47:0] timestamp,
        input string message
    );
        #1;
        check(intent_valid, {message, " valid"});
        check(intent_stock_locate == locate && intent_side == side &&
              intent_price == price && intent_quantity == quantity &&
              intent_timestamp == timestamp, {message, " payload"});
        intent_ready = 1'b1;
        @(posedge clk);
        #1 intent_ready = 1'b0;
    endtask

    initial begin
        failed = 0;
        rst = 1'b1;
        quote_valid = 1'b0;
        quote_stock_locate = '0;
        quote_bid_price = '0;
        quote_bid_shares = '0;
        quote_ask_price = '0;
        quote_ask_shares = '0;
        quote_timestamp = '0;
        feed_healthy = 1'b1;
        strategy_enable = 1'b0;
        kill_switch = 1'b0;
        position_clear = 1'b0;
        max_spread_ticks = 32'd5;
        min_top_shares = 32'd50;
        imbalance_shift = 3'd1;
        order_quantity = 32'd10;
        max_abs_position = 32'd100;
        fill_valid = 1'b0;
        fill_stock_locate = '0;
        fill_side = 1'b0;
        fill_quantity = '0;
        intent_ready = 1'b0;

        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        send_quote(16'h1111, 32'd100, 32'd400, 32'd102, 32'd100, 48'd1);
        check(!intent_valid && control_suppressed_count == 32'd1,
              "disabled strategy suppresses quote");

        strategy_enable = 1'b1;
        send_quote(16'h1111, 32'd100, 32'd400, 32'd102, 32'd100, 48'd2);
        check(intent_valid, "buy intent remains pending under backpressure");
        check(intent_stock_locate == 16'h1111 && !intent_side &&
              intent_price == 32'd102 && intent_quantity == 32'd10,
              "buy intent crosses at current ask");
        repeat (3) begin
            @(posedge clk);
            #1 check(intent_valid && intent_price == 32'd102 &&
                     intent_timestamp == 48'd2,
                     "pending intent payload is stable");
        end
        intent_ready = 1'b1;
        @(posedge clk);
        #1 intent_ready = 1'b0;

        send_fill(16'h1111, 1'b0, 32'd95);
        check($signed(position_by_symbol[31:0]) == 32'sd95,
              "buy fill increases signed position");
        send_quote(16'h1111, 32'd100, 32'd400, 32'd102, 32'd100, 48'd3);
        check(!intent_valid && risk_suppressed_count == 32'd1,
              "buy intent cannot exceed long exposure limit");

        send_quote(16'h1111, 32'd100, 32'd100, 32'd102, 32'd400, 48'd4);
        accept_intent(16'h1111, 1'b1, 32'd100, 32'd10, 48'd4,
                      "sell imbalance intent");

        send_fill(16'h1111, 1'b1, 32'd200);
        check($signed(position_by_symbol[31:0]) == -32'sd105,
              "sell fill decreases signed position");
        send_quote(16'h1111, 32'd100, 32'd100, 32'd102, 32'd400, 48'd5);
        check(!intent_valid && risk_suppressed_count == 32'd2,
              "sell intent cannot exceed short exposure limit");

        position_clear = 1'b1;
        @(posedge clk);
        #1 position_clear = 1'b0;
        check(position_by_symbol == '0, "position clear resets every symbol");

        send_quote(16'h1111, 32'd100, 32'd400, 32'd102, 32'd100, 48'd6);
        check(intent_valid, "intent is present before kill switch");
        kill_switch = 1'b1;
        #1 check(!intent_valid, "kill switch immediately withdraws pending intent");
        @(posedge clk);
        #1 kill_switch = 1'b0;
        check(!intent_valid, "kill switch flushes pending intent state");

        send_quote(16'h1111, 32'd100, 32'd400, 32'd110, 32'd100, 48'd7);
        send_quote(16'h1111, 32'd100, 32'd40, 32'd102, 32'd10, 48'd8);
        send_quote(16'h1111, 32'd100, 32'd100, 32'd102, 32'd100, 48'd9);
        send_quote(16'h9999, 32'd100, 32'd400, 32'd102, 32'd100, 48'd10);
        check(market_suppressed_count == 32'd4,
              "spread, liquidity, balance, and symbol filters are counted");

        feed_healthy = 1'b0;
        send_quote(16'h1111, 32'd100, 32'd400, 32'd102, 32'd100, 48'd11);
        feed_healthy = 1'b1;
        order_quantity = 32'd0;
        send_quote(16'h1111, 32'd100, 32'd400, 32'd102, 32'd100, 48'd12);
        order_quantity = 32'd10;
        check(control_suppressed_count == 32'd3,
              "feed and fail-closed configuration suppressions are counted");

        send_fill(16'h9999, 1'b0, 32'd1);
        check(applied_fill_count == 32'd2 && untracked_fill_count == 32'd1,
              "fill accounting separates tracked and untracked symbols");
        check(evaluated_quote_count == 32'd12 &&
              generated_intent_count == 32'd3,
              "quote and generated-intent counters are exact");

        position_clear = 1'b1;
        @(posedge clk);
        #1 position_clear = 1'b0;
        max_abs_position = 32'd100;
        quote_stock_locate = 16'h1111;
        quote_bid_price = 32'd100;
        quote_bid_shares = 32'd400;
        quote_ask_price = 32'd102;
        quote_ask_shares = 32'd100;
        quote_timestamp = 48'd13;
        quote_valid = 1'b1;
        @(posedge clk);
        #1 quote_valid = 1'b0;
        fill_stock_locate = 16'h1111;
        fill_side = 1'b0;
        fill_quantity = 32'd95;
        fill_valid = 1'b1;
        @(posedge clk);
        #1 fill_valid = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        check(!intent_valid && risk_suppressed_count == 32'd3,
              "in-flight quote risk-checks against same-window fill");
        check($signed(position_by_symbol[31:0]) == 32'sd95,
              "same-window fill updates tracked position");
        check(evaluated_quote_count == 32'd13,
              "held in-flight quote retires exactly once");

        base_evaluated = evaluated_quote_count;
        base_market_suppressed = market_suppressed_count;
        quote_bid_shares = 32'd100;
        quote_ask_shares = 32'd100;
        for (int i = 0; i < 4; i++) begin
            while (!quote_ready) @(posedge clk);
            quote_timestamp = 48'(20 + i);
            quote_valid = 1'b1;
            @(posedge clk);
            #1;
        end
        quote_valid = 1'b0;
        wait_cycles = 0;
        while (evaluated_quote_count < base_evaluated + 4 &&
               wait_cycles < 20) begin
            @(posedge clk);
            #1 wait_cycles++;
        end
        check(evaluated_quote_count == base_evaluated + 4 &&
              market_suppressed_count == base_market_suppressed + 4,
              "registered quote FIFO sustains one quote per cycle");
        check(!intent_valid, "balanced FIFO burst emits no intent");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
