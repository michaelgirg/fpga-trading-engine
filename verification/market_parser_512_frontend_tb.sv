`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_512_frontend_tb
// =============================================================================
// Unit test for the multi-beat 512-bit descriptor frontend.
module market_parser_512_frontend_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int CUSTOM_PACKET_BYTES = 192;
    localparam int EXPECTED_MIXED_DESCS = 8;
    localparam int DENSE_SYSTEM_EVENTS = 10;
    localparam int DENSE_PACKET_BYTES = 20 + (DENSE_SYSTEM_EVENTS * 14);

    localparam logic [7:0] DESC_FLAG_CROSSES_BEAT = 8'h01;
    localparam logic [7:0] DESC_FLAG_BAD_FRAME    = 8'h04;
    localparam logic [7:0] DESC_FLAG_GAP          = 8'h10;

    typedef logic [7:0] byte_t;

    logic clk = 1'b0;
    logic rst;
    logic sequence_rearm;

    logic         s_axis_rx_tvalid;
    logic         s_axis_rx_tready;
    logic [511:0] s_axis_rx_tdata;
    logic [ 63:0] s_axis_rx_tkeep;
    logic         s_axis_rx_tlast;
    logic         s_axis_rx_tuser_bad_frame;

    logic        desc_valid;
    logic        desc_ready;
    logic [63:0] desc_packet_sequence;
    logic [15:0] desc_message_index;
    logic [15:0] desc_message_length;
    logic [15:0] desc_message_start_byte;
    logic [15:0] desc_message_end_byte;
    logic [ 7:0] desc_message_type;
    logic [ 5:0] desc_message_type_lane;
    logic        desc_message_type_valid;
    logic [ 7:0] desc_flags;
    logic [31:0] packet_count;
    logic [31:0] descriptor_count;
    logic [31:0] error_count;

    int passed;
    int failed;

    byte_t mixed_packet_mem [MIXED_PACKET_BYTES];
    byte_t custom_packet_mem[CUSTOM_PACKET_BYTES];

    int expected_start [EXPECTED_MIXED_DESCS];
    int expected_end   [EXPECTED_MIXED_DESCS];
    int expected_len   [EXPECTED_MIXED_DESCS];
    int expected_type  [EXPECTED_MIXED_DESCS];
    bit expected_type_valid[EXPECTED_MIXED_DESCS];
    logic [7:0] expected_flags[EXPECTED_MIXED_DESCS];

    market_parser_512_frontend DUT (
        .clk                       (clk),
        .rst                       (rst),
        .sequence_rearm            (sequence_rearm),
        .s_axis_rx_tvalid          (s_axis_rx_tvalid),
        .s_axis_rx_tready          (s_axis_rx_tready),
        .s_axis_rx_tdata           (s_axis_rx_tdata),
        .s_axis_rx_tkeep           (s_axis_rx_tkeep),
        .s_axis_rx_tlast           (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame (s_axis_rx_tuser_bad_frame),
        .desc_valid                (desc_valid),
        .desc_ready                (desc_ready),
        .desc_packet_sequence      (desc_packet_sequence),
        .desc_message_index        (desc_message_index),
        .desc_message_length       (desc_message_length),
        .desc_message_start_byte   (desc_message_start_byte),
        .desc_message_end_byte     (desc_message_end_byte),
        .desc_message_type         (desc_message_type),
        .desc_message_type_lane    (desc_message_type_lane),
        .desc_message_type_valid   (desc_message_type_valid),
        .desc_flags                (desc_flags),
        .packet_count              (packet_count),
        .descriptor_count          (descriptor_count),
        .error_count               (error_count)
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic reset_dut();
        rst                       = 1'b1;
        sequence_rearm            = 1'b0;
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
        desc_ready                = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    endtask

    task automatic check(input bit condition, input string msg);
        if (condition) begin
            passed++;
            $display("PASS: %s", msg);
        end else begin
            failed++;
            $error("FAIL: %s", msg);
        end
    endtask

    task automatic load_vectors();
        string mixed_path;
        mixed_path = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        $readmemh(mixed_path, mixed_packet_mem);
    endtask

    task automatic init_expected_mixed();
        expected_start[0] = 22;  expected_end[0] = 61;  expected_len[0] = 40; expected_type[0] = "F"; expected_type_valid[0] = 1'b1; expected_flags[0] = 8'h00;
        expected_start[1] = 64;  expected_end[1] = 94;  expected_len[1] = 31; expected_type[1] = 0;   expected_type_valid[1] = 1'b0; expected_flags[1] = 8'h00;
        expected_start[2] = 97;  expected_end[2] = 132; expected_len[2] = 36; expected_type[2] = "C"; expected_type_valid[2] = 1'b1; expected_flags[2] = DESC_FLAG_CROSSES_BEAT;
        expected_start[3] = 135; expected_end[3] = 157; expected_len[3] = 23; expected_type[3] = "X"; expected_type_valid[3] = 1'b1; expected_flags[3] = 8'h00;
        expected_start[4] = 160; expected_end[4] = 178; expected_len[4] = 19; expected_type[4] = "D"; expected_type_valid[4] = 1'b1; expected_flags[4] = 8'h00;
        expected_start[5] = 181; expected_end[5] = 215; expected_len[5] = 35; expected_type[5] = "U"; expected_type_valid[5] = 1'b1; expected_flags[5] = DESC_FLAG_CROSSES_BEAT;
        expected_start[6] = 218; expected_end[6] = 261; expected_len[6] = 44; expected_type[6] = "P"; expected_type_valid[6] = 1'b1; expected_flags[6] = DESC_FLAG_CROSSES_BEAT;
        expected_start[7] = 264; expected_end[7] = 275; expected_len[7] = 12; expected_type[7] = "Z"; expected_type_valid[7] = 1'b1; expected_flags[7] = 8'h00;
    endtask

    task automatic send_beat(input logic [511:0] beat_data,
                             input logic [ 63:0] beat_keep,
                             input bit           beat_last,
                             input bit           beat_bad);
        @(negedge clk);
        s_axis_rx_tvalid          = 1'b1;
        s_axis_rx_tdata           = beat_data;
        s_axis_rx_tkeep           = beat_keep;
        s_axis_rx_tlast           = beat_last;
        s_axis_rx_tuser_bad_frame = beat_bad;
        while (!s_axis_rx_tready) @(negedge clk);
        @(negedge clk);
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
    endtask

    task automatic send_packet(input int packet_bytes, input byte_t packet_mem[], input bit bad_first_beat);
        int offset;
        int bytes_left;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [ 63:0] beat_keep;

        offset = 0;
        while (offset < packet_bytes) begin
            bytes_left = packet_bytes - offset;
            beat_bytes = (bytes_left >= 64) ? 64 : bytes_left;
            beat_data = '0;
            beat_keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                beat_keep[lane] = 1'b1;
            end
            send_beat(beat_data, beat_keep, offset + beat_bytes >= packet_bytes,
                      bad_first_beat && offset == 0);
            offset += beat_bytes;
        end
    endtask

    task automatic wait_desc(input string msg);
        int cycles;
        cycles = 0;
        while (!desc_valid && cycles < 200) begin
            @(posedge clk);
            cycles++;
        end
        check(desc_valid, {msg, " descriptor valid"});
    endtask

    task automatic check_mixed_desc(input int idx,
                                    input logic [63:0] expected_sequence,
                                    input logic [7:0] extra_flags);
        wait_desc($sformatf("mixed message %0d", idx));
        check(desc_packet_sequence == expected_sequence,
              $sformatf("mixed message %0d sequence", idx));
        check(desc_message_index == idx[15:0], $sformatf("mixed message %0d index", idx));
        check(desc_message_length == expected_len[idx][15:0], $sformatf("mixed message %0d length", idx));
        check(desc_message_start_byte == expected_start[idx][15:0], $sformatf("mixed message %0d start offset", idx));
        check(desc_message_end_byte == expected_end[idx][15:0], $sformatf("mixed message %0d end offset", idx));
        check(desc_message_type_valid == expected_type_valid[idx], $sformatf("mixed message %0d type-valid flag", idx));
        if (expected_type_valid[idx]) begin
            check(desc_message_type == expected_type[idx][7:0], $sformatf("mixed message %0d type", idx));
        end
        check(desc_flags == (expected_flags[idx] | extra_flags),
              $sformatf("mixed message %0d flags", idx));
        @(posedge clk);
    endtask

    task automatic build_split_length_packet();
        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd9;
        custom_packet_mem[19] = 8'd2;
        custom_packet_mem[21] = 8'd41;
        custom_packet_mem[22] = "A";
        for (int i = 23; i <= 62; i++) custom_packet_mem[i] = 8'haa;
        custom_packet_mem[63] = 8'h00;
        custom_packet_mem[64] = 8'd12;
        custom_packet_mem[65] = "S";
        for (int i = 66; i <= 76; i++) custom_packet_mem[i] = 8'h55;
    endtask

    task automatic build_dense_system_event_packet();
        int len_offset;
        int msg_start;

        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd64;
        custom_packet_mem[19] = DENSE_SYSTEM_EVENTS[7:0];

        for (int i = 0; i < DENSE_SYSTEM_EVENTS; i++) begin
            len_offset = 20 + (i * 14);
            msg_start = len_offset + 2;
            custom_packet_mem[len_offset] = 8'h00;
            custom_packet_mem[len_offset + 1] = 8'd12;
            custom_packet_mem[msg_start] = "S";
            custom_packet_mem[msg_start + 1] = 8'h01;
            custom_packet_mem[msg_start + 2] = 8'(i);
            custom_packet_mem[msg_start + 3] = 8'h02;
            custom_packet_mem[msg_start + 4] = 8'(i);
            custom_packet_mem[msg_start + 5] = 8'h00;
            custom_packet_mem[msg_start + 6] = 8'h00;
            custom_packet_mem[msg_start + 7] = 8'h00;
            custom_packet_mem[msg_start + 8] = 8'h00;
            custom_packet_mem[msg_start + 9] = 8'h40;
            custom_packet_mem[msg_start + 10] = 8'(i);
            custom_packet_mem[msg_start + 11] = "O";
        end
    endtask

    task automatic check_dense_system_desc(input int idx);
        int len_offset;
        int start_offset;
        int end_offset;
        bit expected_type_valid;
        logic [7:0] expected_desc_flags;

        len_offset = 20 + (idx * 14);
        start_offset = 22 + (idx * 14);
        end_offset = start_offset + 11;
        expected_type_valid = ((len_offset / 64) == (start_offset / 64));
        expected_desc_flags = ((start_offset / 64) != (end_offset / 64)) ? DESC_FLAG_CROSSES_BEAT : 8'h00;

        wait_desc($sformatf("dense system message %0d", idx));
        check(desc_packet_sequence == 64'd64, $sformatf("dense system message %0d sequence", idx));
        check(desc_message_index == idx[15:0], $sformatf("dense system message %0d index", idx));
        check(desc_message_length == 16'd12, $sformatf("dense system message %0d length", idx));
        check(desc_message_start_byte == start_offset[15:0],
              $sformatf("dense system message %0d start offset", idx));
        check(desc_message_end_byte == end_offset[15:0],
              $sformatf("dense system message %0d end offset", idx));
        check(desc_message_type_valid == expected_type_valid,
              $sformatf("dense system message %0d type-valid flag", idx));
        if (expected_type_valid) begin
            check(desc_message_type == "S", $sformatf("dense system message %0d type", idx));
        end
        check(desc_flags == expected_desc_flags, $sformatf("dense system message %0d flags", idx));
        @(posedge clk);
    endtask

    task automatic build_bad_frame_packet();
        for (int i = 0; i < CUSTOM_PACKET_BYTES; i++) custom_packet_mem[i] = 8'h00;
        custom_packet_mem[0] = "S"; custom_packet_mem[1] = "I"; custom_packet_mem[2] = "M";
        custom_packet_mem[3] = "0"; custom_packet_mem[4] = "0"; custom_packet_mem[5] = "0";
        custom_packet_mem[6] = "0"; custom_packet_mem[7] = "0"; custom_packet_mem[8] = "0";
        custom_packet_mem[9] = "1";
        custom_packet_mem[17] = 8'd10;
        custom_packet_mem[19] = 8'd1;
        custom_packet_mem[21] = 8'd12;
        custom_packet_mem[22] = "S";
        for (int i = 23; i <= 33; i++) custom_packet_mem[i] = 8'h11;
    endtask

    task automatic send_truncated_header();
        logic [511:0] beat_data;
        logic [ 63:0] beat_keep;
        beat_data = '0;
        beat_keep = 64'h0000_0000_0000_03ff;
        send_beat(beat_data, beat_keep, 1'b1, 1'b0);
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        load_vectors();
        init_expected_mixed();
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER 512-BIT FRONTEND TESTS");
        $display("========================================================");

        fork
            send_packet(MIXED_PACKET_BYTES, mixed_packet_mem, 1'b0);
            begin
                for (int i = 0; i < EXPECTED_MIXED_DESCS; i++) begin
                    check_mixed_desc(i, 64'd5, 8'h00);
                end
            end
        join
        check(packet_count == 32'd1, "mixed packet count");
        check(descriptor_count == 32'd8, "mixed descriptor count");
        check(error_count == 32'd0, "mixed error count");

        fork
            send_packet(MIXED_PACKET_BYTES, mixed_packet_mem, 1'b0);
            begin
                for (int i = 0; i < EXPECTED_MIXED_DESCS; i++) begin
                    check_mixed_desc(i, 64'd5, DESC_FLAG_GAP);
                end
            end
        join
        check(packet_count == 32'd2, "gap packet count");
        check(descriptor_count == 32'd16, "gap packet descriptor count");
        check(error_count == 32'd1, "sequence gap increments error count once");

        @(negedge clk);
        sequence_rearm = 1'b1;
        #1;
        check(!s_axis_rx_tready, "sequence rearm blocks a new input beat");
        @(negedge clk);
        sequence_rearm = 1'b0;
        mixed_packet_mem[10] = 8'h11;
        mixed_packet_mem[11] = 8'h22;
        mixed_packet_mem[12] = 8'h33;
        mixed_packet_mem[13] = 8'h44;
        mixed_packet_mem[14] = 8'h55;
        mixed_packet_mem[15] = 8'h66;
        mixed_packet_mem[16] = 8'h77;
        mixed_packet_mem[17] = 8'h88;
        fork
            send_packet(MIXED_PACKET_BYTES, mixed_packet_mem, 1'b0);
            begin
                for (int i = 0; i < EXPECTED_MIXED_DESCS; i++) begin
                    check_mixed_desc(i, 64'h1122_3344_5566_7788, 8'h00);
                end
            end
        join
        check(packet_count == 32'd3, "rearmed packet count");
        check(descriptor_count == 32'd24, "rearmed descriptor count");
        check(error_count == 32'd1, "sequence rearm does not add a gap error");

        reset_dut();
        build_split_length_packet();
        fork
            send_packet(77, custom_packet_mem, 1'b0);
            begin
                wait_desc("split message 0");
                check(desc_message_length == 16'd41, "split scenario first length");
                check(desc_message_end_byte == 16'd62, "split scenario first end");
                @(posedge clk);
                wait_desc("split message 1");
                check(desc_message_length == 16'd12, "split length completed on next beat");
                check(desc_message_start_byte == 16'd65, "split message start offset");
                check(desc_message_type_valid, "split message type valid");
                check(desc_message_type == "S", "split message type");
                @(posedge clk);
            end
        join

        reset_dut();
        build_dense_system_event_packet();
        fork
            send_packet(DENSE_PACKET_BYTES, custom_packet_mem, 1'b0);
            begin
                for (int i = 0; i < DENSE_SYSTEM_EVENTS; i++) begin
                    check_dense_system_desc(i);
                end
            end
        join
        check(packet_count == 32'd1, "dense system packet count");
        check(descriptor_count == DENSE_SYSTEM_EVENTS[31:0], "dense system descriptor count");
        check(error_count == 32'd0, "dense system error count");

        reset_dut();
        send_truncated_header();
        repeat (4) @(posedge clk);
        check(packet_count == 32'd0, "truncated header does not count packet");
        check(descriptor_count == 32'd0, "truncated header emits no descriptor");
        check(error_count == 32'd1, "truncated header increments error count");

        reset_dut();
        build_bad_frame_packet();
        fork
            send_packet(34, custom_packet_mem, 1'b1);
            begin
                wait_desc("bad frame message");
                check(desc_flags == DESC_FLAG_BAD_FRAME, "bad frame flag propagated");
                check(error_count == 32'd1, "bad frame increments error count");
                @(posedge clk);
            end
        join

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_frontend_tb failed");
    end

endmodule
`default_nettype wire
