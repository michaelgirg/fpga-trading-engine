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
    logic [ 63:0] event_new_order_ref;
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
    logic [63:0] next_packet_sequence;

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
        .event_new_order_ref            (event_new_order_ref),
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
        next_packet_sequence      = 64'd5;
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
                if (offset + lane >= 10 && offset + lane < 18) begin
                    beat_data[lane*8 +: 8] =
                        next_packet_sequence[63 - ((offset + lane - 10) * 8) -: 8];
                end else begin
                    beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                end
                beat_keep[lane] = 1'b1;
            end
            send_beat(beat_data, beat_keep, offset + beat_bytes >= packet_bytes);
            offset += beat_bytes;
        end
        next_packet_sequence = next_packet_sequence + 64'd8;
    endtask

    function automatic logic [511:0] make_mixed_beat_data(input int offset,
                                                           input logic [63:0] packet_sequence);
        logic [511:0] beat_data;
        int bytes_left;
        int beat_bytes;

        bytes_left = MIXED_PACKET_BYTES - offset;
        beat_bytes = (bytes_left >= 64) ? 64 : bytes_left;
        beat_data = '0;
        for (int lane = 0; lane < beat_bytes; lane++) begin
            if (offset + lane >= 10 && offset + lane < 18) begin
                beat_data[lane*8 +: 8] =
                    packet_sequence[63 - ((offset + lane - 10) * 8) -: 8];
            end else begin
                beat_data[lane*8 +: 8] = mixed_packet_mem[offset + lane];
            end
        end
        make_mixed_beat_data = beat_data;
    endfunction

    function automatic logic [63:0] make_mixed_beat_keep(input int offset);
        logic [63:0] beat_keep;
        int bytes_left;
        int beat_bytes;

        bytes_left = MIXED_PACKET_BYTES - offset;
        beat_bytes = (bytes_left >= 64) ? 64 : bytes_left;
        beat_keep = '0;
        for (int lane = 0; lane < beat_bytes; lane++) begin
            beat_keep[lane] = 1'b1;
        end
        make_mixed_beat_keep = beat_keep;
    endfunction

    task automatic send_mixed_packets_no_idle(input int packets);
        int packet_idx;
        int offset;
        int beat_bytes;
        int stall_cycles;
        logic [63:0] packet_sequence;

        packet_idx = 0;
        offset = 0;
        stall_cycles = 0;
        packet_sequence = next_packet_sequence;
        @(negedge clk);
        while (packet_idx < packets) begin
            beat_bytes = ((MIXED_PACKET_BYTES - offset) >= 64) ? 64 : (MIXED_PACKET_BYTES - offset);
            s_axis_rx_tvalid          = 1'b1;
            s_axis_rx_tdata           = make_mixed_beat_data(offset, packet_sequence);
            s_axis_rx_tkeep           = make_mixed_beat_keep(offset);
            s_axis_rx_tlast           = (offset + beat_bytes >= MIXED_PACKET_BYTES);
            s_axis_rx_tuser_bad_frame = 1'b0;

            @(posedge clk);
            if (s_axis_rx_tready) begin
                stall_cycles = 0;
                offset += beat_bytes;
                if (offset >= MIXED_PACKET_BYTES) begin
                    offset = 0;
                    packet_idx++;
                    packet_sequence = packet_sequence + 64'd8;
                end
            end else begin
                stall_cycles++;
                if (stall_cycles > 2000) begin
                    check(1'b0, "no-idle source did not stall forever");
                    packet_idx = packets;
                end
            end
            @(negedge clk);
        end

        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
        next_packet_sequence      = packet_sequence;
    endtask

    task automatic collect_events_with_random_ready(input int packets,
                                                    input int expected_events,
                                                    input int seed);
        int received;
        int cycles;
        int event_idx;
        int packet_idx;
        int expected_idx;
        bit ready_bit;

        received = 0;
        cycles = 0;
        while (received < expected_events && cycles < 6000) begin
            ready_bit = (($urandom(seed + cycles) % 4) != 0);
            @(negedge clk);
            event_ready = ready_bit;
            @(posedge clk);
            if (event_valid && event_ready) begin
                event_idx = received % MIXED_EVENTS;
                packet_idx = received / MIXED_EVENTS;
                expected_idx = event_idx + 2;
                check(event_keep == 32'hffff_ffff,
                      $sformatf("random packet %0d event %0d keep", packet_idx, event_idx));
                check(event_data == expected_event_mem[expected_idx],
                      $sformatf("random packet %0d event %0d data", packet_idx, event_idx));
                check(event_new_order_ref == ((event_idx == 5) ? 64'h9999_AAAA_BBBB_CCCC : 64'd0),
                      $sformatf("random packet %0d event %0d replacement reference", packet_idx, event_idx));
                check(event_last == (event_idx == MIXED_EVENTS - 1),
                      $sformatf("random packet %0d event %0d last", packet_idx, event_idx));
                received++;
            end
            cycles++;
        end
        @(negedge clk);
        event_ready = 1'b0;
        check(received == expected_events, "random-ready collector received all events");
        check((received / MIXED_EVENTS) == packets, "random-ready collector covered all packets");
    endtask

    task automatic check_no_idle_back_to_back_random_ready(input int packets);
        fork
            send_mixed_packets_no_idle(packets);
            collect_events_with_random_ready(packets, packets * MIXED_EVENTS, 32'h5120_0001);
        join

        repeat (8) @(posedge clk);
        check(packet_count == 32'(packets), "no-idle packet count");
        check(descriptor_count == 32'(packets * MIXED_EVENTS), "no-idle descriptor count");
        check(event_count == 32'(packets * MIXED_EVENTS), "no-idle parser event count");
        check(event_fifo_write_count == 32'(packets * MIXED_EVENTS), "no-idle FIFO write count");
        check(event_fifo_read_count == 32'(packets * MIXED_EVENTS), "no-idle FIFO read count");
        check(event_fifo_level == 16'd0, "no-idle FIFO drains to empty");
        check(extractor_error_count == 32'(packets), "no-idle unknown-message count");
        check(bad_frame_count == 32'd0, "no-idle bad-frame count");
    endtask

    task automatic check_fifo_pressure_with_third_packet();
        int pressure_start;

        event_ready = 1'b0;
        send_mixed_packets_no_idle(2);
        wait_fifo_level(FIFO_EVENTS, "pressure setup fills event FIFO");
        check(event_valid, "pressure setup exposes first queued event");
        pressure_start = int'(event_fifo_backpressure_count);

        fork
            send_mixed_packets_no_idle(1);
            begin
                repeat (40) @(posedge clk);
                check(event_fifo_backpressure_count > 32'(pressure_start),
                      "full FIFO increments backpressure counter");
                collect_events_with_random_ready(3, 3 * MIXED_EVENTS, 32'h5120_0002);
            end
        join

        repeat (8) @(posedge clk);
        check(packet_count == 32'd3, "pressure packet count");
        check(descriptor_count == 32'd24, "pressure descriptor count");
        check(event_count == 32'd24, "pressure parser event count");
        check(event_fifo_write_count == 32'd24, "pressure FIFO write count");
        check(event_fifo_read_count == 32'd24, "pressure FIFO read count");
        check(event_fifo_backpressure_count > 32'(pressure_start),
              "pressure backpressure counter remains nonzero");
        check(event_fifo_level == 16'd0, "pressure FIFO drains to empty");
        check(extractor_error_count == 32'd3, "pressure unknown-message count");
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
        check(event_new_order_ref == ((event_idx == 5) ? 64'h9999_AAAA_BBBB_CCCC : 64'd0),
              $sformatf("packet %0d event %0d replacement reference", packet_idx, event_idx));
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

        reset_dut();
        check_no_idle_back_to_back_random_ready(3);

        reset_dut();
        check_fifo_pressure_with_third_packet();

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_pipeline_fifo_tb failed");
    end

endmodule
`default_nettype wire
