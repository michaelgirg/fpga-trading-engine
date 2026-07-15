`timescale 1ns / 100ps
`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_multi_symbol_top_of_book_tb
// =============================================================================
module market_parser_multi_symbol_top_of_book_tb #(
    parameter realtime CLK_PERIOD = 3.102ns
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [15:0] STOCK_A = 16'h1111;
    localparam logic [15:0] STOCK_B = 16'h2222;
    localparam logic [15:0] STOCK_C = 16'h3333;
    localparam logic [47:0] SYMBOL_LOCATES = {STOCK_C, STOCK_B, STOCK_A};

    logic clk = 1'b0;
    logic rst;
    logic event_valid;
    logic event_ready;
    logic [255:0] event_data;
    logic [63:0] event_new_order_ref;
    logic [31:0] event_keep;
    logic event_last;
    logic quote_valid;
    logic quote_ready;
    logic [15:0] quote_stock_locate;
    logic [31:0] quote_bid_price;
    logic [31:0] quote_bid_shares;
    logic [31:0] quote_ask_price;
    logic [31:0] quote_ask_shares;
    logic [47:0] quote_timestamp;
    logic [31:0] accepted_event_count;
    logic [31:0] applied_event_count;
    logic [31:0] ignored_event_count;
    logic [31:0] untracked_event_count;
    logic [31:0] table_overflow_count;
    logic [31:0] quote_update_count;

    int passed;
    int failed;

    market_parser_multi_symbol_top_of_book #(
        .NUM_SYMBOLS      (3),
        .ORDER_TABLE_DEPTH(8),
        .SYMBOL_LOCATES   (SYMBOL_LOCATES)
    ) DUT (
        .clk                  (clk),
        .rst                  (rst),
        .event_valid          (event_valid),
        .event_ready          (event_ready),
        .event_data           (event_data),
        .event_new_order_ref  (event_new_order_ref),
        .event_keep           (event_keep),
        .event_last           (event_last),
        .quote_valid          (quote_valid),
        .quote_ready          (quote_ready),
        .quote_stock_locate   (quote_stock_locate),
        .quote_bid_price      (quote_bid_price),
        .quote_bid_shares     (quote_bid_shares),
        .quote_ask_price      (quote_ask_price),
        .quote_ask_shares     (quote_ask_shares),
        .quote_timestamp      (quote_timestamp),
        .accepted_event_count (accepted_event_count),
        .applied_event_count  (applied_event_count),
        .ignored_event_count  (ignored_event_count),
        .untracked_event_count(untracked_event_count),
        .table_overflow_count (table_overflow_count),
        .quote_update_count   (quote_update_count)
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
        rst                 = 1'b1;
        event_valid         = 1'b0;
        event_data          = '0;
        event_new_order_ref = '0;
        event_keep          = '0;
        event_last          = 1'b0;
        quote_ready         = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    endtask

    function automatic logic [255:0] make_event(input logic [7:0] kind,
                                                input logic [7:0] msg_type,
                                                input logic [15:0] stock,
                                                input logic [47:0] timestamp,
                                                input logic [63:0] order_ref,
                                                input logic [31:0] shares,
                                                input logic [31:0] price,
                                                input logic [7:0] side,
                                                input logic [7:0] flags);
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

    task automatic send_event(input logic [255:0] data,
                              input logic [63:0] new_order_ref);
        @(negedge clk);
        event_valid         = 1'b1;
        event_data          = data;
        event_new_order_ref = new_order_ref;
        event_keep          = 32'hffff_ffff;
        event_last          = 1'b1;
        while (!event_ready) @(negedge clk);
        @(negedge clk);
        event_valid         = 1'b0;
        event_data          = '0;
        event_new_order_ref = '0;
        event_keep          = '0;
        event_last          = 1'b0;
    endtask

    task automatic expect_quote(input logic [15:0] exp_stock,
                                input logic [31:0] exp_bid_price,
                                input logic [31:0] exp_bid_shares,
                                input logic [31:0] exp_ask_price,
                                input logic [31:0] exp_ask_shares,
                                input logic [47:0] exp_timestamp,
                                input string msg);
        int cycles;
        logic [191:0] held_quote;

        cycles = 0;
        quote_ready = 1'b0;
        while (!quote_valid && cycles < 50) begin
            @(posedge clk);
            cycles++;
        end

        check(quote_valid, {msg, " quote valid"});
        check(quote_stock_locate == exp_stock, {msg, " stock locate"});
        check(quote_bid_price == exp_bid_price, {msg, " bid price"});
        check(quote_bid_shares == exp_bid_shares, {msg, " bid shares"});
        check(quote_ask_price == exp_ask_price, {msg, " ask price"});
        check(quote_ask_shares == exp_ask_shares, {msg, " ask shares"});
        check(quote_timestamp == exp_timestamp, {msg, " timestamp"});
        check(!event_ready, {msg, " globally backpressures events while quote is stalled"});

        held_quote = {
            quote_stock_locate,
            quote_bid_price,
            quote_bid_shares,
            quote_ask_price,
            quote_ask_shares,
            quote_timestamp
        };
        repeat (2) begin
            @(posedge clk);
            check(quote_valid, {msg, " remains valid under backpressure"});
            check({quote_stock_locate, quote_bid_price, quote_bid_shares,
                   quote_ask_price, quote_ask_shares, quote_timestamp} == held_quote,
                  {msg, " remains stable under backpressure"});
        end

        quote_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        quote_ready = 1'b0;
    endtask

    task automatic expect_no_quote(input string msg);
        repeat (15) @(posedge clk);
        check(!quote_valid, msg);
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER MULTI-SYMBOL TOP-OF-BOOK TESTS");
        $display("========================================================");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, STOCK_A, 48'd1, 64'h1,
                              32'd10, 32'd1000, "B", 8'h00), 64'd0);
        expect_quote(STOCK_A, 32'd1000, 32'd10, 32'd0, 32'd0, 48'd1,
                     "stock A initial bid");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, STOCK_B, 48'd2, 64'h2,
                              32'd7, 32'd2050, "S", 8'h00), 64'd0);
        expect_quote(STOCK_B, 32'd0, 32'd0, 32'd2050, 32'd7, 48'd2,
                     "stock B initial ask");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, STOCK_C, 48'd3, 64'h3,
                              32'd3, 32'd3000, "B", 8'h00), 64'd0);
        expect_quote(STOCK_C, 32'd3000, 32'd3, 32'd0, 32'd0, 48'd3,
                     "stock C initial bid");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, STOCK_A, 48'd4, 64'h4,
                              32'd4, 32'd1050, "S", 8'h00), 64'd0);
        expect_quote(STOCK_A, 32'd1000, 32'd10, 32'd1050, 32'd4, 48'd4,
                     "stock A ask preserves bid");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, STOCK_B, 48'd5, 64'h5,
                              32'd8, 32'd2000, "B", 8'h00), 64'd0);
        expect_quote(STOCK_B, 32'd2000, 32'd8, 32'd2050, 32'd7, 48'd5,
                     "stock B bid preserves ask");

        send_event(make_event(EVENT_REPLACE, ITCH_REPLACE, STOCK_A, 48'd6, 64'h1,
                              32'd9, 32'd1010, 8'h00, 8'h00), 64'h10);
        expect_quote(STOCK_A, 32'd1010, 32'd9, 32'd1050, 32'd4, 48'd6,
                     "stock A replace installs new reference");

        send_event(make_event(EVENT_CANCEL, ITCH_CANCEL, STOCK_A, 48'd7, 64'h1,
                              32'd1, 32'd0, 8'h00, 8'h00), 64'd0);
        expect_no_quote("stock A retired reference is ignored");

        send_event(make_event(EVENT_CANCEL, ITCH_CANCEL, STOCK_A, 48'd8, 64'h10,
                              32'd4, 32'd0, 8'h00, 8'h00), 64'd0);
        expect_quote(STOCK_A, 32'd1010, 32'd5, 32'd1050, 32'd4, 48'd8,
                     "stock A replacement reference resolves");

        send_event(make_event(EVENT_DELETE, ITCH_DELETE, STOCK_B, 48'd9, 64'h2,
                              32'd0, 32'd0, 8'h00, 8'h00), 64'd0);
        expect_quote(STOCK_B, 32'd2000, 32'd8, 32'd0, 32'd0, 48'd9,
                     "stock B delete does not disturb other books");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, 16'h9999, 48'd10, 64'h20,
                              32'd1, 32'd9000, "B", 8'h00), 64'd0);
        expect_no_quote("untracked symbol is accepted without a quote");

        send_event(make_event(EVENT_ADD, ITCH_ADD_ORDER, STOCK_C, 48'd11, 64'h21,
                              32'd1, 32'd3100, "B", FLAG_MALFORMED), 64'd0);
        expect_no_quote("malformed tracked event is ignored");

        check(accepted_event_count == 32'd11, "aggregate accepted event counter");
        check(applied_event_count == 32'd8, "aggregate applied event counter");
        check(ignored_event_count == 32'd3, "aggregate ignored event counter");
        check(untracked_event_count == 32'd1, "untracked event counter");
        check(table_overflow_count == 32'd0, "aggregate overflow counter");
        check(quote_update_count == 32'd8, "aggregate quote update counter");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_multi_symbol_top_of_book_tb failed");
    end

endmodule
`default_nettype wire
