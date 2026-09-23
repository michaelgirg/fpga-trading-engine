`default_nettype none
// =============================================================================
// Module: market_parser_100g_ab_multi_strategy_top
// =============================================================================
// Dual-feed 100G boundary. Independent no-tready CMAC packet buffers feed a
// packet-atomic MoldUDP64 A/B merger before the existing multi-symbol parser,
// feed guard, and top-of-book engine.
module market_parser_100g_ab_multi_strategy_top #(
    parameter logic [15:0] FEED_UDP_PORT = 16'd5000,
    parameter int NUM_SYMBOLS = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter int CMAC_RX_FIFO_DEPTH = 64,
    parameter int AB_MAX_SKEW_CYCLES = 32,
    parameter logic [79:0] MERGED_SESSION_ID = 80'h4d455247454420202020,
    parameter int STRIP_FIFO_DEPTH = 8,
    parameter int PACKET_BEATS_MAX = 32,
    parameter int DESC_FIFO_DEPTH = 32,
    parameter int EXTRACTION_WINDOW_BYTES = 256,
    parameter int EVENT_FIFO_DEPTH = 16,
    parameter int ORDER_TABLE_DEPTH = 16,
    parameter logic [31:0] BUILD_ID = 32'h4d50_5253,
    parameter logic [31:0] FEED_TIMEOUT_CYCLES_DEFAULT = 32'd322_400_000
) (
    input  wire logic         clk,
    input  wire logic         rst,
    input  wire logic         feed_recover,
    input  wire logic         feed_activate,

    input  wire logic         rx_axis_a_tvalid,
    input  wire logic [511:0] rx_axis_a_tdata,
    input  wire logic [ 63:0] rx_axis_a_tkeep,
    input  wire logic         rx_axis_a_tlast,
    input  wire logic         rx_axis_a_tuser,
    input  wire logic         rx_axis_b_tvalid,
    input  wire logic [511:0] rx_axis_b_tdata,
    input  wire logic [ 63:0] rx_axis_b_tkeep,
    input  wire logic         rx_axis_b_tlast,
    input  wire logic         rx_axis_b_tuser,

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

    output logic [31:0]       cmac_a_accepted_packet_count,
    output logic [31:0]       cmac_a_overflow_packet_count,
    output logic [31:0]       cmac_a_dropped_beat_count,
    output logic [15:0]       cmac_a_fifo_level,
    output logic [15:0]       cmac_a_fifo_high_watermark,
    output logic [15:0]       cmac_a_buffered_packet_count,
    output logic [31:0]       cmac_b_accepted_packet_count,
    output logic [31:0]       cmac_b_overflow_packet_count,
    output logic [31:0]       cmac_b_dropped_beat_count,
    output logic [15:0]       cmac_b_fifo_level,
    output logic [15:0]       cmac_b_fifo_high_watermark,
    output logic [15:0]       cmac_b_buffered_packet_count,

    output logic              ab_sequence_initialized,
    output logic [63:0]       ab_expected_sequence,
    output logic              ab_active_source,
    output logic              ab_merge_fault,
    output logic              ab_gap_event,
    output logic [31:0]       ab_selected_a_packet_count,
    output logic [31:0]       ab_selected_b_packet_count,
    output logic [31:0]       ab_duplicate_a_packet_count,
    output logic [31:0]       ab_duplicate_b_packet_count,
    output logic [31:0]       ab_malformed_a_packet_count,
    output logic [31:0]       ab_malformed_b_packet_count,
    output logic [31:0]       ab_failover_count,
    output logic [31:0]       ab_gap_count,
    output logic [31:0]       ab_divergence_count,
    output logic [31:0]       ab_session_change_a_count,
    output logic [31:0]       ab_session_change_b_count,

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
    output logic              feed_rebuilding,
    output logic              feed_rebuild_ready,
    output logic [31:0]       feed_gap_count,
    output logic [31:0]       feed_suppressed_event_count,
    output logic [31:0]       feed_idle_cycles,
    output logic [31:0]       feed_timeout_count,
    output logic [31:0]       feed_activation_reject_count,
    output logic [31:0]       feed_session_change_count,
    output logic [31:0]       feed_end_of_session_count
);
    logic a_bridge_tvalid;
    logic a_bridge_tready;
    logic [511:0] a_bridge_tdata;
    logic [63:0] a_bridge_tkeep;
    logic a_bridge_tlast;
    logic a_bridge_tuser_bad_frame;
    logic b_bridge_tvalid;
    logic b_bridge_tready;
    logic [511:0] b_bridge_tdata;
    logic [63:0] b_bridge_tkeep;
    logic b_bridge_tlast;
    logic b_bridge_tuser_bad_frame;
    logic a_tvalid;
    logic a_tready;
    logic [511:0] a_tdata;
    logic [63:0] a_tkeep;
    logic a_tlast;
    logic a_tuser_bad_frame;
    logic b_tvalid;
    logic b_tready;
    logic [511:0] b_tdata;
    logic [63:0] b_tkeep;
    logic b_tlast;
    logic b_tuser_bad_frame;
    logic merged_tvalid;
    logic merged_tready;
    logic [511:0] merged_tdata;
    logic [63:0] merged_tkeep;
    logic merged_tlast;
    logic merged_tuser_bad_frame;
    logic overflow_a_event;
    logic overflow_b_event;
    logic [31:0] selected_packet_count_status_r;
    logic [31:0] overflow_packet_count_status_r;
    logic [31:0] dropped_beat_count_status_r;
    logic [15:0] fifo_level_status_r;
    logic [15:0] fifo_high_watermark_status_r;

    function automatic logic [15:0] add_saturating_16(
        input logic [15:0] lhs,
        input logic [15:0] rhs
    );
        logic [16:0] sum;
        sum = {1'b0, lhs} + {1'b0, rhs};
        add_saturating_16 = sum[16] ? 16'hffff : sum[15:0];
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            selected_packet_count_status_r <= '0;
            overflow_packet_count_status_r <= '0;
            dropped_beat_count_status_r <= '0;
            fifo_level_status_r <= '0;
            fifo_high_watermark_status_r <= '0;
        end else begin
            selected_packet_count_status_r <=
                ab_selected_a_packet_count + ab_selected_b_packet_count;
            overflow_packet_count_status_r <=
                cmac_a_overflow_packet_count + cmac_b_overflow_packet_count;
            dropped_beat_count_status_r <=
                cmac_a_dropped_beat_count + cmac_b_dropped_beat_count;
            fifo_level_status_r <= add_saturating_16(
                cmac_a_fifo_level, cmac_b_fifo_level);
            fifo_high_watermark_status_r <= add_saturating_16(
                cmac_a_fifo_high_watermark, cmac_b_fifo_high_watermark);
        end
    end

    market_parser_cmac_axis_rx_bridge #(
        .DATA_WIDTH(512), .KEEP_WIDTH(64), .FIFO_DEPTH(CMAC_RX_FIFO_DEPTH)
    ) cmac_a_bridge_i (
        .clk(clk), .rst(rst), .rx_axis_tvalid(rx_axis_a_tvalid),
        .rx_axis_tdata(rx_axis_a_tdata), .rx_axis_tkeep(rx_axis_a_tkeep),
        .rx_axis_tlast(rx_axis_a_tlast), .rx_axis_tuser(rx_axis_a_tuser),
        .m_axis_tvalid(a_bridge_tvalid), .m_axis_tready(a_bridge_tready),
        .m_axis_tdata(a_bridge_tdata), .m_axis_tkeep(a_bridge_tkeep),
        .m_axis_tlast(a_bridge_tlast),
        .m_axis_tuser_bad_frame(a_bridge_tuser_bad_frame),
        .accepted_packet_count(cmac_a_accepted_packet_count),
        .overflow_packet_count(cmac_a_overflow_packet_count),
        .dropped_beat_count(cmac_a_dropped_beat_count),
        .fifo_level(cmac_a_fifo_level),
        .fifo_high_watermark(cmac_a_fifo_high_watermark),
        .buffered_packet_count(cmac_a_buffered_packet_count),
        .overflow_event(overflow_a_event)
    );

    market_parser_cmac_axis_rx_bridge #(
        .DATA_WIDTH(512), .KEEP_WIDTH(64), .FIFO_DEPTH(CMAC_RX_FIFO_DEPTH)
    ) cmac_b_bridge_i (
        .clk(clk), .rst(rst), .rx_axis_tvalid(rx_axis_b_tvalid),
        .rx_axis_tdata(rx_axis_b_tdata), .rx_axis_tkeep(rx_axis_b_tkeep),
        .rx_axis_tlast(rx_axis_b_tlast), .rx_axis_tuser(rx_axis_b_tuser),
        .m_axis_tvalid(b_bridge_tvalid), .m_axis_tready(b_bridge_tready),
        .m_axis_tdata(b_bridge_tdata), .m_axis_tkeep(b_bridge_tkeep),
        .m_axis_tlast(b_bridge_tlast),
        .m_axis_tuser_bad_frame(b_bridge_tuser_bad_frame),
        .accepted_packet_count(cmac_b_accepted_packet_count),
        .overflow_packet_count(cmac_b_overflow_packet_count),
        .dropped_beat_count(cmac_b_dropped_beat_count),
        .fifo_level(cmac_b_fifo_level),
        .fifo_high_watermark(cmac_b_fifo_high_watermark),
        .buffered_packet_count(cmac_b_buffered_packet_count),
        .overflow_event(overflow_b_event)
    );

    // Break the BRAM clock-to-output path before sequence classification. The
    // slices remain one-beat-per-cycle and each bridge still retains complete
    // packets while the arbiter holds its head beat.
    market_parser_axis_register_slice #(
        .DATA_WIDTH(512), .KEEP_WIDTH(64)
    ) cmac_a_head_slice_i (
        .clk(clk), .rst(rst),
        .s_axis_tvalid(a_bridge_tvalid), .s_axis_tready(a_bridge_tready),
        .s_axis_tdata(a_bridge_tdata), .s_axis_tkeep(a_bridge_tkeep),
        .s_axis_tlast(a_bridge_tlast),
        .s_axis_tuser_bad_frame(a_bridge_tuser_bad_frame),
        .m_axis_tvalid(a_tvalid), .m_axis_tready(a_tready),
        .m_axis_tdata(a_tdata), .m_axis_tkeep(a_tkeep),
        .m_axis_tlast(a_tlast), .m_axis_tuser_bad_frame(a_tuser_bad_frame)
    );

    market_parser_axis_register_slice #(
        .DATA_WIDTH(512), .KEEP_WIDTH(64)
    ) cmac_b_head_slice_i (
        .clk(clk), .rst(rst),
        .s_axis_tvalid(b_bridge_tvalid), .s_axis_tready(b_bridge_tready),
        .s_axis_tdata(b_bridge_tdata), .s_axis_tkeep(b_bridge_tkeep),
        .s_axis_tlast(b_bridge_tlast),
        .s_axis_tuser_bad_frame(b_bridge_tuser_bad_frame),
        .m_axis_tvalid(b_tvalid), .m_axis_tready(b_tready),
        .m_axis_tdata(b_tdata), .m_axis_tkeep(b_tkeep),
        .m_axis_tlast(b_tlast), .m_axis_tuser_bad_frame(b_tuser_bad_frame)
    );

    market_parser_moldudp64_ab_arbiter #(
        .HEADER_BYTE_OFFSET(42),
        .MAX_SKEW_CYCLES(AB_MAX_SKEW_CYCLES),
        .NORMALIZE_SESSION(1'b1),
        .MERGED_SESSION_ID(MERGED_SESSION_ID)
    ) ab_arbiter_i (
        .clk(clk), .rst(rst), .rearm(feed_recover),
        .s_axis_a_tvalid(a_tvalid), .s_axis_a_tready(a_tready),
        .s_axis_a_tdata(a_tdata), .s_axis_a_tkeep(a_tkeep),
        .s_axis_a_tlast(a_tlast),
        .s_axis_a_tuser_bad_frame(a_tuser_bad_frame),
        .s_axis_b_tvalid(b_tvalid), .s_axis_b_tready(b_tready),
        .s_axis_b_tdata(b_tdata), .s_axis_b_tkeep(b_tkeep),
        .s_axis_b_tlast(b_tlast),
        .s_axis_b_tuser_bad_frame(b_tuser_bad_frame),
        .m_axis_tvalid(merged_tvalid), .m_axis_tready(merged_tready),
        .m_axis_tdata(merged_tdata), .m_axis_tkeep(merged_tkeep),
        .m_axis_tlast(merged_tlast),
        .m_axis_tuser_bad_frame(merged_tuser_bad_frame),
        .sequence_initialized(ab_sequence_initialized),
        .expected_sequence(ab_expected_sequence),
        .active_source(ab_active_source), .merge_fault(ab_merge_fault),
        .gap_event(ab_gap_event),
        .selected_a_packet_count(ab_selected_a_packet_count),
        .selected_b_packet_count(ab_selected_b_packet_count),
        .duplicate_a_packet_count(ab_duplicate_a_packet_count),
        .duplicate_b_packet_count(ab_duplicate_b_packet_count),
        .malformed_a_packet_count(ab_malformed_a_packet_count),
        .malformed_b_packet_count(ab_malformed_b_packet_count),
        .failover_count(ab_failover_count), .gap_count(ab_gap_count),
        .divergence_count(ab_divergence_count),
        .session_change_a_count(ab_session_change_a_count),
        .session_change_b_count(ab_session_change_b_count)
    );

    market_parser_100g_multi_strategy_top #(
        .FEED_UDP_PORT(FEED_UDP_PORT), .NUM_SYMBOLS(NUM_SYMBOLS),
        .SYMBOL_LOCATES(SYMBOL_LOCATES), .STRIP_FIFO_DEPTH(STRIP_FIFO_DEPTH),
        .PACKET_BEATS_MAX(PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH(DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES(EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH(EVENT_FIFO_DEPTH),
        .ORDER_TABLE_DEPTH(ORDER_TABLE_DEPTH), .BUILD_ID(BUILD_ID),
        .FEED_TIMEOUT_CYCLES_DEFAULT(FEED_TIMEOUT_CYCLES_DEFAULT)
    ) multi_strategy_top_i (
        .clk(clk), .rst(rst), .feed_recover(feed_recover),
        .feed_activate(feed_activate),
        .feed_fault(overflow_a_event || overflow_b_event || ab_merge_fault),
        .s_axis_cmac_rx_tvalid(merged_tvalid),
        .s_axis_cmac_rx_tready(merged_tready),
        .s_axis_cmac_rx_tdata(merged_tdata),
        .s_axis_cmac_rx_tkeep(merged_tkeep),
        .s_axis_cmac_rx_tlast(merged_tlast),
        .s_axis_cmac_rx_tuser_bad_frame(merged_tuser_bad_frame),
        .cmac_axis_accepted_packet_count_status(selected_packet_count_status_r),
        .cmac_axis_overflow_packet_count_status(overflow_packet_count_status_r),
        .cmac_axis_dropped_beat_count_status(dropped_beat_count_status_r),
        .cmac_axis_fifo_level_status(fifo_level_status_r),
        .cmac_axis_fifo_high_watermark_status(fifo_high_watermark_status_r),
        .quote_valid(quote_valid), .quote_ready(quote_ready),
        .quote_stock_locate(quote_stock_locate),
        .quote_bid_price(quote_bid_price), .quote_bid_shares(quote_bid_shares),
        .quote_ask_price(quote_ask_price), .quote_ask_shares(quote_ask_shares),
        .quote_timestamp(quote_timestamp), .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .cmac_accepted_frame_count(cmac_accepted_frame_count),
        .cmac_dropped_frame_count(cmac_dropped_frame_count),
        .cmac_header_error_count(cmac_header_error_count),
        .cmac_payload_packet_count(cmac_payload_packet_count),
        .cmac_payload_fifo_level(cmac_payload_fifo_level),
        .book_accepted_event_count(book_accepted_event_count),
        .book_applied_event_count(book_applied_event_count),
        .book_ignored_event_count(book_ignored_event_count),
        .book_untracked_event_count(book_untracked_event_count),
        .book_table_overflow_count(book_table_overflow_count),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy), .feed_rebuilding(feed_rebuilding),
        .feed_rebuild_ready(feed_rebuild_ready), .feed_gap_count(feed_gap_count),
        .feed_suppressed_event_count(feed_suppressed_event_count),
        .feed_idle_cycles(feed_idle_cycles),
        .feed_timeout_count(feed_timeout_count),
        .feed_activation_reject_count(feed_activation_reject_count),
        .feed_session_change_count(feed_session_change_count),
        .feed_end_of_session_count(feed_end_of_session_count)
    );
endmodule
`default_nettype wire
