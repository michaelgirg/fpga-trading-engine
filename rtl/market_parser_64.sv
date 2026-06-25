`default_nettype none
// =============================================================================
// Module: market_parser_64
// =============================================================================
// Compatibility wrapper for the 64-bit stream profile.
//
// Byte lane order follows common AXI-stream byte ordering:
//   lane 0 = data_in_data[7:0], lane 1 = data_in_data[15:8], ...
module market_parser_64 #(
    parameter int OUTPUT_BUS_WIDTH = 256
) (
    input  wire logic                         clk,
    input  wire logic                         rst,

    input  wire logic                         data_in_valid,
    output logic                              data_in_ready,
    input  wire logic [                63:0]  data_in_data,
    input  wire logic [                 7:0]  data_in_keep,
    input  wire logic                         data_in_last,

    output logic                              data_out_valid,
    input  wire logic                         data_out_ready,
    output logic [  OUTPUT_BUS_WIDTH-1:0]     data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0]     data_out_keep,
    output logic                              data_out_last,

    output logic                              gap_error,
    output logic                              malformed_error,
    output logic                              unknown_msg_type,
    output logic [                  63:0]     expected_sequence,
    output logic [                  63:0]     packet_sequence,
    output logic [                  31:0]     packet_count,
    output logic [                  31:0]     message_count,
    output logic [                  31:0]     event_count,
    output logic [                  31:0]     error_count
);
    market_parser_axis_adapter #(
        .DATA_WIDTH      (64),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) u_axis_adapter (
        .clk              (clk),
        .rst              (rst),
        .data_in_valid    (data_in_valid),
        .data_in_ready    (data_in_ready),
        .data_in_data     (data_in_data),
        .data_in_keep     (data_in_keep),
        .data_in_last     (data_in_last),
        .data_out_valid   (data_out_valid),
        .data_out_ready   (data_out_ready),
        .data_out_data    (data_out_data),
        .data_out_keep    (data_out_keep),
        .data_out_last    (data_out_last),
        .gap_error        (gap_error),
        .malformed_error  (malformed_error),
        .unknown_msg_type (unknown_msg_type),
        .expected_sequence(expected_sequence),
        .packet_sequence  (packet_sequence),
        .packet_count     (packet_count),
        .message_count    (message_count),
        .event_count      (event_count),
        .error_count      (error_count)
    );

endmodule
`default_nettype wire
