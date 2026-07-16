`default_nettype none
// =============================================================================
// Module: market_parser_512_system
// =============================================================================
// Pre-hardware integration wrapper:
//   512-bit parser pipeline + event FIFO + AXI-Lite status/control registers.
module market_parser_512_system #(
    parameter int PACKET_BEATS_MAX = 16,
    parameter int DESC_FIFO_DEPTH  = 32,
    parameter int EXTRACTION_WINDOW_BYTES = 256,
    parameter int EVENT_FIFO_DEPTH = 16,
    parameter logic [31:0] BUILD_ID = 32'h4d50_5253,
    parameter logic [31:0] FEED_TIMEOUT_CYCLES_DEFAULT = 32'd0
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         s_axis_rx_tvalid,
    output logic              s_axis_rx_tready,
    input  wire logic [511:0] s_axis_rx_tdata,
    input  wire logic [ 63:0] s_axis_rx_tkeep,
    input  wire logic         s_axis_rx_tlast,
    input  wire logic         s_axis_rx_tuser_bad_frame,

    output logic              event_valid,
    input  wire logic         event_ready,
    output logic [255:0]      event_data,
    output logic [ 63:0]      event_new_order_ref,
    output logic [ 31:0]      event_keep,
    output logic              event_last,

    input  wire logic         feed_healthy_status,
    input  wire logic         feed_rebuilding_status,
    input  wire logic [31:0]  feed_gap_count_status,
    input  wire logic [31:0]  feed_suppressed_event_count_status,
    input  wire logic [31:0]  feed_idle_cycles_status,
    input  wire logic [31:0]  feed_timeout_count_status,
    output logic              feed_recover_pulse,
    output logic              feed_activate_pulse,
    output logic [31:0]       feed_timeout_cycles_config,

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
    input  wire logic         s_axi_rready
);
    logic parser_enable;
    logic clear_counters_pulse;
    logic pipe_ready;
    logic pipe_valid;
    logic ingress_backpressure_active;

    logic [31:0] packet_count;
    logic [31:0] descriptor_count;
    logic [31:0] event_count;
    logic [31:0] extractor_error_count;
    logic [31:0] bad_frame_count;
    logic [15:0] event_fifo_level;
    logic [31:0] event_fifo_write_count;
    logic [31:0] event_fifo_read_count;
    logic [31:0] event_fifo_backpressure_count;
    logic [ 7:0] error_flags_in;
    logic [31:0] extractor_error_count_prev_r;
    logic [31:0] bad_frame_count_prev_r;
    logic [31:0] event_fifo_backpressure_count_prev_r;
    logic [ 7:0] error_flags_in_r;

    assign pipe_valid = s_axis_rx_tvalid && parser_enable;
    assign s_axis_rx_tready = parser_enable && pipe_ready;
    assign ingress_backpressure_active = s_axis_rx_tvalid && !s_axis_rx_tready;
    assign error_flags_in = error_flags_in_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            extractor_error_count_prev_r         <= '0;
            bad_frame_count_prev_r               <= '0;
            event_fifo_backpressure_count_prev_r <= '0;
            error_flags_in_r                     <= '0;
        end else begin
            error_flags_in_r <= {
                3'd0,
                event_fifo_backpressure_count != event_fifo_backpressure_count_prev_r,
                bad_frame_count != bad_frame_count_prev_r,
                1'b0,
                extractor_error_count != extractor_error_count_prev_r,
                1'b0
            };
            extractor_error_count_prev_r         <= extractor_error_count;
            bad_frame_count_prev_r               <= bad_frame_count;
            event_fifo_backpressure_count_prev_r <= event_fifo_backpressure_count;
        end
    end

    market_parser_512_pipeline_fifo #(
        .PACKET_BEATS_MAX        (PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH         (DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES (EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH        (EVENT_FIFO_DEPTH)
    ) parser_i (
        .clk                           (clk),
        .rst                           (rst),
        .s_axis_rx_tvalid              (pipe_valid),
        .s_axis_rx_tready              (pipe_ready),
        .s_axis_rx_tdata               (s_axis_rx_tdata),
        .s_axis_rx_tkeep               (s_axis_rx_tkeep),
        .s_axis_rx_tlast               (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame     (s_axis_rx_tuser_bad_frame),
        .event_valid                   (event_valid),
        .event_ready                   (event_ready),
        .event_data                    (event_data),
        .event_new_order_ref           (event_new_order_ref),
        .event_keep                    (event_keep),
        .event_last                    (event_last),
        .packet_count                  (packet_count),
        .descriptor_count              (descriptor_count),
        .event_count                   (event_count),
        .extractor_error_count         (extractor_error_count),
        .bad_frame_count               (bad_frame_count),
        .event_fifo_level              (event_fifo_level),
        .event_fifo_write_count        (event_fifo_write_count),
        .event_fifo_read_count         (event_fifo_read_count),
        .event_fifo_backpressure_count (event_fifo_backpressure_count)
    );

    market_parser_axi_lite_regs #(
        .ADDR_WIDTH      (12),
        .BUILD_ID        (BUILD_ID),
        .EVENT_FIFO_DEPTH(EVENT_FIFO_DEPTH),
        .FEED_TIMEOUT_CYCLES_DEFAULT(FEED_TIMEOUT_CYCLES_DEFAULT)
    ) regs_i (
        .clk                            (clk),
        .rst                            (rst),
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
        .packet_count                   (packet_count),
        .descriptor_count               (descriptor_count),
        .event_count                    (event_count),
        .extractor_error_count          (extractor_error_count),
        .bad_frame_count                (bad_frame_count),
        .event_fifo_level               (event_fifo_level),
        .event_fifo_write_count         (event_fifo_write_count),
        .event_fifo_read_count          (event_fifo_read_count),
        .event_fifo_backpressure_count  (event_fifo_backpressure_count),
        .ingress_backpressure_active    (ingress_backpressure_active),
        .event_out_valid                (event_valid),
        .error_flags_in                 (error_flags_in),
        .feed_healthy                   (feed_healthy_status),
        .feed_rebuilding                (feed_rebuilding_status),
        .feed_gap_count                 (feed_gap_count_status),
        .feed_suppressed_event_count    (feed_suppressed_event_count_status),
        .feed_idle_cycles               (feed_idle_cycles_status),
        .feed_timeout_count             (feed_timeout_count_status),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count_status),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count_status),
        .cmac_axis_dropped_beat_count   (cmac_axis_dropped_beat_count_status),
        .cmac_axis_fifo_level           (cmac_axis_fifo_level_status),
        .cmac_axis_fifo_high_watermark  (cmac_axis_fifo_high_watermark_status),
        .parser_enable                  (parser_enable),
        .clear_counters_pulse           (clear_counters_pulse),
        .feed_recover_pulse             (feed_recover_pulse),
        .feed_activate_pulse            (feed_activate_pulse),
        .feed_timeout_cycles_config     (feed_timeout_cycles_config)
    );

endmodule
`default_nettype wire
