`timescale 1ns/1ps
`default_nettype none

module market_parser_book_throughput_tb #(
    parameter int ORDER_TABLE_DEPTH = 16
);
    import market_parser_pkg::*;
    localparam int EVENTS = 32;
    localparam realtime CLK_PERIOD = 3.102ns;
    logic clk = 0;
    logic rst = 1;
    logic event_valid = 0;
    logic event_ready;
    logic [255:0] event_data = '0;
    logic [63:0] new_ref = 0;
    logic quote_valid;
    logic [31:0] bid_price, bid_shares, ask_price, ask_shares;
    logic [47:0] quote_timestamp;
    logic [31:0] accepted_count, applied_count, ignored_count, overflow_count;
    int failed = 0;
    int cycle = 0;
    int accepted = 0;
    int received = 0;
    int accepted_cycle[EVENTS];
    int latency_min = 32'h7fffffff;
    int latency_max = 0;
    int first_accept = 0;
    int last_accept = 0;
    int interval_min = 32'h7fffffff;
    int interval_max = 0;

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    market_parser_top_of_book #(
        .ORDER_TABLE_DEPTH(ORDER_TABLE_DEPTH), .TARGET_STOCK_LOCATE(16'h1234)
    ) dut (
        .clk(clk), .rst(rst), .event_valid(event_valid), .event_ready(event_ready),
        .event_data(event_data), .event_new_order_ref(new_ref),
        .event_keep(32'hffffffff), .event_last(1'b1),
        .quote_valid(quote_valid), .quote_ready(1'b1), .quote_stock_locate(),
        .quote_bid_price(bid_price), .quote_bid_shares(bid_shares),
        .quote_ask_price(ask_price), .quote_ask_shares(ask_shares),
        .quote_timestamp(quote_timestamp), .accepted_event_count(accepted_count),
        .applied_event_count(applied_count), .ignored_event_count(ignored_count),
        .table_overflow_count(overflow_count), .quote_update_count()
    );

    always @(posedge clk) begin
        int elapsed;
        if (!rst) begin
            cycle++;
            if (event_valid && event_ready) begin
                if (accepted >= EVENTS) $fatal(1, "Unexpected extra accepted event");
                accepted_cycle[accepted] = cycle;
                if (accepted == 0) first_accept = cycle;
                else begin
                    elapsed = cycle - last_accept;
                    if (elapsed < interval_min) interval_min = elapsed;
                    if (elapsed > interval_max) interval_max = elapsed;
                end
                last_accept = cycle;
                accepted++;
            end
            if (quote_valid) begin
                if (received >= accepted) $fatal(1, "Unexpected extra quote");
                if (bid_price !== 32'(10000+received) ||
                    bid_shares !== 32'(100+received) || ask_price !== 0 ||
                    ask_shares !== 0 || quote_timestamp !== 48'(received+1)) begin
                    $display("FAIL: quote %0d differs from expected replacement book", received);
                    failed++;
                end
                elapsed = cycle - accepted_cycle[received];
                if (elapsed < latency_min) latency_min = elapsed;
                if (elapsed > latency_max) latency_max = elapsed;
                received++;
            end
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst = 0;
        // Keep work continuously available: one Add followed by exact-ref Replaces.
        for (int idx = 0; idx < EVENTS; idx++) begin
            @(negedge clk);
            event_valid = 1;
            event_data = '0;
            event_data[7:0] = idx == 0 ? EVENT_ADD : EVENT_REPLACE;
            event_data[31:16] = 16'h1234;
            event_data[95:48] = 48'(idx+1);
            event_data[159:96] = idx == 0 ? 64'd1 : 64'(idx);
            event_data[191:160] = 32'(100+idx);
            event_data[223:192] = 32'(10000+idx);
            event_data[231:224] = "B";
            new_ref = idx == 0 ? 64'd0 : 64'(idx+1);
            do @(posedge clk); while (!event_ready);
        end
        @(negedge clk);
        event_valid = 0;
        wait (received == EVENTS);
        @(negedge clk);
        if (accepted_count != EVENTS || applied_count != EVENTS ||
            ignored_count != 0 || overflow_count != 0) begin
            $display("FAIL: benchmark event counters do not conserve updates");
            failed++;
        end
        $display("BOOK BENCHMARK depth=%0d events=%0d latency_cycles=%0d..%0d accept_interval_cycles=%0d..%0d nominal_rate_mevents_s=%0.3f",
                 ORDER_TABLE_DEPTH, EVENTS, latency_min, latency_max, interval_min,
                 interval_max, real'(EVENTS-1)*1000.0 / (CLK_PERIOD * real'(last_accept-first_accept)));
        $display("Tests failed: %0d", failed);
        if (failed == 0) $finish;
        else $fatal(1, "book throughput benchmark failed");
    end
endmodule
`default_nettype wire
