`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_100g_multi_strategy_top
// =============================================================================
// Multi-symbol strategy integration path:
//   Ethernet/IPv4/UDP/MoldUDP64/ITCH -> normalized events -> book bank.
module market_parser_100g_multi_strategy_top #(
    parameter logic [15:0] FEED_UDP_PORT            = 16'd5000,
    parameter int          NUM_SYMBOLS              = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter int          STRIP_FIFO_DEPTH         = 8,
    parameter int          PACKET_BEATS_MAX         = 16,
    parameter int          DESC_FIFO_DEPTH          = 32,
    parameter int          EXTRACTION_WINDOW_BYTES  = 256,
    parameter int          EVENT_FIFO_DEPTH         = 16,
    parameter int          ORDER_TABLE_DEPTH        = 16,
    parameter logic [31:0] BUILD_ID                 = 32'h4d50_5253,
    parameter logic [31:0] FEED_TIMEOUT_CYCLES_DEFAULT = 32'd322_400_000
) (
    input  wire logic         clk,
    input  wire logic         rst,
    input  wire logic         feed_recover,
    input  wire logic         feed_activate,
    input  wire logic         feed_fault,

    input  wire logic         s_axis_cmac_rx_tvalid,
    output logic              s_axis_cmac_rx_tready,
    input  wire logic [511:0] s_axis_cmac_rx_tdata,
    input  wire logic [ 63:0] s_axis_cmac_rx_tkeep,
    input  wire logic         s_axis_cmac_rx_tlast,
    input  wire logic         s_axis_cmac_rx_tuser_bad_frame,

    input  wire logic [31:0]  cmac_axis_accepted_packet_count_status,
    input  wire logic [31:0]  cmac_axis_overflow_packet_count_status,
    input  wire logic [31:0]  cmac_axis_dropped_beat_count_status,
    input  wire logic [15:0]  cmac_axis_fifo_level_status,
    input  wire logic [15:0]  cmac_axis_fifo_high_watermark_status,

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
    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;
    logic [ 63:0] event_new_order_ref;
    logic [ 31:0] event_keep;
    logic         event_last;
    logic         session_change_pulse;
    logic         end_of_session_pulse;
    logic         book_event_valid;
    logic         book_event_ready;
    logic         book_quote_valid;
    logic         book_quote_ready;
    logic         book_rst;
    logic         book_gap_reset_r;
    logic         gap_event_i;
    logic         event_fire_i;
    logic         feed_healthy_r;
    logic         feed_rebuilding_r;
    logic [31:0]  feed_gap_count_r;
    logic [31:0]  feed_suppressed_event_count_r;
    logic         feed_recover_sw;
    logic         feed_activate_sw;
    logic         feed_recover_i;
    logic         feed_activate_i;
    logic         feed_activate_effective_i;
    logic         feed_operational_i;
    logic         feed_control_transition_i;
    logic         feed_fault_i;
    logic         watchdog_timeout_due_i;
    logic         watchdog_timeout_r;
    logic [31:0]  feed_idle_cycles_r;
    logic [31:0]  feed_timeout_count_r;
    logic         rebuild_applied_event_seen_r;
    logic [31:0]  book_applied_event_count_prev_r;
    logic [31:0]  feed_activation_reject_count_r;
    logic [31:0]  feed_session_change_count_r;
    logic [31:0]  feed_end_of_session_count_r;
    logic [31:0]  feed_timeout_cycles_config;
    logic [31:0]  feed_timeout_cycles_prev_r;
    logic [31:0]  accepted_packet_count_seen_r;

    assign feed_recover_i = feed_recover || feed_recover_sw;
    assign feed_activate_i = feed_activate || feed_activate_sw;
    assign feed_operational_i = feed_healthy_r || feed_rebuilding_r;
    assign feed_activate_effective_i = feed_activate_i && !feed_recover_i &&
                                       feed_rebuilding_r &&
                                       rebuild_applied_event_seen_r;
    assign feed_control_transition_i = feed_recover_i || feed_activate_effective_i;
    assign watchdog_timeout_due_i =
        feed_operational_i && !feed_control_transition_i && !feed_fault_i &&
        (feed_timeout_cycles_config == feed_timeout_cycles_prev_r) &&
        (feed_timeout_cycles_config != 32'd0) &&
        (cmac_axis_accepted_packet_count_status == accepted_packet_count_seen_r) &&
        (feed_idle_cycles_r + 1'b1 >= feed_timeout_cycles_config);
    assign feed_fault_i = feed_fault || session_change_pulse ||
                          end_of_session_pulse || watchdog_timeout_r;

    assign gap_event_i = event_valid &&
                         ((event_data[239:232] & FLAG_GAP) != 8'h00);
    assign event_ready = feed_control_transition_i ? 1'b0 :
                         ((!feed_operational_i || gap_event_i || feed_fault_i) ?
                          1'b1 : book_event_ready);
    assign event_fire_i = event_valid && event_ready;
    assign book_event_valid = event_valid && feed_operational_i &&
                              !gap_event_i && !feed_fault_i &&
                              !feed_control_transition_i;
    assign book_rst = rst || feed_recover_i ||
                      feed_fault_i || book_gap_reset_r;

    assign quote_valid = feed_healthy_r && !gap_event_i &&
                         !feed_fault_i && !feed_control_transition_i &&
                         book_quote_valid;
    assign book_quote_ready = feed_rebuilding_r ? 1'b1 : quote_ready;
    assign feed_healthy = feed_healthy_r;
    assign feed_rebuilding = feed_rebuilding_r;
    assign feed_rebuild_ready = feed_rebuilding_r && rebuild_applied_event_seen_r;
    assign feed_gap_count = feed_gap_count_r;
    assign feed_suppressed_event_count = feed_suppressed_event_count_r;
    assign feed_idle_cycles = feed_idle_cycles_r;
    assign feed_timeout_count = feed_timeout_count_r;
    assign feed_activation_reject_count = feed_activation_reject_count_r;
    assign feed_session_change_count = feed_session_change_count_r;
    assign feed_end_of_session_count = feed_end_of_session_count_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            rebuild_applied_event_seen_r   <= 1'b0;
            book_applied_event_count_prev_r <= '0;
            feed_activation_reject_count_r <= '0;
            feed_session_change_count_r    <= '0;
            feed_end_of_session_count_r    <= '0;
        end else begin
            if (feed_fault_i || feed_recover_i || feed_activate_effective_i ||
                (event_fire_i && gap_event_i && feed_operational_i)) begin
                rebuild_applied_event_seen_r    <= 1'b0;
                book_applied_event_count_prev_r <= '0;
            end else begin
                if (feed_rebuilding_r &&
                    (book_applied_event_count != book_applied_event_count_prev_r)) begin
                    rebuild_applied_event_seen_r <= 1'b1;
                end
                book_applied_event_count_prev_r <= book_applied_event_count;
            end

            if (feed_activate_i && !feed_activate_effective_i) begin
                feed_activation_reject_count_r <=
                    feed_activation_reject_count_r + 1'b1;
            end
            if (session_change_pulse) begin
                feed_session_change_count_r <= feed_session_change_count_r + 1'b1;
            end
            if (end_of_session_pulse) begin
                feed_end_of_session_count_r <= feed_end_of_session_count_r + 1'b1;
            end
        end
    end

    // Isolate decoded event data from the high-fanout book reset network.
    always_ff @(posedge clk) begin
        if (rst) begin
            book_gap_reset_r <= 1'b0;
        end else begin
            book_gap_reset_r <= event_fire_i && gap_event_i &&
                                feed_operational_i;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            feed_healthy_r                <= 1'b1;
            feed_rebuilding_r             <= 1'b0;
            feed_gap_count_r              <= '0;
            feed_suppressed_event_count_r <= '0;
        end else if (feed_fault_i) begin
            feed_healthy_r    <= 1'b0;
            feed_rebuilding_r <= 1'b0;
            if (event_fire_i) begin
                feed_suppressed_event_count_r <= feed_suppressed_event_count_r + 1'b1;
            end
        end else if (feed_recover_i) begin
            feed_healthy_r    <= 1'b0;
            feed_rebuilding_r <= 1'b1;
        end else if (feed_activate_effective_i) begin
            feed_healthy_r    <= 1'b1;
            feed_rebuilding_r <= 1'b0;
        end else if (event_fire_i) begin
            if (gap_event_i && feed_operational_i) begin
                feed_healthy_r    <= 1'b0;
                feed_rebuilding_r <= 1'b0;
                feed_gap_count_r  <= feed_gap_count_r + 1'b1;
            end
            if (!feed_operational_i || gap_event_i) begin
                feed_suppressed_event_count_r <= feed_suppressed_event_count_r + 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            accepted_packet_count_seen_r <= cmac_axis_accepted_packet_count_status;
            feed_timeout_cycles_prev_r   <= FEED_TIMEOUT_CYCLES_DEFAULT;
            feed_idle_cycles_r           <= '0;
            feed_timeout_count_r         <= '0;
            watchdog_timeout_r           <= 1'b0;
        end else begin
            accepted_packet_count_seen_r <= cmac_axis_accepted_packet_count_status;
            feed_timeout_cycles_prev_r   <= feed_timeout_cycles_config;
            watchdog_timeout_r           <= watchdog_timeout_due_i;

            if (feed_control_transition_i ||
                (feed_timeout_cycles_config != feed_timeout_cycles_prev_r)) begin
                feed_idle_cycles_r <= '0;
            end else if (!feed_operational_i || feed_fault_i) begin
                feed_idle_cycles_r <= feed_idle_cycles_r;
            end else if (cmac_axis_accepted_packet_count_status !=
                         accepted_packet_count_seen_r) begin
                feed_idle_cycles_r <= '0;
            end else if (feed_idle_cycles_r != 32'hffff_ffff) begin
                feed_idle_cycles_r <= feed_idle_cycles_r + 1'b1;
            end

            if (watchdog_timeout_due_i) begin
                feed_timeout_count_r <= feed_timeout_count_r + 1'b1;
            end
        end
    end

    market_parser_100g_cmac_system #(
        .FEED_UDP_PORT           (FEED_UDP_PORT),
        .STRIP_FIFO_DEPTH        (STRIP_FIFO_DEPTH),
        .PACKET_BEATS_MAX        (PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH         (DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES (EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH        (EVENT_FIFO_DEPTH),
        .BUILD_ID                (BUILD_ID),
        .FEED_TIMEOUT_CYCLES_DEFAULT(FEED_TIMEOUT_CYCLES_DEFAULT)
    ) ingress_parser_i (
        .clk                            (clk),
        .rst                            (rst),
        .sequence_rearm                 (feed_recover_i),
        .s_axis_cmac_rx_tvalid          (s_axis_cmac_rx_tvalid),
        .s_axis_cmac_rx_tready          (s_axis_cmac_rx_tready),
        .s_axis_cmac_rx_tdata           (s_axis_cmac_rx_tdata),
        .s_axis_cmac_rx_tkeep           (s_axis_cmac_rx_tkeep),
        .s_axis_cmac_rx_tlast           (s_axis_cmac_rx_tlast),
        .s_axis_cmac_rx_tuser_bad_frame (s_axis_cmac_rx_tuser_bad_frame),
        .event_valid                    (event_valid),
        .event_ready                    (event_ready),
        .event_data                     (event_data),
        .event_new_order_ref            (event_new_order_ref),
        .event_keep                     (event_keep),
        .event_last                     (event_last),
        .session_change_pulse           (session_change_pulse),
        .end_of_session_pulse           (end_of_session_pulse),
        .feed_healthy_status            (feed_healthy_r),
        .feed_rebuilding_status         (feed_rebuilding_r),
        .feed_rebuild_ready_status      (feed_rebuild_ready),
        .feed_gap_count_status          (feed_gap_count_r),
        .feed_suppressed_event_count_status(feed_suppressed_event_count_r),
        .feed_idle_cycles_status        (feed_idle_cycles_r),
        .feed_timeout_count_status      (feed_timeout_count_r),
        .feed_activation_reject_count_status(feed_activation_reject_count_r),
        .feed_session_change_count_status(feed_session_change_count_r),
        .feed_end_of_session_count_status(feed_end_of_session_count_r),
        .feed_recover_pulse             (feed_recover_sw),
        .feed_activate_pulse            (feed_activate_sw),
        .feed_timeout_cycles_config     (feed_timeout_cycles_config),
        .cmac_axis_accepted_packet_count_status(cmac_axis_accepted_packet_count_status),
        .cmac_axis_overflow_packet_count_status(cmac_axis_overflow_packet_count_status),
        .cmac_axis_dropped_beat_count_status(cmac_axis_dropped_beat_count_status),
        .cmac_axis_fifo_level_status    (cmac_axis_fifo_level_status),
        .cmac_axis_fifo_high_watermark_status(cmac_axis_fifo_high_watermark_status),
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
        .cmac_payload_fifo_level        (cmac_payload_fifo_level)
    );

    market_parser_multi_symbol_top_of_book #(
        .NUM_SYMBOLS      (NUM_SYMBOLS),
        .ORDER_TABLE_DEPTH(ORDER_TABLE_DEPTH),
        .SYMBOL_LOCATES   (SYMBOL_LOCATES)
    ) book_bank_i (
        .clk                  (clk),
        .rst                  (book_rst),
        .event_valid          (book_event_valid),
        .event_ready          (book_event_ready),
        .event_data           (event_data),
        .event_new_order_ref  (event_new_order_ref),
        .event_keep           (event_keep),
        .event_last           (event_last),
        .quote_valid          (book_quote_valid),
        .quote_ready          (book_quote_ready),
        .quote_stock_locate   (quote_stock_locate),
        .quote_bid_price      (quote_bid_price),
        .quote_bid_shares     (quote_bid_shares),
        .quote_ask_price      (quote_ask_price),
        .quote_ask_shares     (quote_ask_shares),
        .quote_timestamp      (quote_timestamp),
        .accepted_event_count (book_accepted_event_count),
        .applied_event_count  (book_applied_event_count),
        .ignored_event_count  (book_ignored_event_count),
        .untracked_event_count(book_untracked_event_count),
        .table_overflow_count (book_table_overflow_count),
        .quote_update_count   (book_quote_update_count)
    );

endmodule
`default_nettype wire
