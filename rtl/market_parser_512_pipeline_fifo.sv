`default_nettype none
// =============================================================================
// Module: market_parser_512_pipeline_fifo
// =============================================================================
// 512-bit parallel event pipeline with an output event FIFO.
//
// The parser can drain packet-generated events into the FIFO while the consumer
// stalls. The upstream pipeline can now emit eligible events before packet end,
// while this boundary queues normalized events independently from downstream
// timing.
module market_parser_512_pipeline_fifo #(
    parameter int PACKET_BEATS_MAX = 16,
    parameter int DESC_FIFO_DEPTH  = 32,
    parameter int EXTRACTION_WINDOW_BYTES = 256,
    parameter int EVENT_FIFO_DEPTH = 16
) (
    input  wire logic         clk,
    input  wire logic         rst,
    input  wire logic         sequence_rearm,

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

    output logic [31:0]       packet_count,
    output logic [31:0]       descriptor_count,
    output logic [31:0]       event_count,
    output logic [31:0]       extractor_error_count,
    output logic [31:0]       bad_frame_count,

    output logic [15:0]       event_fifo_level,
    output logic [31:0]       event_fifo_write_count,
    output logic [31:0]       event_fifo_read_count,
    output logic [31:0]       event_fifo_backpressure_count
);
    logic         pipe_event_valid;
    logic         pipe_event_ready;
    logic [255:0] pipe_event_data;
    logic [ 63:0] pipe_event_new_order_ref;
    logic [ 31:0] pipe_event_keep;
    logic         pipe_event_last;
    logic [319:0] fifo_event_data;

    assign event_data          = fifo_event_data[255:0];
    assign event_new_order_ref = fifo_event_data[319:256];

    market_parser_512_pipeline #(
        .PACKET_BEATS_MAX        (PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH         (DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES (EXTRACTION_WINDOW_BYTES)
    ) pipeline_i (
        .clk                  (clk),
        .rst                  (rst),
        .sequence_rearm       (sequence_rearm),
        .s_axis_rx_tvalid     (s_axis_rx_tvalid),
        .s_axis_rx_tready     (s_axis_rx_tready),
        .s_axis_rx_tdata      (s_axis_rx_tdata),
        .s_axis_rx_tkeep      (s_axis_rx_tkeep),
        .s_axis_rx_tlast      (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame(s_axis_rx_tuser_bad_frame),
        .event_valid          (pipe_event_valid),
        .event_ready          (pipe_event_ready),
        .event_data           (pipe_event_data),
        .event_new_order_ref  (pipe_event_new_order_ref),
        .event_keep           (pipe_event_keep),
        .event_last           (pipe_event_last),
        .packet_count         (packet_count),
        .descriptor_count     (descriptor_count),
        .event_count          (event_count),
        .extractor_error_count(extractor_error_count),
        .bad_frame_count      (bad_frame_count)
    );

    market_parser_event_fifo #(
        .EVENT_WIDTH(320),
        .KEEP_WIDTH (32),
        .FIFO_DEPTH (EVENT_FIFO_DEPTH)
    ) event_fifo_i (
        .clk               (clk),
        .rst               (rst),
        .event_in_valid    (pipe_event_valid),
        .event_in_ready    (pipe_event_ready),
        .event_in_data     ({pipe_event_new_order_ref, pipe_event_data}),
        .event_in_keep     (pipe_event_keep),
        .event_in_last     (pipe_event_last),
        .event_out_valid   (event_valid),
        .event_out_ready   (event_ready),
        .event_out_data    (fifo_event_data),
        .event_out_keep    (event_keep),
        .event_out_last    (event_last),
        .fifo_level        (event_fifo_level),
        .write_count       (event_fifo_write_count),
        .read_count        (event_fifo_read_count),
        .backpressure_count(event_fifo_backpressure_count)
    );

endmodule
`default_nettype wire
