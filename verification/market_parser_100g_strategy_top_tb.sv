`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_100g_strategy_top_tb
// =============================================================================
// End-to-end smoke test for the strategy-facing top:
// raw Ethernet/IPv4/UDP frame -> MoldUDP64/ITCH parser -> top-of-book quote.
module market_parser_100g_strategy_top_tb #(
    parameter realtime CLK_PERIOD = 3.102ns
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [15:0] FEED_UDP_PORT = 16'd5000;
    localparam logic [15:0] TARGET_STOCK_LOCATE = 16'h1234;
    localparam int HEADER_BYTES = 42;
    localparam int MOLD_HEADER_BYTES = 20;
    localparam int ADD_MSG_BYTES = 36;
    localparam int MESSAGE_BYTES = 2 + ADD_MSG_BYTES;
    localparam int EXPECTED_QUOTES = 3;
    localparam int MOLD_PACKET_BYTES = MOLD_HEADER_BYTES + EXPECTED_QUOTES * MESSAGE_BYTES;
    localparam int RAW_PACKET_BYTES = HEADER_BYTES + MOLD_PACKET_BYTES;
    localparam int RX_BYTES_PER_BEAT = 64;
    localparam int EXPECTED_RAW_BEATS = (RAW_PACKET_BYTES + RX_BYTES_PER_BEAT - 1) / RX_BYTES_PER_BEAT;

    typedef logic [7:0] byte_t;

    logic clk = 1'b0;
    logic rst;

    logic         s_axis_cmac_rx_tvalid;
    logic         s_axis_cmac_rx_tready;
    logic [511:0] s_axis_cmac_rx_tdata;
    logic [ 63:0] s_axis_cmac_rx_tkeep;
    logic         s_axis_cmac_rx_tlast;
    logic         s_axis_cmac_rx_tuser_bad_frame;

    logic         quote_valid;
    logic         quote_ready;
    logic [15:0]  quote_stock_locate;
    logic [31:0]  quote_bid_price;
    logic [31:0]  quote_bid_shares;
    logic [31:0]  quote_ask_price;
    logic [31:0]  quote_ask_shares;
    logic [47:0]  quote_timestamp;

    logic [11:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [ 3:0] s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [ 1:0] s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [11:0] s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [ 1:0] s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    logic [31:0] cmac_accepted_frame_count;
    logic [31:0] cmac_dropped_frame_count;
    logic [31:0] cmac_header_error_count;
    logic [31:0] cmac_payload_packet_count;
    logic [15:0] cmac_payload_fifo_level;

    logic [31:0] book_accepted_event_count;
    logic [31:0] book_applied_event_count;
    logic [31:0] book_ignored_event_count;
    logic [31:0] book_table_overflow_count;
    logic [31:0] book_quote_update_count;

    int passed;
    int failed;
    int ingress_stall_cycles_seen;
    int raw_beat_count;

    byte_t mold_packet_mem[MOLD_PACKET_BYTES];
    byte_t raw_packet_mem  [RAW_PACKET_BYTES];

    market_parser_100g_strategy_top #(
        .FEED_UDP_PORT      (FEED_UDP_PORT),
        .TARGET_STOCK_LOCATE(TARGET_STOCK_LOCATE),
        .ORDER_TABLE_DEPTH  (8)
    ) DUT (
        .clk                            (clk),
        .rst                            (rst),
        .s_axis_cmac_rx_tvalid          (s_axis_cmac_rx_tvalid),
        .s_axis_cmac_rx_tready          (s_axis_cmac_rx_tready),
        .s_axis_cmac_rx_tdata           (s_axis_cmac_rx_tdata),
        .s_axis_cmac_rx_tkeep           (s_axis_cmac_rx_tkeep),
        .s_axis_cmac_rx_tlast           (s_axis_cmac_rx_tlast),
        .s_axis_cmac_rx_tuser_bad_frame (s_axis_cmac_rx_tuser_bad_frame),
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
        .cmac_accepted_frame_count      (cmac_accepted_frame_count),
        .cmac_dropped_frame_count       (cmac_dropped_frame_count),
        .cmac_header_error_count        (cmac_header_error_count),
        .cmac_payload_packet_count      (cmac_payload_packet_count),
        .cmac_payload_fifo_level        (cmac_payload_fifo_level),
        .book_accepted_event_count      (book_accepted_event_count),
        .book_applied_event_count       (book_applied_event_count),
        .book_ignored_event_count       (book_ignored_event_count),
        .book_table_overflow_count      (book_table_overflow_count),
        .book_quote_update_count        (book_quote_update_count)
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

    task automatic put_byte(ref int offset, input byte_t value);
        mold_packet_mem[offset] = value;
        offset++;
    endtask

    task automatic put_u16(ref int offset, input logic [15:0] value);
        put_byte(offset, value[15:8]);
        put_byte(offset, value[7:0]);
    endtask

    task automatic put_u32(ref int offset, input logic [31:0] value);
        put_byte(offset, value[31:24]);
        put_byte(offset, value[23:16]);
        put_byte(offset, value[15:8]);
        put_byte(offset, value[7:0]);
    endtask

    task automatic put_u48(ref int offset, input logic [47:0] value);
        put_byte(offset, value[47:40]);
        put_byte(offset, value[39:32]);
        put_byte(offset, value[31:24]);
        put_byte(offset, value[23:16]);
        put_byte(offset, value[15:8]);
        put_byte(offset, value[7:0]);
    endtask

    task automatic put_u64(ref int offset, input logic [63:0] value);
        put_byte(offset, value[63:56]);
        put_byte(offset, value[55:48]);
        put_byte(offset, value[47:40]);
        put_byte(offset, value[39:32]);
        put_byte(offset, value[31:24]);
        put_byte(offset, value[23:16]);
        put_byte(offset, value[15:8]);
        put_byte(offset, value[7:0]);
    endtask

    task automatic append_add_order(ref int offset,
                                    input logic [15:0] stock_locate,
                                    input logic [15:0] tracking_number,
                                    input logic [47:0] timestamp,
                                    input logic [63:0] order_ref,
                                    input logic [7:0]  side,
                                    input logic [31:0] shares,
                                    input logic [31:0] price);
        put_u16(offset, ADD_MSG_BYTES[15:0]);
        put_byte(offset, "A");
        put_u16(offset, stock_locate);
        put_u16(offset, tracking_number);
        put_u48(offset, timestamp);
        put_u64(offset, order_ref);
        put_byte(offset, side);
        put_u32(offset, shares);
        put_byte(offset, "T");
        put_byte(offset, "E");
        put_byte(offset, "S");
        put_byte(offset, "T");
        put_byte(offset, " ");
        put_byte(offset, " ");
        put_byte(offset, " ");
        put_byte(offset, " ");
        put_u32(offset, price);
    endtask

    task automatic build_mold_payload();
        int offset;

        for (int i = 0; i < MOLD_PACKET_BYTES; i++) begin
            mold_packet_mem[i] = 8'h00;
        end

        offset = 0;
        put_byte(offset, "S");
        put_byte(offset, "I");
        put_byte(offset, "M");
        put_byte(offset, "0");
        put_byte(offset, "0");
        put_byte(offset, "0");
        put_byte(offset, "0");
        put_byte(offset, "0");
        put_byte(offset, "0");
        put_byte(offset, "1");
        put_u64(offset, 64'd1);
        put_u16(offset, EXPECTED_QUOTES[15:0]);

        append_add_order(offset, TARGET_STOCK_LOCATE, 16'h0001, 48'd1,
                         64'h0000_0000_0000_0001, "B", 32'd10, 32'd1000);
        append_add_order(offset, TARGET_STOCK_LOCATE, 16'h0002, 48'd2,
                         64'h0000_0000_0000_0002, "S", 32'd7, 32'd1050);
        append_add_order(offset, TARGET_STOCK_LOCATE, 16'h0003, 48'd3,
                         64'h0000_0000_0000_0003, "B", 32'd5, 32'd1010);

        check(offset == MOLD_PACKET_BYTES, "synthetic MoldUDP64 payload length");
    endtask

    task automatic build_raw_packet();
        logic [15:0] ip_total_length;
        logic [15:0] udp_length;

        ip_total_length = 16'(20 + 8 + MOLD_PACKET_BYTES);
        udp_length      = 16'(8 + MOLD_PACKET_BYTES);

        for (int i = 0; i < RAW_PACKET_BYTES; i++) begin
            raw_packet_mem[i] = 8'h00;
        end

        raw_packet_mem[0]  = 8'h01;
        raw_packet_mem[1]  = 8'h02;
        raw_packet_mem[2]  = 8'h03;
        raw_packet_mem[3]  = 8'h04;
        raw_packet_mem[4]  = 8'h05;
        raw_packet_mem[5]  = 8'h06;
        raw_packet_mem[6]  = 8'h0a;
        raw_packet_mem[7]  = 8'h0b;
        raw_packet_mem[8]  = 8'h0c;
        raw_packet_mem[9]  = 8'h0d;
        raw_packet_mem[10] = 8'h0e;
        raw_packet_mem[11] = 8'h0f;
        raw_packet_mem[12] = 8'h08;
        raw_packet_mem[13] = 8'h00;

        raw_packet_mem[14] = 8'h45;
        raw_packet_mem[15] = 8'h00;
        raw_packet_mem[16] = ip_total_length[15:8];
        raw_packet_mem[17] = ip_total_length[7:0];
        raw_packet_mem[18] = 8'h00;
        raw_packet_mem[19] = 8'h01;
        raw_packet_mem[20] = 8'h40;
        raw_packet_mem[21] = 8'h00;
        raw_packet_mem[22] = 8'h40;
        raw_packet_mem[23] = 8'h11;
        raw_packet_mem[24] = 8'h00;
        raw_packet_mem[25] = 8'h00;
        raw_packet_mem[26] = 8'h0a;
        raw_packet_mem[27] = 8'h00;
        raw_packet_mem[28] = 8'h00;
        raw_packet_mem[29] = 8'h01;
        raw_packet_mem[30] = 8'hef;
        raw_packet_mem[31] = 8'hc0;
        raw_packet_mem[32] = 8'h00;
        raw_packet_mem[33] = 8'h01;

        raw_packet_mem[34] = 8'h9c;
        raw_packet_mem[35] = 8'h40;
        raw_packet_mem[36] = FEED_UDP_PORT[15:8];
        raw_packet_mem[37] = FEED_UDP_PORT[7:0];
        raw_packet_mem[38] = udp_length[15:8];
        raw_packet_mem[39] = udp_length[7:0];
        raw_packet_mem[40] = 8'h00;
        raw_packet_mem[41] = 8'h00;

        for (int i = 0; i < MOLD_PACKET_BYTES; i++) begin
            raw_packet_mem[HEADER_BYTES + i] = mold_packet_mem[i];
        end
    endtask

    task automatic send_packet_100g_burst(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int bytes_left;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [ 63:0] beat_keep;

        offset = 0;
        @(negedge clk);
        while (offset < packet_bytes) begin
            bytes_left = packet_bytes - offset;
            beat_bytes = (bytes_left >= RX_BYTES_PER_BEAT) ? RX_BYTES_PER_BEAT : bytes_left;
            beat_data  = '0;
            beat_keep  = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                beat_keep[lane]        = 1'b1;
            end

            s_axis_cmac_rx_tvalid          = 1'b1;
            s_axis_cmac_rx_tdata           = beat_data;
            s_axis_cmac_rx_tkeep           = beat_keep;
            s_axis_cmac_rx_tlast           = (offset + beat_bytes >= packet_bytes);
            s_axis_cmac_rx_tuser_bad_frame = 1'b0;
            while (!s_axis_cmac_rx_tready) begin
                ingress_stall_cycles_seen++;
                @(negedge clk);
            end
            @(negedge clk);
            offset += beat_bytes;
            raw_beat_count++;
        end
        s_axis_cmac_rx_tvalid          = 1'b0;
        s_axis_cmac_rx_tdata           = '0;
        s_axis_cmac_rx_tkeep           = '0;
        s_axis_cmac_rx_tlast           = 1'b0;
        s_axis_cmac_rx_tuser_bad_frame = 1'b0;
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
        while (!quote_valid && cycles < 2000) begin
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

    initial begin : run_tests
        passed = 0;
        failed = 0;
        ingress_stall_cycles_seen = 0;
        raw_beat_count = 0;
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER 100G STRATEGY TOP TESTS");
        $display("========================================================");

        build_mold_payload();
        build_raw_packet();
        send_packet_100g_burst(RAW_PACKET_BYTES, raw_packet_mem);

        expect_quote(32'd1000, 32'd10, 32'd0, 32'd0, 48'd1, "strategy initial bid");
        expect_quote(32'd1000, 32'd10, 32'd1050, 32'd7, 48'd2, "strategy initial ask");
        expect_quote(32'd1010, 32'd5, 32'd1050, 32'd7, 48'd3, "strategy better bid");

        repeat (20) @(posedge clk);
        check(ingress_stall_cycles_seen == 0, "strategy top accepts short frame with no input stalls");
        check(raw_beat_count == EXPECTED_RAW_BEATS, "strategy top raw beat count");
        check(cmac_accepted_frame_count == 32'd1, "strategy top accepted-frame counter");
        check(cmac_payload_packet_count == 32'd1, "strategy top payload-packet counter");
        check(cmac_dropped_frame_count == 32'd0, "strategy top drop counter stays zero");
        check(cmac_header_error_count == 32'd0, "strategy top header-error counter stays zero");
        check(cmac_payload_fifo_level == 16'd0, "strategy top payload FIFO drains");
        check(book_accepted_event_count == 32'd3, "strategy top book accepted-event counter");
        check(book_applied_event_count == 32'd3, "strategy top book applied-event counter");
        check(book_ignored_event_count == 32'd0, "strategy top book ignored-event counter");
        check(book_table_overflow_count == 32'd0, "strategy top book overflow counter");
        check(book_quote_update_count == 32'd3, "strategy top book quote-update counter");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_100g_strategy_top_tb failed");
    end

endmodule
`default_nettype wire
