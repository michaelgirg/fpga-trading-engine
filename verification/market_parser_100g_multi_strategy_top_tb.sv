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
    localparam int END_OF_SESSION_RAW_BYTES = 62;
    localparam int MTU_MESSAGE_COUNT = 100;
    localparam int MTU_MESSAGE_BYTES = 12;
    localparam int MTU_MOLD_PAYLOAD_BYTES = 20 + MTU_MESSAGE_COUNT * (2 + MTU_MESSAGE_BYTES);
    localparam int MTU_UDP_LENGTH = 8 + MTU_MOLD_PAYLOAD_BYTES;
    localparam int MTU_IP_TOTAL_LENGTH = 20 + MTU_UDP_LENGTH;
    localparam int MTU_RAW_BYTES = 14 + MTU_IP_TOTAL_LENGTH;
    localparam int MTU_RAW_BEATS = (MTU_RAW_BYTES + RX_BYTES_PER_BEAT - 1) /
                                   RX_BYTES_PER_BEAT;
    localparam logic [11:0] REG_CONTROL         = 12'h000;
    localparam logic [11:0] REG_STATUS          = 12'h004;
    localparam logic [11:0] REG_FEED_STATUS     = 12'h0b0;
    localparam logic [11:0] REG_FEED_GAP_COUNT  = 12'h0b4;
    localparam logic [11:0] REG_FEED_SUPPRESSED = 12'h0b8;
    localparam logic [11:0] REG_CMAC_AXIS_FIFO  = 12'h0bc;
    localparam logic [11:0] REG_CMAC_AXIS_ACCEPT = 12'h0c0;
    localparam logic [11:0] REG_CMAC_AXIS_OVFL  = 12'h0c4;
    localparam logic [11:0] REG_CMAC_AXIS_DROP  = 12'h0c8;
    localparam logic [11:0] REG_FEED_IDLE_CYCLES = 12'h0cc;
    localparam logic [11:0] REG_FEED_TIMEOUT_CFG = 12'h0d0;
    localparam logic [11:0] REG_FEED_TIMEOUT_CNT = 12'h0d4;
    localparam logic [11:0] REG_FEED_ACT_REJECT  = 12'h0d8;
    localparam logic [11:0] REG_FEED_SESSION_CHANGE = 12'h0dc;
    localparam logic [11:0] REG_FEED_END_OF_SESSION = 12'h0e0;

