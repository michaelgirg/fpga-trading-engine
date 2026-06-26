`default_nettype none
// =============================================================================
// Module: market_parser_512_window_buffer
// =============================================================================
// Packet-local 512-bit beat store with a multi-beat extraction window.
//
// This block is intentionally small: it captures accepted packet beats and
// presents the aligned window containing a requested message start byte.
module market_parser_512_window_buffer #(
    parameter int PACKET_BEATS_MAX = 16,
    parameter int WINDOW_BYTES     = 256
) (
    input  wire logic                         clk,
    input  wire logic                         rst,
    input  wire logic                         clear,

    input  wire logic                         beat_write_en,
    input  wire logic [                  15:0] beat_write_index,
    input  wire logic [                 511:0] beat_write_data,
    input  wire logic [                  63:0] beat_write_keep,

    input  wire logic [                  15:0] read_message_start_byte,
    output logic [                  15:0]      window_base_byte,
    output logic [    WINDOW_BYTES*8-1:0]      window_data,
    output logic [      WINDOW_BYTES-1:0]      window_keep
);
    localparam int WINDOW_BEATS = WINDOW_BYTES / 64;

    initial begin
        if (PACKET_BEATS_MAX < 2) begin
            $fatal(1, "PACKET_BEATS_MAX must be at least 2");
        end
        if (WINDOW_BYTES < 128 || (WINDOW_BYTES % 64) != 0) begin
            $fatal(1, "WINDOW_BYTES must be a multiple of 64 and at least 128");
        end
    end

    logic [511:0] beat_data_r [PACKET_BEATS_MAX];
    logic [ 63:0] beat_keep_r [PACKET_BEATS_MAX];
    logic         beat_valid_r[PACKET_BEATS_MAX];

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            for (int i = 0; i < PACKET_BEATS_MAX; i++) begin
                beat_data_r [i] <= '0;
                beat_keep_r [i] <= '0;
                beat_valid_r[i] <= 1'b0;
            end
        end else if (beat_write_en && int'(beat_write_index) < PACKET_BEATS_MAX) begin
            beat_data_r [int'(beat_write_index)] <= beat_write_data;
            beat_keep_r [int'(beat_write_index)] <= beat_write_keep;
            beat_valid_r[int'(beat_write_index)] <= 1'b1;
        end
    end

    always_comb begin
        int base_beat;

        base_beat        = int'(read_message_start_byte[15:6]);
        window_base_byte = {read_message_start_byte[15:6], 6'b0};
        window_data      = '0;
        window_keep      = '0;

        for (int w = 0; w < WINDOW_BEATS; w++) begin
            if ((base_beat + w) < PACKET_BEATS_MAX && beat_valid_r[base_beat + w]) begin
                window_data[w*512 +: 512] = beat_data_r[base_beat + w];
                window_keep[w*64 +: 64]   = beat_keep_r[base_beat + w];
            end
        end
    end

endmodule
`default_nettype wire
