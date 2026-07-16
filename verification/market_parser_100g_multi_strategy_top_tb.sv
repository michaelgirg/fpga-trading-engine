`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_100g_multi_strategy_top_tb
// =============================================================================
// End-to-end source-only CMAC AXIS replay for three interleaved symbols.
module market_parser_100g_multi_strategy_top_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [15:0] FEED_UDP_PORT = 16'd5000;
    localparam logic [47:0] SYMBOL_LOCATES = {16'h3333, 16'h2222, 16'h1111};
    localparam int RX_BYTES_PER_BEAT = 64;
    localparam logic [11:0] REG_CONTROL         = 12'h000;
    localparam logic [11:0] REG_STATUS          = 12'h004;
    localparam logic [11:0] REG_FEED_STATUS     = 12'h0b0;
    localparam logic [11:0] REG_FEED_GAP_COUNT  = 12'h0b4;
    localparam logic [11:0] REG_FEED_SUPPRESSED = 12'h0b8;

`include "verification/vectors/multi_symbol_meta.svh"

    typedef logic [7:0] byte_t;

    logic clk = 1'b0;
    logic rst;
    logic feed_recover;
    logic s_axis_cmac_rx_tvalid;
    logic [511:0] s_axis_cmac_rx_tdata;
    logic [63:0] s_axis_cmac_rx_tkeep;
    logic s_axis_cmac_rx_tlast;
    logic s_axis_cmac_rx_tuser_bad_frame;
    logic quote_valid;
    logic quote_ready;
    logic [15:0] quote_stock_locate;
    logic [31:0] quote_bid_price;
    logic [31:0] quote_bid_shares;
    logic [31:0] quote_ask_price;
    logic [31:0] quote_ask_shares;
    logic [47:0] quote_timestamp;
    logic [11:0] s_axi_awaddr;
    logic s_axi_awvalid;
    logic s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0] s_axi_wstrb;
    logic s_axi_wvalid;
    logic s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready;
    logic [11:0] s_axi_araddr;
    logic s_axi_arvalid;
    logic s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready;
    logic [31:0] cmac_accepted_frame_count;
    logic [31:0] cmac_dropped_frame_count;
    logic [31:0] cmac_header_error_count;
    logic [31:0] cmac_payload_packet_count;
    logic [15:0] cmac_payload_fifo_level;
    logic [31:0] book_accepted_event_count;
    logic [31:0] book_applied_event_count;
    logic [31:0] book_ignored_event_count;
    logic [31:0] book_untracked_event_count;
    logic [31:0] book_table_overflow_count;
    logic [31:0] book_quote_update_count;
    logic feed_healthy;
    logic [31:0] feed_gap_count;
    logic [31:0] feed_suppressed_event_count;
    logic [31:0] cmac_axis_accepted_packet_count;
    logic [31:0] cmac_axis_overflow_packet_count;
    logic [31:0] cmac_axis_dropped_beat_count;
    logic [15:0] cmac_axis_fifo_level;
    logic [15:0] cmac_axis_buffered_packet_count;

    byte_t raw_0_mem[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t raw_1_mem[MULTI_SYMBOL_RAW_1_BYTES];
    byte_t raw_2_mem[MULTI_SYMBOL_RAW_2_BYTES];
    byte_t recovery_raw_mem[MULTI_SYMBOL_RAW_0_BYTES];
    logic [191:0] expected_quote_mem[MULTI_SYMBOL_EXPECTED_QUOTES];

    int passed;
    int failed;
    int ingress_stall_cycles_seen;
    int raw_beat_count;

    market_parser_100g_cmac_axis_multi_strategy_top #(
        .FEED_UDP_PORT      (FEED_UDP_PORT),
        .NUM_SYMBOLS        (3),
        .SYMBOL_LOCATES     (SYMBOL_LOCATES),
        .CMAC_RX_FIFO_DEPTH (16),
        .ORDER_TABLE_DEPTH  (8)
    ) DUT (
        .clk                            (clk),
        .rst                            (rst),
        .feed_recover                   (feed_recover),
        .rx_axis_tvalid                 (s_axis_cmac_rx_tvalid),
        .rx_axis_tdata                  (s_axis_cmac_rx_tdata),
        .rx_axis_tkeep                  (s_axis_cmac_rx_tkeep),
        .rx_axis_tlast                  (s_axis_cmac_rx_tlast),
        .rx_axis_tuser                  (s_axis_cmac_rx_tuser_bad_frame),
        .quote_valid                    (quote_valid),
        .quote_ready                    (quote_ready),
        .quote_stock_locate             (quote_stock_locate),
        .quote_bid_price                (quote_bid_price),
        .quote_bid_shares               (quote_bid_shares),
        .quote_ask_price                (quote_ask_price),
        .quote_ask_shares               (quote_ask_shares),
        .quote_timestamp                (quote_timestamp),
        .s_axi_awaddr                   (s_axi_awaddr),
        .s_axi_awvalid                  (s_axi_awvalid),
        .s_axi_awready                  (s_axi_awready),
        .s_axi_wdata                    (s_axi_wdata),
        .s_axi_wstrb                    (s_axi_wstrb),
        .s_axi_wvalid                   (s_axi_wvalid),
        .s_axi_wready                   (s_axi_wready),
        .s_axi_bresp                    (s_axi_bresp),
        .s_axi_bvalid                   (s_axi_bvalid),
        .s_axi_bready                   (s_axi_bready),
        .s_axi_araddr                   (s_axi_araddr),
        .s_axi_arvalid                  (s_axi_arvalid),
        .s_axi_arready                  (s_axi_arready),
        .s_axi_rdata                    (s_axi_rdata),
        .s_axi_rresp                    (s_axi_rresp),
        .s_axi_rvalid                   (s_axi_rvalid),
        .s_axi_rready                   (s_axi_rready),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count   (cmac_axis_dropped_beat_count),
        .cmac_axis_fifo_level           (cmac_axis_fifo_level),
        .cmac_axis_buffered_packet_count(cmac_axis_buffered_packet_count),
        .cmac_accepted_frame_count      (cmac_accepted_frame_count),
        .cmac_dropped_frame_count       (cmac_dropped_frame_count),
        .cmac_header_error_count        (cmac_header_error_count),
        .cmac_payload_packet_count      (cmac_payload_packet_count),
        .cmac_payload_fifo_level        (cmac_payload_fifo_level),
        .book_accepted_event_count      (book_accepted_event_count),
        .book_applied_event_count       (book_applied_event_count),
        .book_ignored_event_count       (book_ignored_event_count),
        .book_untracked_event_count     (book_untracked_event_count),
        .book_table_overflow_count      (book_table_overflow_count),
        .book_quote_update_count        (book_quote_update_count),
        .feed_healthy                   (feed_healthy),
        .feed_gap_count                 (feed_gap_count),
        .feed_suppressed_event_count    (feed_suppressed_event_count)
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
        rst                            = 1'b1;
        feed_recover                   = 1'b0;
        s_axis_cmac_rx_tvalid          = 1'b0;
        s_axis_cmac_rx_tdata           = '0;
        s_axis_cmac_rx_tkeep           = '0;
        s_axis_cmac_rx_tlast           = 1'b0;
        s_axis_cmac_rx_tuser_bad_frame = 1'b0;
        quote_ready                    = 1'b0;
        s_axi_awaddr                   = '0;
        s_axi_awvalid                  = 1'b0;
        s_axi_wdata                    = '0;
        s_axi_wstrb                    = '0;
        s_axi_wvalid                   = 1'b0;
        s_axi_bready                   = 1'b1;
        s_axi_araddr                   = '0;
        s_axi_arvalid                  = 1'b0;
        s_axi_rready                   = 1'b0;
        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);
    endtask

    task automatic load_vectors();
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_0.hex"}, raw_0_mem);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_1.hex"}, raw_1_mem);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_2.hex"}, raw_2_mem);
        $readmemh({VECTOR_DIR, "/multi_symbol_expected_quotes.hex"}, expected_quote_mem);
        for (int idx = 0; idx < MULTI_SYMBOL_RAW_0_BYTES; idx++) begin
            recovery_raw_mem[idx] = raw_0_mem[idx];
        end
        recovery_raw_mem[52] = 8'h00;
        recovery_raw_mem[53] = 8'h00;
        recovery_raw_mem[54] = 8'h00;
        recovery_raw_mem[55] = 8'h00;
        recovery_raw_mem[56] = 8'h00;
        recovery_raw_mem[57] = 8'h00;
        recovery_raw_mem[58] = 8'h07;
        recovery_raw_mem[59] = 8'hd3;
    endtask

    task automatic expect_no_quote(input int cycles, input string msg);
        bit saw_quote;

        saw_quote = 1'b0;
        quote_ready = 1'b1;
        repeat (cycles) begin
            @(posedge clk);
            if (quote_valid) saw_quote = 1'b1;
        end
        quote_ready = 1'b0;
        check(!saw_quote, msg);
    endtask

    task automatic recover_feed();
        axi_write(REG_CONTROL, 32'h0000_0005);
        @(posedge clk);
    endtask

    task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
        @(negedge clk);
        s_axi_awaddr  = addr;
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = data;
        s_axi_wstrb   = 4'hf;
        s_axi_wvalid  = 1'b1;
        while (!(s_axi_awready && s_axi_wready)) @(negedge clk);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_wstrb   = 4'h0;
        while (!s_axi_bvalid) @(negedge clk);
        check(s_axi_bresp == 2'b00, $sformatf("AXI write 0x%03h response OKAY", addr));
        @(negedge clk);
    endtask

    task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
        @(negedge clk);
        s_axi_araddr  = addr;
        s_axi_arvalid = 1'b1;
        s_axi_rready  = 1'b1;
        while (!s_axi_arready) @(negedge clk);
        @(negedge clk);
        s_axi_arvalid = 1'b0;
        while (!s_axi_rvalid) @(negedge clk);
        data = s_axi_rdata;
        check(s_axi_rresp == 2'b00, $sformatf("AXI read 0x%03h response OKAY", addr));
        @(negedge clk);
        s_axi_rready = 1'b0;
    endtask

    task automatic send_packet(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [63:0] beat_keep;

        offset = 0;
        @(negedge clk);
        while (offset < packet_bytes) begin
            beat_bytes = ((packet_bytes - offset) >= RX_BYTES_PER_BEAT) ?
                         RX_BYTES_PER_BEAT : packet_bytes - offset;
            beat_data = '0;
            beat_keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                beat_keep[lane] = 1'b1;
            end

            s_axis_cmac_rx_tvalid          = 1'b1;
            s_axis_cmac_rx_tdata           = beat_data;
            s_axis_cmac_rx_tkeep           = beat_keep;
            s_axis_cmac_rx_tlast           = (offset + beat_bytes >= packet_bytes);
            s_axis_cmac_rx_tuser_bad_frame = 1'b0;
            @(negedge clk);
            offset += beat_bytes;
            raw_beat_count++;
        end

        s_axis_cmac_rx_tvalid = 1'b0;
        s_axis_cmac_rx_tdata  = '0;
        s_axis_cmac_rx_tkeep  = '0;
        s_axis_cmac_rx_tlast  = 1'b0;
    endtask

    task automatic expect_quote_word(input logic [191:0] exp_quote,
                                     input string msg);
        int cycles;
        logic [191:0] observed_quote;

        cycles = 0;
        quote_ready = 1'b0;
        while (!quote_valid && cycles < 2000) begin
            @(posedge clk);
            cycles++;
        end
        observed_quote = {
            quote_timestamp,
            quote_ask_shares,
            quote_ask_price,
            quote_bid_shares,
            quote_bid_price,
            quote_stock_locate
        };
        check(quote_valid, {msg, " quote valid"});
        check(observed_quote == exp_quote, {msg, " matches Python golden model"});
        quote_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        quote_ready = 1'b0;
    endtask

    initial begin : run_tests
        int quote_base;
        logic [31:0] reg_value;

        passed = 0;
        failed = 0;
        ingress_stall_cycles_seen = 0;
        raw_beat_count = 0;
        reset_dut();
        load_vectors();

        $display("\n========================================================");
        $display("MARKET PARSER 100G MULTI-SYMBOL STRATEGY TESTS");
        $display("========================================================");

        quote_base = 0;
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, raw_0_mem);
        for (int idx = 0; idx < MULTI_SYMBOL_PACKET_0_QUOTES; idx++) begin
            expect_quote_word(expected_quote_mem[quote_base + idx],
                              $sformatf("frame 0 quote %0d", idx));
        end
        quote_base += MULTI_SYMBOL_PACKET_0_QUOTES;

        send_packet(MULTI_SYMBOL_RAW_1_BYTES, raw_1_mem);
        for (int idx = 0; idx < MULTI_SYMBOL_PACKET_1_QUOTES; idx++) begin
            expect_quote_word(expected_quote_mem[quote_base + idx],
                              $sformatf("frame 1 quote %0d", idx));
        end
        quote_base += MULTI_SYMBOL_PACKET_1_QUOTES;

        send_packet(MULTI_SYMBOL_RAW_2_BYTES, raw_2_mem);
        for (int idx = 0; idx < MULTI_SYMBOL_PACKET_2_QUOTES; idx++) begin
            expect_quote_word(expected_quote_mem[quote_base + idx],
                              $sformatf("frame 2 quote %0d", idx));
        end
        quote_base += MULTI_SYMBOL_PACKET_2_QUOTES;

        repeat (40) @(posedge clk);
        check(quote_base == MULTI_SYMBOL_EXPECTED_QUOTES, "all golden quotes consumed");
        check(ingress_stall_cycles_seen == 0, "all frames accepted without ingress stalls");
        check(raw_beat_count == MULTI_SYMBOL_EXPECTED_RAW_BEATS, "raw beat count");
        check(cmac_axis_accepted_packet_count == 32'(MULTI_SYMBOL_PACKETS),
              "source-only bridge accepted every packet");
        check(cmac_axis_overflow_packet_count == 32'd0, "source-only bridge has no overflow");
        check(cmac_axis_dropped_beat_count == 32'd0, "source-only bridge drops no beats");
        check(cmac_axis_fifo_level == 16'd0, "source-only bridge FIFO drains");
        check(cmac_axis_buffered_packet_count == 16'd0,
              "source-only bridge has no buffered packet after replay");
        check(cmac_accepted_frame_count == 32'(MULTI_SYMBOL_PACKETS), "accepted frame counter");
        check(cmac_payload_packet_count == 32'(MULTI_SYMBOL_PACKETS), "payload packet counter");
        check(cmac_dropped_frame_count == 32'd0, "dropped frame counter");
        check(cmac_header_error_count == 32'd0, "header error counter");
        check(cmac_payload_fifo_level == 16'd0, "payload FIFO drains");
        check(book_accepted_event_count == 32'(MULTI_SYMBOL_EXPECTED_EVENTS),
              "aggregate accepted event counter");
        check(book_applied_event_count == 32'(MULTI_SYMBOL_EXPECTED_APPLIED),
              "aggregate applied event counter");
        check(book_ignored_event_count == 32'(MULTI_SYMBOL_EXPECTED_IGNORED),
              "aggregate ignored event counter");
        check(book_untracked_event_count == 32'(MULTI_SYMBOL_EXPECTED_UNTRACKED),
              "untracked event counter");
        check(book_table_overflow_count == 32'(MULTI_SYMBOL_EXPECTED_OVERFLOW),
              "aggregate overflow counter");
        check(book_quote_update_count == 32'(MULTI_SYMBOL_EXPECTED_QUOTES),
              "aggregate quote update counter");

        send_packet(MULTI_SYMBOL_RAW_0_BYTES, raw_0_mem);
        expect_no_quote(500, "sequence-gap packet emits no quote");
        check(!feed_healthy, "sequence gap marks feed unhealthy");
        check(feed_gap_count == 32'd1, "sequence gap counted once per packet");
        check(feed_suppressed_event_count == 32'd3,
              "all events from the gap packet are suppressed");
        axi_read(REG_STATUS, reg_value);
        check(!reg_value[5], "aggregate status reports feed unhealthy");
        axi_read(REG_FEED_STATUS, reg_value);
        check(reg_value == 32'd0, "AXI-Lite feed health register reports fault");
        axi_read(REG_FEED_GAP_COUNT, reg_value);
        check(reg_value == 32'd1, "AXI-Lite exposes sequence-gap count");
        axi_read(REG_FEED_SUPPRESSED, reg_value);
        check(reg_value == 32'd3, "AXI-Lite exposes suppressed-event count");
        check(book_accepted_event_count == 32'd0,
              "sequence gap clears aggregate book state and counters");
        check(book_quote_update_count == 32'd0,
              "sequence gap clears pending quote state");

        recover_feed();
        check(feed_healthy, "software recovery rearms the feed guard");
        axi_read(REG_STATUS, reg_value);
        check(reg_value[5], "aggregate status reports recovered feed");
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, recovery_raw_mem);
        for (int idx = 0; idx < MULTI_SYMBOL_PACKET_0_QUOTES; idx++) begin
            expect_quote_word(expected_quote_mem[idx],
                              $sformatf("recovery quote %0d", idx));
        end
        check(feed_healthy, "contiguous recovery packet keeps feed healthy");
        check(feed_gap_count == 32'd1, "recovery does not erase fault history");
        check(feed_suppressed_event_count == 32'd3,
              "recovery does not erase suppression history");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_100g_multi_strategy_top_tb failed");
    end

endmodule
`default_nettype wire