`include "verification/vectors/multi_symbol_meta.svh"

    typedef logic [7:0] byte_t;

    logic clk = 1'b0;
    logic rst;
    logic feed_recover;
    logic feed_activate;
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
    logic feed_rebuilding;
    logic feed_rebuild_ready;
    logic [31:0] feed_gap_count;
    logic [31:0] feed_suppressed_event_count;
    logic [31:0] feed_idle_cycles;
    logic [31:0] feed_timeout_count;
    logic [31:0] feed_activation_reject_count;
    logic [31:0] feed_session_change_count;
    logic [31:0] feed_end_of_session_count;
    logic [31:0] cmac_axis_accepted_packet_count;
    logic [31:0] cmac_axis_overflow_packet_count;
    logic [31:0] cmac_axis_dropped_beat_count;
    logic [15:0] cmac_axis_fifo_level;
    logic [15:0] cmac_axis_fifo_high_watermark;
    logic [15:0] cmac_axis_buffered_packet_count;

    byte_t raw_0_mem[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t raw_1_mem[MULTI_SYMBOL_RAW_1_BYTES];
    byte_t raw_2_mem[MULTI_SYMBOL_RAW_2_BYTES];
    byte_t recovery_raw_mem[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t session_change_raw_mem[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t end_of_session_raw_mem[END_OF_SESSION_RAW_BYTES];
    byte_t mtu_raw_0_mem[MTU_RAW_BYTES];
    byte_t mtu_raw_1_mem[MTU_RAW_BYTES];
    logic [191:0] expected_quote_mem[MULTI_SYMBOL_EXPECTED_QUOTES];

    int passed;
    int failed;
    int ingress_stall_cycles_seen;
    int raw_beat_count;

    market_parser_100g_cmac_axis_multi_strategy_top #(
        .FEED_UDP_PORT      (FEED_UDP_PORT),
        .NUM_SYMBOLS        (3),
        .SYMBOL_LOCATES     (SYMBOL_LOCATES),
        .CMAC_RX_FIFO_DEPTH (64),
        .ORDER_TABLE_DEPTH  (8)
    ) DUT (
        .clk                            (clk),
        .rst                            (rst),
        .feed_recover                   (feed_recover),
        .feed_activate                  (feed_activate),
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
        .cmac_axis_fifo_high_watermark  (cmac_axis_fifo_high_watermark),
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
        .feed_rebuilding                (feed_rebuilding),
        .feed_rebuild_ready             (feed_rebuild_ready),
        .feed_gap_count                 (feed_gap_count),
        .feed_suppressed_event_count    (feed_suppressed_event_count),
        .feed_idle_cycles               (feed_idle_cycles),
        .feed_timeout_count             (feed_timeout_count),
        .feed_activation_reject_count   (feed_activation_reject_count),
        .feed_session_change_count      (feed_session_change_count),
        .feed_end_of_session_count      (feed_end_of_session_count)
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
        feed_activate                  = 1'b0;
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
            session_change_raw_mem[idx] = raw_0_mem[idx];
            if (idx < END_OF_SESSION_RAW_BYTES) begin
                end_of_session_raw_mem[idx] = raw_0_mem[idx];
            end
        end
        recovery_raw_mem[52] = 8'h11;
        recovery_raw_mem[53] = 8'h22;
        recovery_raw_mem[54] = 8'h33;
        recovery_raw_mem[55] = 8'h44;
        recovery_raw_mem[56] = 8'h55;
        recovery_raw_mem[57] = 8'h66;
        recovery_raw_mem[58] = 8'h77;
        recovery_raw_mem[59] = 8'h88;
        session_change_raw_mem[42] = raw_0_mem[42] ^ 8'h01;
        session_change_raw_mem[52] = 8'h00;
        session_change_raw_mem[53] = 8'h00;
        session_change_raw_mem[54] = 8'h00;
        session_change_raw_mem[55] = 8'h00;
        session_change_raw_mem[56] = 8'h00;
        session_change_raw_mem[57] = 8'h00;
        session_change_raw_mem[58] = 8'h07;
        session_change_raw_mem[59] = 8'hdb;
        end_of_session_raw_mem[52] = 8'h11;
        end_of_session_raw_mem[53] = 8'h22;
        end_of_session_raw_mem[54] = 8'h33;
        end_of_session_raw_mem[55] = 8'h44;
        end_of_session_raw_mem[56] = 8'h55;
        end_of_session_raw_mem[57] = 8'h66;
        end_of_session_raw_mem[58] = 8'h77;
        end_of_session_raw_mem[59] = 8'h8b;
        end_of_session_raw_mem[60] = 8'hff;
        end_of_session_raw_mem[61] = 8'hff;
        end_of_session_raw_mem[16] = 8'h00;
        end_of_session_raw_mem[17] = 8'h30;
        end_of_session_raw_mem[38] = 8'h00;
        end_of_session_raw_mem[39] = 8'h1c;
    endtask

    task automatic build_mtu_system_packet();
        int len_offset;
        int msg_start;

        for (int idx = 0; idx < MTU_RAW_BYTES; idx++) begin
            mtu_raw_0_mem[idx] = 8'h00;
            mtu_raw_1_mem[idx] = 8'h00;
        end
        for (int idx = 0; idx < 62; idx++) begin
            mtu_raw_0_mem[idx] = raw_0_mem[idx];
        end

        mtu_raw_0_mem[16] = 8'(MTU_IP_TOTAL_LENGTH >> 8);
        mtu_raw_0_mem[17] = 8'(MTU_IP_TOTAL_LENGTH);
        mtu_raw_0_mem[38] = 8'(MTU_UDP_LENGTH >> 8);
        mtu_raw_0_mem[39] = 8'(MTU_UDP_LENGTH);
        mtu_raw_0_mem[52] = 8'h00;
        mtu_raw_0_mem[53] = 8'h00;
        mtu_raw_0_mem[54] = 8'h00;
        mtu_raw_0_mem[55] = 8'h00;
        mtu_raw_0_mem[56] = 8'h00;
        mtu_raw_0_mem[57] = 8'h00;
        mtu_raw_0_mem[58] = 8'h00;
        mtu_raw_0_mem[59] = 8'h01;
        mtu_raw_0_mem[60] = 8'(MTU_MESSAGE_COUNT >> 8);
        mtu_raw_0_mem[61] = 8'(MTU_MESSAGE_COUNT);

        for (int idx = 0; idx < MTU_MESSAGE_COUNT; idx++) begin
            len_offset = 62 + idx * (2 + MTU_MESSAGE_BYTES);
            msg_start = len_offset + 2;
            mtu_raw_0_mem[len_offset] = 8'h00;
            mtu_raw_0_mem[len_offset + 1] = 8'(MTU_MESSAGE_BYTES);
            mtu_raw_0_mem[msg_start] = "S";
            mtu_raw_0_mem[msg_start + 1] = 8'h77;
            mtu_raw_0_mem[msg_start + 2] = 8'h77;
            mtu_raw_0_mem[msg_start + 3] = 8'(idx >> 8);
            mtu_raw_0_mem[msg_start + 4] = 8'(idx);
            mtu_raw_0_mem[msg_start + 5] = 8'h00;
            mtu_raw_0_mem[msg_start + 6] = 8'h00;
            mtu_raw_0_mem[msg_start + 7] = 8'h00;
            mtu_raw_0_mem[msg_start + 8] = 8'h00;
            mtu_raw_0_mem[msg_start + 9] = 8'h00;
            mtu_raw_0_mem[msg_start + 10] = 8'(idx);
            mtu_raw_0_mem[msg_start + 11] = "O";
        end

        for (int idx = 0; idx < MTU_RAW_BYTES; idx++) begin
            mtu_raw_1_mem[idx] = mtu_raw_0_mem[idx];
        end
        mtu_raw_1_mem[59] = 8'(1 + MTU_MESSAGE_COUNT);
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

    task automatic activate_feed();
        axi_write(REG_CONTROL, 32'h0000_0009);
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

    task automatic send_packet_pair_contiguous(input int packet_bytes,
                                                input byte_t packet_0_mem[],
                                                input byte_t packet_1_mem[]);
        int packet_idx;
        int offset;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [63:0] beat_keep;

        packet_idx = 0;
        offset = 0;
        @(negedge clk);
        while (packet_idx < 2) begin
            beat_bytes = ((packet_bytes - offset) >= RX_BYTES_PER_BEAT) ?
                         RX_BYTES_PER_BEAT : packet_bytes - offset;
            beat_data = '0;
            beat_keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                if (packet_idx == 0) begin
                    beat_data[lane*8 +: 8] = packet_0_mem[offset + lane];
                end else begin
                    beat_data[lane*8 +: 8] = packet_1_mem[offset + lane];
                end
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
            if (offset >= packet_bytes) begin
                packet_idx++;
                offset = 0;
            end
        end

        s_axis_cmac_rx_tvalid = 1'b0;
        s_axis_cmac_rx_tdata  = '0;
        s_axis_cmac_rx_tkeep  = '0;
        s_axis_cmac_rx_tlast  = 1'b0;
    endtask

    task automatic send_oversize_packet(input int beats);
        @(negedge clk);
        for (int idx = 0; idx < beats; idx++) begin
            s_axis_cmac_rx_tvalid          = 1'b1;
            s_axis_cmac_rx_tdata           = 512'(idx);
            s_axis_cmac_rx_tkeep           = '1;
            s_axis_cmac_rx_tlast           = (idx == beats - 1);
            s_axis_cmac_rx_tuser_bad_frame = 1'b0;
            @(negedge clk);
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
        build_mtu_system_packet();

        $display("\n========================================================");
        $display("MARKET PARSER 100G MULTI-SYMBOL STRATEGY TESTS");
        $display("========================================================");

        send_packet_pair_contiguous(MTU_RAW_BYTES, mtu_raw_0_mem, mtu_raw_1_mem);
        expect_no_quote(6000, "back-to-back near-MTU system-event packets emit no quote");
        check(MTU_IP_TOTAL_LENGTH <= 1500 && MTU_RAW_BYTES <= 1514,
              "near-MTU frames remain within the standard Ethernet envelope");
        check(raw_beat_count == 2 * MTU_RAW_BEATS,
              "near-MTU frames arrive as contiguous 512-bit beats");
        check(cmac_axis_accepted_packet_count == 32'd2,
              "CMAC bridge accepts both near-MTU packets atomically");
        check(cmac_axis_overflow_packet_count == 32'd0 &&
              cmac_axis_dropped_beat_count == 32'd0,
              "back-to-back near-MTU packets cause no bridge loss");
        check(cmac_axis_fifo_high_watermark >= 16'(MTU_RAW_BEATS) &&
              cmac_axis_fifo_high_watermark <= 16'(2 * MTU_RAW_BEATS),
              "CMAC bridge absorbs the back-to-back near-MTU burst");
        check(cmac_accepted_frame_count == 32'd2 && cmac_payload_packet_count == 32'd2,
              "UDP ingress accepts both near-MTU feed frames");
        check(book_accepted_event_count == 32'(2 * MTU_MESSAGE_COUNT),
              "parser emits every near-MTU ITCH message");
        check(book_ignored_event_count == 32'(2 * MTU_MESSAGE_COUNT),
              "book path accounts for every near-MTU system event");
        check(feed_healthy && feed_gap_count == 32'd0,
              "near-MTU packet preserves feed continuity");

        reset_dut();
        raw_beat_count = 0;

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
        check(cmac_axis_fifo_high_watermark != 16'd0,
              "source-only bridge records occupancy high watermark");
        check(cmac_axis_buffered_packet_count == 16'd0,
              "source-only bridge has no buffered packet after replay");
        axi_read(REG_CMAC_AXIS_FIFO, reg_value);
        check(reg_value == {cmac_axis_fifo_high_watermark, 16'd0},
              "AXI-Lite exposes bridge FIFO level and high watermark");
        axi_read(REG_CMAC_AXIS_ACCEPT, reg_value);
        check(reg_value == 32'(MULTI_SYMBOL_PACKETS),
              "AXI-Lite exposes accepted CMAC packet count");
        axi_read(REG_CMAC_AXIS_OVFL, reg_value);
        check(reg_value == 32'd0, "AXI-Lite reports zero CMAC packet overflow");
        axi_read(REG_CMAC_AXIS_DROP, reg_value);
        check(reg_value == 32'd0, "AXI-Lite reports zero CMAC dropped beats");
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

        activate_feed();
        check(feed_healthy && !feed_rebuilding,
              "activation outside rebuild leaves healthy feed unchanged");
        check(feed_activation_reject_count == 32'd1,
              "activation outside rebuild is counted as rejected");

        send_packet(MULTI_SYMBOL_RAW_0_BYTES, session_change_raw_mem);
        expect_no_quote(500, "session-change packet emits no quote");
        check(!feed_healthy && !feed_rebuilding,
              "unexpected MoldUDP64 session change invalidates feed");
        check(feed_session_change_count == 32'd1,
              "session change has distinct fault telemetry");
        check(feed_suppressed_event_count == 32'd3,
              "session-change packet events are suppressed");
        check(feed_gap_count == 32'd0,
              "session change does not masquerade as a sequence gap");
        axi_read(REG_STATUS, reg_value);
        check(reg_value[10] && !reg_value[5],
              "aggregate status identifies session fault and unhealthy feed");
        axi_read(REG_FEED_STATUS, reg_value);
        check(reg_value[5] && !reg_value[0],
              "feed status retains session-change history");
        axi_read(REG_FEED_SESSION_CHANGE, reg_value);
        check(reg_value == 32'd1, "AXI-Lite exposes session-change count");
        recover_feed();
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, recovery_raw_mem);
        expect_no_quote(800, "session recovery rebuild suppresses quotes");
        check(feed_rebuild_ready, "session recovery becomes activation-ready");
        activate_feed();
        check(feed_healthy && !feed_rebuilding,
              "qualified activation completes session recovery");

        send_packet(END_OF_SESSION_RAW_BYTES, end_of_session_raw_mem);
        expect_no_quote(200, "end-of-session packet emits no quote");
        check(!feed_healthy && !feed_rebuilding,
              "MoldUDP64 end-of-session invalidates feed");
        check(feed_end_of_session_count == 32'd1,
              "end-of-session has distinct fault telemetry");
        check(feed_session_change_count == 32'd1 && feed_gap_count == 32'd0,
              "end-of-session does not masquerade as session change or sequence gap");
        check(feed_suppressed_event_count == 32'd3,
              "end-of-session packet carries no suppressible events");
        axi_read(REG_STATUS, reg_value);
        check(reg_value[11] && !reg_value[5],
              "aggregate status identifies end-of-session and unhealthy feed");
        axi_read(REG_FEED_STATUS, reg_value);
        check(reg_value[6] && !reg_value[0],
              "feed status retains end-of-session history");
        axi_read(REG_FEED_END_OF_SESSION, reg_value);
        check(reg_value == 32'd1, "AXI-Lite exposes end-of-session count");
        recover_feed();
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, recovery_raw_mem);
        expect_no_quote(800, "end-of-session recovery suppresses rebuild quotes");
        check(feed_rebuild_ready,
              "end-of-session recovery becomes activation-ready");
        activate_feed();
        check(feed_healthy && !feed_rebuilding,
              "qualified activation completes end-of-session recovery");

        send_packet(MULTI_SYMBOL_RAW_0_BYTES, raw_0_mem);
        expect_no_quote(500, "sequence-gap packet emits no quote");
        check(!feed_healthy, "sequence gap marks feed unhealthy");
        check(feed_gap_count == 32'd1, "sequence gap counted once per packet");
        check(feed_suppressed_event_count == 32'd6,
              "session-change and gap packet events are suppressed");
        axi_read(REG_STATUS, reg_value);
        check(!reg_value[5], "aggregate status reports feed unhealthy");
        axi_read(REG_FEED_STATUS, reg_value);
        check(!reg_value[0] && reg_value[4],
              "feed status reports fault and activation rejection history");
        axi_read(REG_FEED_GAP_COUNT, reg_value);
        check(reg_value == 32'd1, "AXI-Lite exposes sequence-gap count");
        axi_read(REG_FEED_SUPPRESSED, reg_value);
        check(reg_value == 32'd6, "AXI-Lite exposes cumulative suppressed-event count");
        check(book_accepted_event_count == 32'd0,
              "sequence gap clears aggregate book state and counters");
        check(book_quote_update_count == 32'd0,
              "sequence gap clears pending quote state");

        recover_feed();
        check(!feed_healthy && feed_rebuilding,
              "software recovery enters non-tradable rebuild state");
        axi_read(REG_STATUS, reg_value);
        check(!reg_value[5] && reg_value[8],
              "aggregate status reports feed rebuild state");
        axi_read(REG_FEED_STATUS, reg_value);
        check(!reg_value[0] && reg_value[2] && !reg_value[3] && reg_value[4],
              "feed status distinguishes empty rebuild from healthy");
        activate_feed();
        check(!feed_healthy && feed_rebuilding && !feed_rebuild_ready,
              "empty rebuild rejects premature activation");
        check(feed_activation_reject_count == 32'd2,
              "premature activation increments rejection counter");
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, recovery_raw_mem);
        expect_no_quote(800, "rebuild suppresses external quotes");
        check(feed_rebuilding && !feed_healthy,
              "contiguous rebuild packet remains non-tradable");
        check(feed_gap_count == 32'd1,
              "recovery packet establishes a new sequence baseline");
        check(book_quote_update_count == 32'(MULTI_SYMBOL_PACKET_0_QUOTES),
              "rebuild packet repopulates book state internally");
        check(feed_rebuild_ready,
              "applied rebuild traffic qualifies feed activation");
        axi_read(REG_FEED_STATUS, reg_value);
        check(reg_value[4:2] == 3'b111,
              "feed status exposes rejection history and activation readiness");
        axi_read(REG_FEED_ACT_REJECT, reg_value);
        check(reg_value == 32'd2,
              "AXI-Lite exposes activation rejection count");
        activate_feed();
        check(feed_healthy && !feed_rebuilding,
              "software activation makes rebuilt feed tradable");
        axi_read(REG_STATUS, reg_value);
        check(reg_value[5] && !reg_value[8],
              "aggregate status reports activated feed");
        check(feed_gap_count == 32'd1, "recovery does not erase fault history");
        check(feed_suppressed_event_count == 32'd6,
              "rebuild does not count applied events as suppressed");

        axi_write(REG_FEED_TIMEOUT_CFG, 32'd32);
        axi_read(REG_FEED_TIMEOUT_CFG, reg_value);
        check(reg_value == 32'd32, "software configures feed liveness timeout");
        repeat (36) @(negedge clk);
        check(!feed_healthy, "packet inactivity invalidates feed");
        check(feed_timeout_count == 32'd1, "feed timeout counted once");
        check(feed_idle_cycles >= 32'd32,
              $sformatf("idle counter captures timeout interval (observed %0d)",
                        feed_idle_cycles));
        check(feed_gap_count == 32'd1,
              "liveness timeout does not masquerade as sequence gap");
        check(book_accepted_event_count == 32'd0,
              "liveness timeout clears active book state");
        axi_read(REG_FEED_IDLE_CYCLES, reg_value);
        check(reg_value >= 32'd32,
              $sformatf("AXI-Lite exposes feed idle cycles (observed %0d)", reg_value));
        axi_read(REG_FEED_TIMEOUT_CNT, reg_value);
        check(reg_value == 32'd1, "AXI-Lite exposes feed timeout count");
        axi_read(REG_FEED_STATUS, reg_value);
        check(!reg_value[0] && reg_value[1] && !reg_value[2] && reg_value[4],
              "feed status identifies liveness timeout and rejection history");
        axi_read(REG_STATUS, reg_value);
        check(!reg_value[5] && !reg_value[6] && reg_value[7],
              "aggregate status distinguishes timeout from bridge overflow");
        recover_feed();
        check(!feed_healthy && feed_rebuilding,
              "timeout recovery enters rebuild state");
        check(feed_idle_cycles <= 32'd2, "recovery restarts liveness timer");
        activate_feed();
        check(!feed_healthy && feed_rebuilding,
              "timeout recovery cannot activate an empty book");
        axi_write(REG_FEED_TIMEOUT_CFG, 32'd0);
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, recovery_raw_mem);
        expect_no_quote(800, "timeout rebuild suppresses external quotes");
        check(feed_rebuild_ready, "timeout rebuild becomes activation-ready");
        activate_feed();
        check(feed_healthy && !feed_rebuilding,
              "activation rearms feed after timeout");
        axi_read(REG_STATUS, reg_value);
        check(reg_value[5] && !reg_value[6] && reg_value[7] && !reg_value[8],
              "timeout recovery preserves timeout history");

        send_oversize_packet(65);
        repeat (4) @(posedge clk);
        check(!feed_healthy, "CMAC bridge overflow invalidates feed immediately");
        check(cmac_axis_overflow_packet_count == 32'd1,
              "CMAC bridge overflow reason is retained");
        check(cmac_axis_dropped_beat_count == 32'd65,
              "CMAC bridge reports every beat in the lost packet");
        check(cmac_axis_fifo_level == 16'd0,
              "overflow rollback removes the incomplete packet");
        check(feed_gap_count == 32'd1,
              "bridge loss does not masquerade as a decoded sequence gap");
        check(book_accepted_event_count == 32'd0,
              "bridge loss clears all book state immediately");
        axi_read(REG_STATUS, reg_value);
        check(!reg_value[5] && reg_value[6],
              "AXI-Lite identifies unhealthy feed and CMAC overflow");
        recover_feed();
        check(!feed_healthy && feed_rebuilding,
              "overflow recovery enters rebuild state");
        activate_feed();
        check(!feed_healthy && feed_rebuilding,
              "overflow recovery cannot activate an empty book");
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, recovery_raw_mem);
        expect_no_quote(800, "overflow rebuild suppresses external quotes");
        check(feed_rebuild_ready, "overflow rebuild becomes activation-ready");
        activate_feed();
        check(feed_healthy && !feed_rebuilding,
              "activation rearms feed after CMAC overflow");
        axi_read(REG_STATUS, reg_value);
        check(reg_value[5] && reg_value[6] && !reg_value[8],
              "recovery preserves CMAC overflow history");
        axi_read(REG_FEED_ACT_REJECT, reg_value);
        check(reg_value == 32'd4,
              "activation rejection history covers all premature commands");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_100g_multi_strategy_top_tb failed");
    end

endmodule
`default_nettype wire
