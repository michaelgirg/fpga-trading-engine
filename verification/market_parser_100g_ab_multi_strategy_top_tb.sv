`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_ab_multi_strategy_top_tb #(
    parameter string VECTOR_DIR = "verification/vectors"
);
    localparam logic [47:0] SYMBOL_LOCATES = {
        16'h3333, 16'h2222, 16'h1111
    };
    localparam int RX_BYTES_PER_BEAT = 64;

`include "verification/vectors/multi_symbol_meta.svh"

    typedef logic [7:0] byte_t;

    logic clk = 1'b0;
    logic rst;
    logic feed_recover;
    logic feed_activate;
    logic a_valid;
    logic [511:0] a_data;
    logic [63:0] a_keep;
    logic a_last;
    logic a_user;
    logic b_valid;
    logic [511:0] b_data;
    logic [63:0] b_keep;
    logic b_last;
    logic b_user;
    logic quote_valid;
    logic [15:0] quote_stock_locate;
    logic [31:0] quote_bid_price;
    logic [31:0] quote_bid_shares;
    logic [31:0] quote_ask_price;
    logic [31:0] quote_ask_shares;
    logic [47:0] quote_timestamp;
    logic [31:0] cmac_a_accepted_packet_count;
    logic [31:0] cmac_b_accepted_packet_count;
    logic [31:0] cmac_a_overflow_packet_count;
    logic [31:0] cmac_b_overflow_packet_count;
    logic [31:0] ab_selected_a_packet_count;
    logic [31:0] ab_selected_b_packet_count;
    logic [31:0] ab_duplicate_a_packet_count;
    logic [31:0] ab_duplicate_b_packet_count;
    logic [31:0] ab_failover_count;
    logic [31:0] ab_gap_count;
    logic [31:0] ab_divergence_count;
    logic ab_merge_fault;
    logic feed_healthy;
    logic [31:0] feed_session_change_count;
    logic [31:0] book_accepted_event_count;
    logic [31:0] book_applied_event_count;
    logic [31:0] book_quote_update_count;

    byte_t raw_a_0[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t raw_a_1[MULTI_SYMBOL_RAW_1_BYTES];
    byte_t raw_a_2[MULTI_SYMBOL_RAW_2_BYTES];
    byte_t raw_b_0[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t raw_b_1[MULTI_SYMBOL_RAW_1_BYTES];
    logic [191:0] expected_quote_mem[MULTI_SYMBOL_EXPECTED_QUOTES];
    int quote_seen;
    int failed;

    always #1.551ns clk = ~clk;

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    task automatic send_a(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int beat_bytes;
        logic [511:0] beat;
        logic [63:0] keep;
        offset = 0;
        @(negedge clk);
        while (offset < packet_bytes) begin
            beat_bytes = ((packet_bytes - offset) >= RX_BYTES_PER_BEAT) ?
                         RX_BYTES_PER_BEAT : packet_bytes - offset;
            beat = '0;
            keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat[lane*8 +: 8] = packet_mem[offset + lane];
                keep[lane] = 1'b1;
            end
            a_valid = 1'b1;
            a_data = beat;
            a_keep = keep;
            a_last = (offset + beat_bytes >= packet_bytes);
            a_user = 1'b0;
            @(negedge clk);
            offset += beat_bytes;
        end
        a_valid = 1'b0;
        a_data = '0;
        a_keep = '0;
        a_last = 1'b0;
    endtask

    task automatic send_b(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int beat_bytes;
        logic [511:0] beat;
        logic [63:0] keep;
        offset = 0;
        @(negedge clk);
        while (offset < packet_bytes) begin
            beat_bytes = ((packet_bytes - offset) >= RX_BYTES_PER_BEAT) ?
                         RX_BYTES_PER_BEAT : packet_bytes - offset;
            beat = '0;
            keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat[lane*8 +: 8] = packet_mem[offset + lane];
                keep[lane] = 1'b1;
            end
            b_valid = 1'b1;
            b_data = beat;
            b_keep = keep;
            b_last = (offset + beat_bytes >= packet_bytes);
            b_user = 1'b0;
            @(negedge clk);
            offset += beat_bytes;
        end
        b_valid = 1'b0;
        b_data = '0;
        b_keep = '0;
        b_last = 1'b0;
    endtask

    task automatic wait_for_quotes(input int target);
        int cycles;
        cycles = 0;
        while (quote_seen < target && cycles < 4000) begin
            @(posedge clk);
            cycles++;
        end
        check(quote_seen == target,
              $sformatf("received %0d ordered golden quotes", target));
    endtask

    always @(posedge clk) begin
        logic [191:0] observed;
        if (!rst && quote_valid) begin
            observed = {
                quote_timestamp, quote_ask_shares, quote_ask_price,
                quote_bid_shares, quote_bid_price, quote_stock_locate
            };
            if (quote_seen >= MULTI_SYMBOL_EXPECTED_QUOTES ||
                observed != expected_quote_mem[quote_seen]) begin
                $display("FAIL: quote %0d mismatches golden replay", quote_seen);
                failed++;
            end
            quote_seen++;
        end
    end

    market_parser_100g_ab_multi_strategy_top #(
        .NUM_SYMBOLS(3), .SYMBOL_LOCATES(SYMBOL_LOCATES),
        .CMAC_RX_FIFO_DEPTH(16), .AB_MAX_SKEW_CYCLES(8),
        .ORDER_TABLE_DEPTH(8)
    ) dut (
        .clk(clk), .rst(rst), .feed_recover(feed_recover),
        .feed_activate(feed_activate),
        .rx_axis_a_tvalid(a_valid), .rx_axis_a_tdata(a_data),
        .rx_axis_a_tkeep(a_keep), .rx_axis_a_tlast(a_last),
        .rx_axis_a_tuser(a_user), .rx_axis_b_tvalid(b_valid),
        .rx_axis_b_tdata(b_data), .rx_axis_b_tkeep(b_keep),
        .rx_axis_b_tlast(b_last), .rx_axis_b_tuser(b_user),
        .quote_valid(quote_valid), .quote_ready(1'b1),
        .quote_stock_locate(quote_stock_locate),
        .quote_bid_price(quote_bid_price), .quote_bid_shares(quote_bid_shares),
        .quote_ask_price(quote_ask_price), .quote_ask_shares(quote_ask_shares),
        .quote_timestamp(quote_timestamp), .s_axi_awaddr('0),
        .s_axi_awvalid(1'b0), .s_axi_awready(), .s_axi_wdata('0),
        .s_axi_wstrb('0), .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bresp(), .s_axi_bvalid(), .s_axi_bready(1'b1),
        .s_axi_araddr('0), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .cmac_a_accepted_packet_count(cmac_a_accepted_packet_count),
        .cmac_a_overflow_packet_count(cmac_a_overflow_packet_count),
        .cmac_a_dropped_beat_count(), .cmac_a_fifo_level(),
        .cmac_a_fifo_high_watermark(), .cmac_a_buffered_packet_count(),
        .cmac_b_accepted_packet_count(cmac_b_accepted_packet_count),
        .cmac_b_overflow_packet_count(cmac_b_overflow_packet_count),
        .cmac_b_dropped_beat_count(), .cmac_b_fifo_level(),
        .cmac_b_fifo_high_watermark(), .cmac_b_buffered_packet_count(),
        .ab_sequence_initialized(), .ab_expected_sequence(),
        .ab_active_source(), .ab_merge_fault(ab_merge_fault), .ab_gap_event(),
        .ab_selected_a_packet_count(ab_selected_a_packet_count),
        .ab_selected_b_packet_count(ab_selected_b_packet_count),
        .ab_duplicate_a_packet_count(ab_duplicate_a_packet_count),
        .ab_duplicate_b_packet_count(ab_duplicate_b_packet_count),
        .ab_malformed_a_packet_count(), .ab_malformed_b_packet_count(),
        .ab_failover_count(ab_failover_count), .ab_gap_count(ab_gap_count),
        .ab_divergence_count(ab_divergence_count),
        .ab_session_change_a_count(), .ab_session_change_b_count(),
        .cmac_accepted_frame_count(), .cmac_dropped_frame_count(),
        .cmac_header_error_count(), .cmac_payload_packet_count(),
        .cmac_payload_fifo_level(),
        .book_accepted_event_count(book_accepted_event_count),
        .book_applied_event_count(book_applied_event_count),
        .book_ignored_event_count(), .book_untracked_event_count(),
        .book_table_overflow_count(),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy), .feed_rebuilding(),
        .feed_rebuild_ready(), .feed_gap_count(),
        .feed_suppressed_event_count(), .feed_idle_cycles(),
        .feed_timeout_count(), .feed_activation_reject_count(),
        .feed_session_change_count(feed_session_change_count),
        .feed_end_of_session_count()
    );

    initial begin
        failed = 0;
        quote_seen = 0;
        rst = 1'b1;
        feed_recover = 1'b0;
        feed_activate = 1'b0;
        a_valid = 1'b0;
        a_data = '0;
        a_keep = '0;
        a_last = 1'b0;
        a_user = 1'b0;
        b_valid = 1'b0;
        b_data = '0;
        b_keep = '0;
        b_last = 1'b0;
        b_user = 1'b0;

        $readmemh({VECTOR_DIR, "/multi_symbol_raw_0.hex"}, raw_a_0);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_1.hex"}, raw_a_1);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_2.hex"}, raw_a_2);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_0.hex"}, raw_b_0);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_1.hex"}, raw_b_1);
        $readmemh({VECTOR_DIR, "/multi_symbol_expected_quotes.hex"},
                  expected_quote_mem);
        for (int idx = 42; idx < 52; idx++) begin
            raw_b_0[idx] = raw_b_0[idx] ^ 8'h5a;
            raw_b_1[idx] = raw_b_1[idx] ^ 8'h5a;
        end

        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);

        fork
            send_a(MULTI_SYMBOL_RAW_0_BYTES, raw_a_0);
            send_b(MULTI_SYMBOL_RAW_0_BYTES, raw_b_0);
        join
        wait_for_quotes(MULTI_SYMBOL_PACKET_0_QUOTES);
        check(ab_selected_a_packet_count + ab_selected_b_packet_count == 1 &&
              ab_duplicate_a_packet_count + ab_duplicate_b_packet_count == 1,
              "duplicate first packet is emitted once");

        send_b(MULTI_SYMBOL_RAW_1_BYTES, raw_b_1);
        wait_for_quotes(MULTI_SYMBOL_PACKET_0_QUOTES +
                        MULTI_SYMBOL_PACKET_1_QUOTES);
        send_a(MULTI_SYMBOL_RAW_2_BYTES, raw_a_2);
        wait_for_quotes(MULTI_SYMBOL_EXPECTED_QUOTES);
        repeat (80) @(posedge clk);

        check(cmac_a_accepted_packet_count == 2 &&
              cmac_b_accepted_packet_count == 2,
              "both source-only CMAC packet buffers accept their traffic");
        check(cmac_a_overflow_packet_count == 0 &&
              cmac_b_overflow_packet_count == 0,
              "neither redundant input buffer overflows");
        check(ab_selected_a_packet_count + ab_selected_b_packet_count == 3 &&
              ab_duplicate_a_packet_count + ab_duplicate_b_packet_count == 1,
              "three unique sequence packets survive A/B deduplication");
        check(ab_failover_count == 2,
              "alternating unique packets record two source failovers");
        check(!ab_merge_fault && ab_gap_count == 0 && ab_divergence_count == 0,
              "ordered redundant replay creates no merge fault");
        check(feed_healthy && feed_session_change_count == 0,
              "session normalization prevents false failover session faults");
        check(book_accepted_event_count == MULTI_SYMBOL_EXPECTED_EVENTS &&
              book_applied_event_count == MULTI_SYMBOL_EXPECTED_APPLIED &&
              book_quote_update_count == MULTI_SYMBOL_EXPECTED_QUOTES,
              "merged feed preserves end-to-end parser and book accounting");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
