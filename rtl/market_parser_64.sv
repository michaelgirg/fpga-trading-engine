`default_nettype none
// =============================================================================
// Module: market_parser_64
// =============================================================================
// 64-bit input wrapper for the byte-oriented market_parser core.
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
    // =========================================================================
    // Word-to-byte adapter state
    // =========================================================================
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SEND
    } state_t;

    state_t      state_r;
    logic [63:0] word_data_r;
    logic [ 7:0] word_keep_r;
    logic        word_last_r;
    logic [ 2:0] lane_idx_r;

    logic        byte_valid_i;
    logic        byte_ready_i;
    logic [ 7:0] byte_data_i;
    logic        byte_keep_i;
    logic        byte_last_i;
    logic [ 2:0] next_valid_lane_i;

    assign data_in_ready = (state_r == ST_IDLE);
    assign byte_valid_i  = (state_r == ST_SEND) && word_keep_r[lane_idx_r];
    assign byte_data_i   = word_data_r[lane_idx_r*8 +: 8];
    assign byte_keep_i   = 1'b1;
    assign byte_last_i   = word_last_r && (lane_idx_r == next_valid_lane_i);

    // =========================================================================
    // Next valid lane finder
    // =========================================================================
    always_comb begin
        next_valid_lane_i = lane_idx_r;
        for (int i = 0; i < 8; i++) begin
            if (word_keep_r[i]) next_valid_lane_i = 3'(i);
        end
    end

    // =========================================================================
    // Adapter FSM
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state_r    <= ST_IDLE;
            word_data_r <= '0;
            word_keep_r <= '0;
            word_last_r <= 1'b0;
            lane_idx_r  <= '0;
        end else begin
            case (state_r)
                ST_IDLE: begin
                    if (data_in_valid && data_in_ready) begin
                        word_data_r <= data_in_data;
                        word_keep_r <= data_in_keep;
                        word_last_r <= data_in_last;
                        lane_idx_r  <= '0;
                        state_r     <= (data_in_keep == 8'h00) ? ST_IDLE : ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (byte_valid_i && byte_ready_i) begin
                        if (lane_idx_r == next_valid_lane_i) begin
                            lane_idx_r <= '0;
                            state_r    <= ST_IDLE;
                        end else begin
                            lane_idx_r <= lane_idx_r + 1'b1;
                        end
                    end else if (!word_keep_r[lane_idx_r]) begin
                        if (lane_idx_r == next_valid_lane_i) begin
                            lane_idx_r <= '0;
                            state_r    <= ST_IDLE;
                        end else begin
                            lane_idx_r <= lane_idx_r + 1'b1;
                        end
                    end
                end

                default: begin
                    state_r    <= ST_IDLE;
                    lane_idx_r <= '0;
                end
            endcase
        end
    end

    // =========================================================================
    // Byte parser core
    // =========================================================================
    market_parser #(
        .INPUT_BUS_WIDTH (8),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) u_market_parser (
        .clk              (clk),
        .rst              (rst),
        .data_in_valid    (byte_valid_i),
        .data_in_ready    (byte_ready_i),
        .data_in_data     (byte_data_i),
        .data_in_keep     (byte_keep_i),
        .data_in_last     (byte_last_i),
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
