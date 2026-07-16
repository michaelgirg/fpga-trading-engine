`default_nettype none
// =============================================================================
// Module: market_parser_100g_cmac_axis_multi_strategy_top
// =============================================================================
// Vendor-IP-free boundary for a source-only 512-bit CMAC RX AXIS stream.
// Complete packets are buffered before entering the guarded multi-symbol
// packet-to-book path so downstream backpressure cannot truncate a frame.
module market_parser_100g_cmac_axis_multi_strategy_top #(
    parameter logic [15:0] FEED_UDP_PORT            = 16'd5000,
    parameter int          NUM_SYMBOLS              = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter int          CMAC_RX_FIFO_DEPTH       = 16,
    parameter int          STRIP_FIFO_DEPTH         = 8,
    parameter int          PACKET_BEATS_MAX         = 16,
    parameter int          DESC_FIFO_DEPTH          = 32,
    parameter int          EXTRACTION_WINDOW_BYTES  = 256,
    parameter int          EVENT_FIFO_DEPTH         = 16,
    parameter int          ORDER_TABLE_DEPTH        = 16,
    parameter logic [31:0] BUILD_ID                 = 32'h4d50_5253
) (
    input  wire logic         clk,
    input  wire logic         rst,
    input  wire logic         feed_recover,

    input  wire logic         rx_axis_tvalid,
    input  wire logic [511:0] rx_axis_tdata,
    input  wire logic [ 63:0] rx_axis_tkeep,
    input  wire logic         rx_axis_tlast,
    input  wire logic         rx_axis_tuser,

    output logic              quote_valid,
    input  wire logic         quote_ready,
    output logic [15:0]       quote_stock_locate,
    output logic [31:0]       quote_bid_price,
    output logic [31:0]       quote_bid_shares,
    output logic [31:0]       quote_ask_price,
    output logic [31:0]       quote_ask_shares,
    output logic [47:0]       quote_timestamp,

    input  wire logic [11:0]  s_axi_awaddr,
    input  wire logic         s_axi_awvalid,
    output logic              s_axi_awready,
    input  wire logic [31:0]  s_axi_wdata,
    input  wire logic [ 3:0]  s_axi_wstrb,
    input  wire logic         s_axi_wvalid,
    output logic              s_axi_wready,
    output logic [ 1:0]       s_axi_bresp,
    output logic              s_axi_bvalid,
    input  wire logic         s_axi_bready,
    input  wire logic [11:0]  s_axi_araddr,
    input  wire logic         s_axi_arvalid,
    output logic              s_axi_arready,
    output logic [31:0]       s_axi_rdata,
    output logic [ 1:0]       s_axi_rresp,
    output logic              s_axi_rvalid,
    input  wire logic         s_axi_rready,

    output logic [31:0]       cmac_axis_accepted_packet_count,
    output logic [31:0]       cmac_axis_overflow_packet_count,
    output logic [31:0]       cmac_axis_dropped_beat_count,
    output logic [15:0]       cmac_axis_fifo_level,
    output logic [15:0]       cmac_axis_fifo_high_watermark,
    output logic [15:0]       cmac_axis_buffered_packet_count,

    output logic [31:0]       cmac_accepted_frame_count,
    output logic [31:0]       cmac_dropped_frame_count,
    output logic [31:0]       cmac_header_error_count,
    output logic [31:0]       cmac_payload_packet_count,
    output logic [15:0]       cmac_payload_fifo_level,

    output logic [31:0]       book_accepted_event_count,
    output logic [31:0]       book_applied_event_count,
    output logic [31:0]       book_ignored_event_count,
    output logic [31:0]       book_untracked_event_count,
    output logic [31:0]       book_table_overflow_count,
    output logic [31:0]       book_quote_update_count,

    output logic              feed_healthy,
    output logic [31:0]       feed_gap_count,
    output logic [31:0]       feed_suppressed_event_count
);
    logic         parser_rx_tvalid;
    logic         parser_rx_tready;
    logic [511:0] parser_rx_tdata;
    logic [ 63:0] parser_rx_tkeep;
    logic         parser_rx_tlast;
    logic         parser_rx_tuser_bad_frame;

    market_parser_cmac_axis_rx_bridge #(
        .DATA_WIDTH(512),
        .KEEP_WIDTH(64),
        .FIFO_DEPTH(CMAC_RX_FIFO_DEPTH)
    ) cmac_rx_bridge_i (
        .clk                  (clk),
        .rst                  (rst),
        .rx_axis_tvalid       (rx_axis_tvalid),
        .rx_axis_tdata        (rx_axis_tdata),
        .rx_axis_tkeep        (rx_axis_tkeep),
        .rx_axis_tlast        (rx_axis_tlast),
        .rx_axis_tuser        (rx_axis_tuser),
        .m_axis_tvalid        (parser_rx_tvalid),
        .m_axis_tready        (parser_rx_tready),
        .m_axis_tdata         (parser_rx_tdata),
        .m_axis_tkeep         (parser_rx_tkeep),
        .m_axis_tlast         (parser_rx_tlast),
        .m_axis_tuser_bad_frame(parser_rx_tuser_bad_frame),
        .accepted_packet_count(cmac_axis_accepted_packet_count),
        .overflow_packet_count(cmac_axis_overflow_packet_count),
        .dropped_beat_count   (cmac_axis_dropped_beat_count),
        .fifo_level           (cmac_axis_fifo_level),
        .fifo_high_watermark  (cmac_axis_fifo_high_watermark),
        .buffered_packet_count(cmac_axis_buffered_packet_count)
    );

    market_parser_100g_multi_strategy_top #(
        .FEED_UDP_PORT          (FEED_UDP_PORT),
        .NUM_SYMBOLS            (NUM_SYMBOLS),
        .SYMBOL_LOCATES         (SYMBOL_LOCATES),
        .STRIP_FIFO_DEPTH       (STRIP_FIFO_DEPTH),
        .PACKET_BEATS_MAX       (PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH        (DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES(EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH       (EVENT_FIFO_DEPTH),
        .ORDER_TABLE_DEPTH      (ORDER_TABLE_DEPTH),
        .BUILD_ID               (BUILD_ID)
    ) multi_strategy_top_i (
        .clk                            (clk),
        .rst                            (rst),
        .feed_recover                   (feed_recover),
        .s_axis_cmac_rx_tvalid          (parser_rx_tvalid),
        .s_axis_cmac_rx_tready          (parser_rx_tready),
        .s_axis_cmac_rx_tdata           (parser_rx_tdata),
        .s_axis_cmac_rx_tkeep           (parser_rx_tkeep),
        .s_axis_cmac_rx_tlast           (parser_rx_tlast),
        .s_axis_cmac_rx_tuser_bad_frame (parser_rx_tuser_bad_frame),
        .cmac_axis_accepted_packet_count_status(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count_status(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count_status(cmac_axis_dropped_beat_count),
        .cmac_axis_fifo_level_status    (cmac_axis_fifo_level),
        .cmac_axis_fifo_high_watermark_status(cmac_axis_fifo_high_watermark),
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
        .book_untracked_event_count     (book_untracked_event_count),
        .book_table_overflow_count      (book_table_overflow_count),
        .book_quote_update_count        (book_quote_update_count),
        .feed_healthy                   (feed_healthy),
        .feed_gap_count                 (feed_gap_count),
        .feed_suppressed_event_count    (feed_suppressed_event_count)
    );

endmodule
`default_nettype wire
