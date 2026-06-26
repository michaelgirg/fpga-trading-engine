`default_nettype none
// =============================================================================
// Module: market_parser_512_window_buffer
// =============================================================================
// Packet-local 512-bit beat store with a two-beat extraction window.
//
// This block is intentionally small: it captures accepted packet beats and
// presents the 1024-bit window containing a requested message start byte. The
// first integrated 512-bit pipeline uses this as a packet-buffered handoff
// between descriptor generation and parallel field extraction.
module market_parser_512_window_buffer #(
    parameter int PACKET_BEATS_MAX = 16,
    parameter int WINDOW_BYTES     = 128
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
    initial begin
        if (PACKET_BEATS_MAX < 2) begin
            $fatal(1, "PACKET_BEATS_MAX must be at least 2");
        end
        if (WINDOW_BYTES != 128) begin
            $fatal(1, "market_parser_512_window_buffer currently supports a 128-byte window");
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
        end else if (beat_write_en && beat_write_index < PACKET_BEATS_MAX) begin
            beat_data_r [beat_write_index] <= beat_write_data;
            beat_keep_r [beat_write_index] <= beat_write_keep;
            beat_valid_r[beat_write_index] <= 1'b1;
        end
    end

    always_comb begin
        int base_beat;
        int next_beat;

        base_beat        = int'(read_message_start_byte[15:6]);
        next_beat        = base_beat + 1;
        window_base_byte = {read_message_start_byte[15:6], 6'b0};
        window_data      = '0;
        window_keep      = '0;

        if (base_beat < PACKET_BEATS_MAX && beat_valid_r[base_beat]) begin
            window_data[511:0] = beat_data_r[base_beat];
            window_keep[63:0]  = beat_keep_r[base_beat];
        end

        if (next_beat < PACKET_BEATS_MAX && beat_valid_r[next_beat]) begin
            window_data[1023:512] = beat_data_r[next_beat];
            window_keep[127:64]   = beat_keep_r[next_beat];
        end
    end

endmodule
`default_nettype wire
