`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_512_pipeline_fifo_tb
// =============================================================================
// Test the event FIFO boundary after the 512-bit parallel event pipeline.
module market_parser_512_pipeline_fifo_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int EXPECTED_EVENTS = 10;
    localparam int MIXED_EVENTS = 8;
    localparam int FIFO_EVENTS = 16;

    typedef logic [7:0] byte_t;
    typedef logic [255:0] event_word_t;

    logic clk = 1'b0;
    logic rst;

    logic         s_axis_rx_tvalid;
    logic         s_axis_rx_tready;
    logic [511:0] s_axis_rx_tdata;
    logic [ 63:0] s_axis_rx_tkeep;
    logic         s_axis_rx_tlast;
    logic         s_axis_rx_tuser_bad_frame;

    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;
    logic [ 31:0] event_keep;
    logic         event_last;

    logic [31:0] packet_count;
    logic [31:0] descriptor_count;
    logic [31:0] event_count;
    logic [31:0] extractor_error_count;
    logic [31:0] bad_frame_count;
    logic [15:0] event_fifo_level;
    logic [31:0] event_fifo_write_count;
    logic [31:0] event_fifo_read_count;
    logic [31:0] event_fifo_backpressure_count;

    int passed;
    int failed;

    byte_t       mixed_packet_mem  [MIXED_PACKET_BYTES];
    event_word_t expected_event_mem[EXPECTED_EVENTS];

    market_parser_512_pipeline_fifo #(
        .EVENT_FIFO_DEPTH(FIFO_EVENTS)
    ) DUT (
        .clk                            (clk),
        .rst                            (rst),
        .s_axis_rx_tvalid               (s_axis_rx_tvalid),
        .s_axis_rx_tready               (s_axis_rx_tready),
        .s_axis_rx_tdata                (s_axis_rx_tdata),
        .s_axis_rx_tkeep                (s_axis_rx_tkeep),
        .s_axis_rx_tlast                (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame      (s_axis_rx_tuser_bad_frame),
        .event_valid                    (event_valid),
        .event_ready                    (event_ready),
        .event_data                     (event_data),
        .event_keep                     (event_keep),
        .event_last                     (event_last),
        .packet_count                   (packet_count),
        .descriptor_count               (descriptor_count),
        .event_count                    (event_count),
        .extractor_error_count          (extractor_error_count),
        .bad_frame_count                (bad_frame_count),
        .event_fifo_level               (event_fifo_level),
        .event_fifo_write_count         (event_fifo_write_count),
        .event_fifo_read_count          (event_fifo_read_count),
        .event_fifo_backpressure_count  (event_fifo_backpressure_count)
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic reset_dut();
        rst                       = 1'b1;
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
        event_ready               = 1'b0;
        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);
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
        string expected_path;
        mixed_path    = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        expected_path = {VECTOR_DIR, "/expected_events.hex"};
        $readmemh(mixed_path, mixed_packet_mem);
        $readmemh(expected_path, expected_event_mem);
    endtask

    task automatic send_beat(input logic [511:0] beat_data,
                             input logic [ 63:0] beat_keep,
                             input bit           beat_last);
        @(negedge clk);
        s_axis_rx_tvalid          = 1'b1;
        s_axis_rx_tdata           = beat_data;
        s_axis_rx_tkeep           = beat_keep;
        s_axis_rx_tlast           = beat_last;
        s_axis_rx_tuser_bad_frame = 1'b0;
        while (!s_axis_rx_tready) @(negedge clk);
        @(negedge clk);
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
    endtask

    task automatic send_packet(input int packet_bytes, input byte_t packet_mem[]);
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
            send_beat(beat_data, beat_keep, offset + beat_bytes >= packet_bytes);
            offset += beat_bytes;
        end
    endtask

    task automatic wait_fifo_level(input int expected_level, input string msg);
        int cycles;
        cycles = 0;
        while (event_fifo_level != expected_level[15:0] && cycles < 600) begin
            @(posedge clk);
            cycles++;
        end
        check(event_fifo_level == expected_level[15:0], msg);
    endtask

    task automatic wait_event(input string msg);
        int cycles;
        cycles = 0;
        while (!event_valid && cycles < 200) begin
            @(posedge clk);
            cycles++;
        end
        check(event_valid, {msg, " valid"});
    endtask

    task automatic check_and_pop_event(input int packet_idx, input int event_idx);
        int expected_idx;
        expected_idx = event_idx + 2;
        wait_event($sformatf("packet %0d event %0d", packet_idx, event_idx));
        check(event_keep == 32'hffff_ffff,
              $sformatf("packet %0d event %0d keep", packet_idx, event_idx));
        check(event_data == expected_event_mem[expected_idx],
              $sformatf("packet %0d event %0d data", packet_idx, event_idx));
        check(event_last == (event_idx == MIXED_EVENTS - 1),
              $sformatf("packet %0d event %0d last", packet_idx, event_idx));
        @(negedge clk);
        event_ready = 1'b1;
        @(negedge clk);
        event_ready = 1'b0;
    endtask

    initial begin : run_tests
        passed = 0;
        failed = 0;
        load_vectors();
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER 512-BIT PIPELINE FIFO TESTS");
        $display("========================================================");

        send_packet(MIXED_PACKET_BYTES, mixed_packet_mem);
        wait_fifo_level(MIXED_EVENTS, "first packet events queued while output stalled");
        check(event_valid, "fifo presents first queued event while output stalled");
        check(packet_count == 32'd1, "first packet counted");
        check(event_fifo_write_count == 32'd8, "first packet fifo write count");
        check(event_fifo_read_count == 32'd0, "no fifo reads while output stalled");

        send_packet(MIXED_PACKET_BYTES, mixed_packet_mem);
        wait_fifo_level(FIFO_EVENTS, "two packets fill event fifo while output remains stalled");
        check(packet_count == 32'd2, "two packets counted");
        check(descriptor_count == 32'd16, "two packet descriptor count");
        check(event_count == 32'd16, "two packet parser event count");
        check(event_fifo_write_count == 32'd16, "two packet fifo write count");
        check(event_fifo_backpressure_count == 32'd0, "fifo did not backpressure before becoming full");

        for (int pkt = 0; pkt < 2; pkt++) begin
            for (int evt = 0; evt < MIXED_EVENTS; evt++) begin
                check_and_pop_event(pkt, evt);
            end
        end

        repeat (3) @(posedge clk);
        check(event_fifo_level == 16'd0, "fifo empty after draining all events");
        check(event_fifo_read_count == 32'd16, "fifo read count after drain");
        check(!event_valid, "event valid drops after fifo drains");
        check(extractor_error_count == 32'd2, "unknown event counted once per mixed packet");
        check(bad_frame_count == 32'd0, "no bad frames in fifo test");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_pipeline_fifo_tb failed");
    end

endmodule
`default_nettype wire
