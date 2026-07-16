`default_nettype none
// =============================================================================
// Module: market_parser_100g_cmac_system
// =============================================================================
// CMAC-facing system shell:
//   raw Ethernet/IPv4/UDP 512-bit RX stream
//     -> fixed UDP payload stripper
//     -> existing 512-bit parser system with event FIFO and AXI-Lite control.
module market_parser_100g_cmac_system #(
    parameter logic [15:0] FEED_UDP_PORT          = 16'd5000,
    parameter int          STRIP_FIFO_DEPTH       = 8,
    parameter int          PACKET_BEATS_MAX       = 16,
    parameter int          DESC_FIFO_DEPTH        = 32,
    parameter int          EXTRACTION_WINDOW_BYTES = 256,
    parameter int          EVENT_FIFO_DEPTH       = 16,
    parameter logic [31:0] BUILD_ID               = 32'h4d50_5253
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         s_axis_cmac_rx_tvalid,
    output logic              s_axis_cmac_rx_tready,
    input  wire logic [511:0] s_axis_cmac_rx_tdata,
    input  wire logic [ 63:0] s_axis_cmac_rx_tkeep,
    input  wire logic         s_axis_cmac_rx_tlast,
    input  wire logic         s_axis_cmac_rx_tuser_bad_frame,

    output logic              event_valid,
    input  wire logic         event_ready,
    output logic [255:0]      event_data,
    output logic [ 63:0]      event_new_order_ref,
    output logic [ 31:0]      event_keep,
    output logic              event_last,

    input  wire logic         feed_healthy_status,
    input  wire logic [31:0]  feed_gap_count_status,
    input  wire logic [31:0]  feed_suppressed_event_count_status,
    output logic              feed_recover_pulse,

    input  wire logic [31:0]  cmac_axis_accepted_packet_count_status,
    input  wire logic [31:0]  cmac_axis_overflow_packet_count_status,
    input  wire logic [31:0]  cmac_axis_dropped_beat_count_status,
    input  wire logic [15:0]  cmac_axis_fifo_level_status,
    input  wire logic [15:0]  cmac_axis_fifo_high_watermark_status,

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
    output logic [15:0]       cmac_payload_fifo_level
);
    logic         strip_rx_tvalid;
    logic         strip_rx_tready;
    logic [511:0] strip_rx_tdata;
    logic [ 63:0] strip_rx_tkeep;
    logic         strip_rx_tlast;
    logic         strip_rx_tuser_bad_frame;
    logic         payload_tvalid;
    logic         payload_tready;
    logic [511:0] payload_tdata;
    logic [ 63:0] payload_tkeep;
    logic         payload_tlast;
    logic         payload_tuser_bad_frame;
    logic         parser_payload_tvalid;
    logic         parser_payload_tready;
    logic [511:0] parser_payload_tdata;
    logic [ 63:0] parser_payload_tkeep;
    logic         parser_payload_tlast;
    logic         parser_payload_tuser_bad_frame;

    market_parser_axis_register_slice #(
        .DATA_WIDTH(512),
        .KEEP_WIDTH(64)
    ) cmac_rx_slice_i (
        .clk                   (clk),
        .rst                   (rst),
        .s_axis_tvalid         (s_axis_cmac_rx_tvalid),
        .s_axis_tready         (s_axis_cmac_rx_tready),
        .s_axis_tdata          (s_axis_cmac_rx_tdata),
        .s_axis_tkeep          (s_axis_cmac_rx_tkeep),
        .s_axis_tlast          (s_axis_cmac_rx_tlast),
        .s_axis_tuser_bad_frame(s_axis_cmac_rx_tuser_bad_frame),
        .m_axis_tvalid         (strip_rx_tvalid),
        .m_axis_tready         (strip_rx_tready),
        .m_axis_tdata          (strip_rx_tdata),
        .m_axis_tkeep          (strip_rx_tkeep),
        .m_axis_tlast          (strip_rx_tlast),
        .m_axis_tuser_bad_frame(strip_rx_tuser_bad_frame)
    );

    market_parser_udp_payload_strip #(
        .FEED_UDP_PORT(FEED_UDP_PORT),
        .FIFO_DEPTH   (STRIP_FIFO_DEPTH)
    ) payload_strip_i (
        .clk                            (clk),
        .rst                            (rst),
        .s_axis_rx_tvalid               (strip_rx_tvalid),
        .s_axis_rx_tready               (strip_rx_tready),
        .s_axis_rx_tdata                (strip_rx_tdata),
        .s_axis_rx_tkeep                (strip_rx_tkeep),
        .s_axis_rx_tlast                (strip_rx_tlast),
        .s_axis_rx_tuser_bad_frame      (strip_rx_tuser_bad_frame),
        .m_axis_payload_tvalid          (payload_tvalid),
        .m_axis_payload_tready          (payload_tready),
        .m_axis_payload_tdata           (payload_tdata),
        .m_axis_payload_tkeep           (payload_tkeep),
        .m_axis_payload_tlast           (payload_tlast),
        .m_axis_payload_tuser_bad_frame (payload_tuser_bad_frame),
        .accepted_frame_count           (cmac_accepted_frame_count),
        .dropped_frame_count            (cmac_dropped_frame_count),
        .header_error_count             (cmac_header_error_count),
        .payload_packet_count           (cmac_payload_packet_count),
        .payload_fifo_level             (cmac_payload_fifo_level)
    );

    market_parser_axis_register_slice #(
        .DATA_WIDTH(512),
        .KEEP_WIDTH(64)
    ) payload_slice_i (
        .clk                   (clk),
        .rst                   (rst),
        .s_axis_tvalid         (payload_tvalid),
        .s_axis_tready         (payload_tready),
        .s_axis_tdata          (payload_tdata),
        .s_axis_tkeep          (payload_tkeep),
        .s_axis_tlast          (payload_tlast),
        .s_axis_tuser_bad_frame(payload_tuser_bad_frame),
        .m_axis_tvalid         (parser_payload_tvalid),
        .m_axis_tready         (parser_payload_tready),
        .m_axis_tdata          (parser_payload_tdata),
        .m_axis_tkeep          (parser_payload_tkeep),
        .m_axis_tlast          (parser_payload_tlast),
        .m_axis_tuser_bad_frame(parser_payload_tuser_bad_frame)
    );

    market_parser_512_system #(
        .PACKET_BEATS_MAX        (PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH         (DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES (EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH        (EVENT_FIFO_DEPTH),
        .BUILD_ID                (BUILD_ID)
    ) parser_system_i (
        .clk                       (clk),
        .rst                       (rst),
        .s_axis_rx_tvalid          (parser_payload_tvalid),
        .s_axis_rx_tready          (parser_payload_tready),
        .s_axis_rx_tdata           (parser_payload_tdata),
        .s_axis_rx_tkeep           (parser_payload_tkeep),
        .s_axis_rx_tlast           (parser_payload_tlast),
        .s_axis_rx_tuser_bad_frame (parser_payload_tuser_bad_frame),
        .event_valid               (event_valid),
        .event_ready               (event_ready),
        .event_data                (event_data),
        .event_new_order_ref       (event_new_order_ref),
        .event_keep                (event_keep),
        .event_last                (event_last),
        .feed_healthy_status       (feed_healthy_status),
        .feed_gap_count_status     (feed_gap_count_status),
        .feed_suppressed_event_count_status(feed_suppressed_event_count_status),
        .feed_recover_pulse        (feed_recover_pulse),
        .cmac_axis_accepted_packet_count_status(cmac_axis_accepted_packet_count_status),
        .cmac_axis_overflow_packet_count_status(cmac_axis_overflow_packet_count_status),
        .cmac_axis_dropped_beat_count_status(cmac_axis_dropped_beat_count_status),
        .cmac_axis_fifo_level_status(cmac_axis_fifo_level_status),
        .cmac_axis_fifo_high_watermark_status(cmac_axis_fifo_high_watermark_status),
        .s_axi_awaddr              (s_axi_awaddr),
        .s_axi_awvalid             (s_axi_awvalid),
        .s_axi_awready             (s_axi_awready),
        .s_axi_wdata               (s_axi_wdata),
        .s_axi_wstrb               (s_axi_wstrb),
        .s_axi_wvalid              (s_axi_wvalid),
        .s_axi_wready              (s_axi_wready),
        .s_axi_bresp               (s_axi_bresp),
        .s_axi_bvalid              (s_axi_bvalid),
        .s_axi_bready              (s_axi_bready),
        .s_axi_araddr              (s_axi_araddr),
        .s_axi_arvalid             (s_axi_arvalid),
        .s_axi_arready             (s_axi_arready),
        .s_axi_rdata               (s_axi_rdata),
        .s_axi_rresp               (s_axi_rresp),
        .s_axi_rvalid              (s_axi_rvalid),
        .s_axi_rready              (s_axi_rready)
    );

endmodule
`default_nettype wire
