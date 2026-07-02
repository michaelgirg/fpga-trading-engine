`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_top_of_book_tb
// =============================================================================
// Unit test for the single-symbol top-of-book engine.
module market_parser_top_of_book_tb #(
    parameter realtime CLK_PERIOD = 3.102ns
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [15:0] TARGET_STOCK_LOCATE = 16'h1234;

    logic clk = 1'b0;
    logic rst;

    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;
    logic [ 31:0] event_keep;
    logic         event_last;

    logic         quote_valid;
    logic         quote_ready;
    logic [15:0]  quote_stock_locate;
    logic [31:0]  quote_bid_price;
    logic [31:0]  quote_bid_shares;
    logic [31:0]  quote_ask_price;
    logic [31:0]  quote_ask_shares;
    logic [47:0]  quote_timestamp;

    logic [31:0] accepted_event_count;
    logic [31:0] applied_event_count;
    logic [31:0] ignored_event_count;
    logic [31:0] table_overflow_count;
    logic [31:0] quote_update_count;

    int passed;
    int failed;

    market_parser_top_of_book #(
        .ORDER_TABLE_DEPTH  (8),
        .TARGET_STOCK_LOCATE(TARGET_STOCK_LOCATE)
    ) DUT (
        .clk                 (clk),
        .rst                 (rst),
        .event_valid         (event_valid),
        .event_ready         (event_ready),
        .event_data          (event_data),
        .event_keep          (event_keep),
        .event_last          (event_last),
        .quote_valid         (quote_valid),
        .quote_ready         (quote_ready),
        .quote_stock_locate  (quote_stock_locate),
        .quote_bid_price     (quote_bid_price),
        .quote_bid_shares    (quote_bid_shares),
        .quote_ask_price     (quote_ask_price),
        .quote_ask_shares    (quote_ask_shares),
        .quote_timestamp     (quote_timestamp),
        .accepted_event_count(accepted_event_count),
        .applied_event_count (applied_event_count),
        .ignored_event_count (ignored_event_count),
        .table_overflow_count(table_overflow_count),
        .quote_update_count  (quote_update_count)
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic check(input bit condition, input string msg);
        if (condition) begin
            passed++;
            $display("PASS: %s", msg);
        end else begin
            failed++;
            $error("FAIL: %s", msg);
        end
    endtask

    task automatic reset_dut();
        rst         = 1'b1;
        event_valid = 1'b0;
        event_data  = '0;
        event_keep  = '0;
        event_last  = 1'b0;
        quote_ready = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    endtask

    function automatic logic [255:0] make_event(input logic [7:0]  kind,
                                                input logic [7:0]  msg_type,
                                                input logic [15:0] stock,
                                                input logic [47:0] timestamp,
                                                input logic [63:0] order_ref,
                                                input logic [31:0] shares,
                                                input logic [31:0] price,
                                                input logic [7:0]  side,
                                                input logic [7:0]  flags);
        make_event = pack_event(
            kind,
            msg_type,
            stock,
            16'h0001,
            timestamp,
            order_ref,
            shares,
            price,
            side,
            flags
        );
    endfunction

    task automatic send_event(input logic [255:0] data);
        @(negedge clk);
        event_valid = 1'b1;
        event_data  = data;
        event_keep  = 32'hffff_ffff;
        event_last  = 1'b1;
        while (!event_ready) @(negedge clk);
        @(negedge clk);
        event_valid = 1'b0;
        event_data  = '0;
        event_keep  = '0;
        event_last  = 1'b0;
    endtask

    task automatic expect_quote(input logic [31:0] exp_bid_price,
                                input logic [31:0] exp_bid_shares,
                                input logic [31:0] exp_ask_price,
                                input logic [31:0] exp_ask_shares,
                                input logic [47:0] exp_timestamp,
                                input string msg);
        int cycles;
        cycles = 0;
        quote_ready = 1'b0;
        while (!quote_valid && cycles < 40) begin
            @(posedge clk);
            cycles++;
        end
        check(quote_valid, {msg, " quote valid"});
        check(quote_stock_locate == TARGET_STOCK_LOCATE, {msg, " stock locate"});
        check(quote_bid_price == exp_bid_price, {msg, " bid price"});
        check(quote_bid_shares == exp_bid_shares, {msg, " bid shares"});
        check(quote_ask_price == exp_ask_price, {msg, " ask price"});
        check(quote_ask_shares == exp_ask_shares, {msg, " ask shares"});
        check(quote_timestamp == exp_timestamp, {msg, " timestamp"});
        quote_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        quote_ready = 1'b0;
    endtask

    task automatic expect_no_quote(input string msg);
        repeat (8) @(posedge clk);
        check(!quote_valid, msg);
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER TOP-OF-BOOK TESTS");
        $display("========================================================");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, TARGET_STOCK_LOCATE,
                              48'd1, 64'h0000_0000_0000_0001,
                              32'd10, 32'd1000, "B", 8'h00));
        expect_quote(32'd1000, 32'd10, 32'd0, 32'd0, 48'd1, "initial bid");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, TARGET_STOCK_LOCATE,
                              48'd2, 64'h0000_0000_0000_0002,
                              32'd7, 32'd1050, "S", 8'h00));
        expect_quote(32'd1000, 32'd10, 32'd1050, 32'd7, 48'd2, "initial ask");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, TARGET_STOCK_LOCATE,
                              48'd3, 64'h0000_0000_0000_0003,
                              32'd5, 32'd1010, "B", 8'h00));
        expect_quote(32'd1010, 32'd5, 32'd1050, 32'd7, 48'd3, "better bid");

        send_event(make_event(EVENT_CANCEL, ITCH_CANCEL, TARGET_STOCK_LOCATE,
                              48'd4, 64'h0000_0000_0000_0003,
                              32'd5, 32'd0, 8'h00, 8'h00));
        expect_quote(32'd1000, 32'd10, 32'd1050, 32'd7, 48'd4, "cancel best bid");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, TARGET_STOCK_LOCATE,
                              48'd5, 64'h0000_0000_0000_0004,
                              32'd4, 32'd1040, "S", 8'h00));
        expect_quote(32'd1000, 32'd10, 32'd1040, 32'd4, 48'd5, "better ask");

        send_event(make_event(EVENT_EXECUTE, ITCH_EXECUTED, TARGET_STOCK_LOCATE,
                              48'd6, 64'h0000_0000_0000_0004,
                              32'd2, 32'd0, 8'h00, 8'h00));
        expect_quote(32'd1000, 32'd10, 32'd1040, 32'd2, 48'd6, "partial ask execute");

        send_event(make_event(EVENT_DELETE, ITCH_DELETE, TARGET_STOCK_LOCATE,
                              48'd7, 64'h0000_0000_0000_0004,
                              32'd0, 32'd0, 8'h00, 8'h00));
        expect_quote(32'd1000, 32'd10, 32'd1050, 32'd7, 48'd7, "delete best ask");

        send_event(make_event(EVENT_REPLACE, ITCH_REPLACE, TARGET_STOCK_LOCATE,
                              48'd8, 64'h0000_0000_0000_0001,
                              32'd8, 32'd1020, 8'h00, 8'h00));
        expect_quote(32'd1020, 32'd8, 32'd1050, 32'd7, 48'd8, "replace bid price");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, TARGET_STOCK_LOCATE,
                              48'd9, 64'h0000_0000_0000_0005,
                              32'd2, 32'd1020, "B", 8'h00));
        expect_quote(32'd1020, 32'd10, 32'd1050, 32'd7, 48'd9, "aggregate best bid size");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, 16'h9999,
                              48'd10, 64'h0000_0000_0000_0100,
                              32'd100, 32'd900, "B", 8'h00));
        expect_no_quote("wrong stock emits no quote");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, TARGET_STOCK_LOCATE,
                              48'd11, 64'h0000_0000_0000_0006,
                              32'd1, 32'd2000, "B", FLAG_MALFORMED));
        expect_no_quote("malformed event emits no quote");

        check(accepted_event_count == 32'd11, "accepted event counter");
        check(applied_event_count == 32'd9, "applied event counter");
        check(ignored_event_count == 32'd2, "ignored event counter");
        check(table_overflow_count == 32'd0, "overflow counter");
        check(quote_update_count == 32'd9, "quote update counter");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_top_of_book_tb failed");
    end

endmodule
`default_nettype wire
