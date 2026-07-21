`default_nettype none
// =============================================================================
// Module: market_parser_512_window_buffer
// =============================================================================
// Packet-local 512-bit beat store with a multi-beat extraction window.
//
// Each window beat has an independent distributed-RAM read copy. Writes are
// broadcast to every copy, allowing a registered multi-beat read without a
// resettable register array or a wide asynchronous address mux.
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

    input  wire logic                         read_en,
    input  wire logic [                  15:0] read_message_start_byte,
    input  wire logic [                  15:0] read_stored_beats,
    output logic                              read_valid,
    output logic [                  15:0]      window_base_byte,
    output logic [    WINDOW_BYTES*8-1:0]      window_data,
    output logic [      WINDOW_BYTES-1:0]      window_keep
);
    localparam int WINDOW_BEATS = WINDOW_BYTES / 64;
    localparam int ENTRY_WIDTH  = 512 + 64;

    initial begin
        if (PACKET_BEATS_MAX < 2) begin
            $fatal(1, "PACKET_BEATS_MAX must be at least 2");
        end
        if (WINDOW_BYTES < 128 || (WINDOW_BYTES % 64) != 0) begin
            $fatal(1, "WINDOW_BYTES must be a multiple of 64 and at least 128");
        end
    end

    logic [ENTRY_WIDTH-1:0] window_entry_r[WINDOW_BEATS];
    logic [WINDOW_BEATS-1:0] window_entry_valid_r;
    logic                    read_valid_r;
    logic [15:0]             window_base_byte_r;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            read_valid_r      <= 1'b0;
            window_base_byte_r <= '0;
        end else begin
            read_valid_r <= read_en;
            if (read_en) begin
                window_base_byte_r <= {read_message_start_byte[15:6], 6'b0};
            end
        end
    end

    generate
        for (genvar w = 0; w < WINDOW_BEATS; w++) begin : g_window_read_copy
            (* ram_style = "distributed" *) logic [ENTRY_WIDTH-1:0] beat_mem[PACKET_BEATS_MAX];

            always_ff @(posedge clk) begin
                if (rst || clear) begin
                    window_entry_r[w]       <= '0;
                    window_entry_valid_r[w] <= 1'b0;
                end else begin
                    if (beat_write_en && int'(beat_write_index) < PACKET_BEATS_MAX) begin
                        beat_mem[int'(beat_write_index)] <= {beat_write_keep, beat_write_data};
                    end

                    if (read_en) begin
                        if ((int'(read_message_start_byte[15:6]) + w) < PACKET_BEATS_MAX) begin
                            window_entry_r[w] <= beat_mem[int'(read_message_start_byte[15:6]) + w];
                            window_entry_valid_r[w] <=
                                (int'(read_message_start_byte[15:6]) + w) < int'(read_stored_beats);
                        end else begin
                            window_entry_r[w]       <= '0;
                            window_entry_valid_r[w] <= 1'b0;
                        end
                    end
                end
            end
        end
    endgenerate

    always_comb begin
        read_valid      = read_valid_r;
        window_base_byte = window_base_byte_r;
        window_data      = '0;
        window_keep      = '0;

        for (int w = 0; w < WINDOW_BEATS; w++) begin
            if (window_entry_valid_r[w]) begin
                window_data[w*512 +: 512] = window_entry_r[w][511:0];
                window_keep[w*64 +: 64]   = window_entry_r[w][512 +: 64];
            end
        end
    end

endmodule
`default_nettype wire
