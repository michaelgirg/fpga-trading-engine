`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_100g_cmac_system_tb
// =============================================================================
// Smoke test for the CMAC-facing shell that strips Ethernet/IPv4/UDP headers
// before driving the 512-bit parser system.
module market_parser_100g_cmac_system_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [15:0] FEED_UDP_PORT = 16'd5000;
    localparam int HEADER_BYTES = 42;
    localparam int MIXED_PACKET_BYTES = 276;
    localparam int RAW_PACKET_BYTES = HEADER_BYTES + MIXED_PACKET_BYTES;
    localparam int EXPECTED_EVENTS = 10;
    localparam int RX_BYTES_PER_BEAT = 64;
    localparam int EXPECTED_RAW_BEATS = (RAW_PACKET_BYTES + RX_BYTES_PER_BEAT - 1) / RX_BYTES_PER_BEAT;

    typedef logic [7:0] byte_t;
    typedef logic [255:0] event_word_t;

    logic clk = 1'b0;
    logic rst;

    logic         s_axis_cmac_rx_tvalid;
    logic         s_axis_cmac_rx_tready;
    logic [511:0] s_axis_cmac_rx_tdata;
    logic [ 63:0] s_axis_cmac_rx_tkeep;
    logic         s_axis_cmac_rx_tlast;
    logic         s_axis_cmac_rx_tuser_bad_frame;

    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;
    logic [ 63:0] event_new_order_ref;
    logic [ 31:0] event_keep;
    logic         event_last;

    logic [11:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [ 3:0] s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [ 1:0] s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [11:0] s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [ 1:0] s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    logic [31:0] cmac_accepted_frame_count;
    logic [31:0] cmac_dropped_frame_count;
    logic [31:0] cmac_header_error_count;
    logic [31:0] cmac_payload_packet_count;
    logic [15:0] cmac_payload_fifo_level;
    logic        feed_recover_pulse;
    logic        feed_activate_pulse;

    int passed;
    int failed;
    int ingress_stall_cycles_seen;
    int raw_beat_count;

    byte_t       mixed_packet_mem  [MIXED_PACKET_BYTES];
    byte_t       raw_packet_mem    [RAW_PACKET_BYTES];
    event_word_t expected_event_mem[EXPECTED_EVENTS];

    market_parser_100g_cmac_system #(
        .FEED_UDP_PORT   (FEED_UDP_PORT),
        .STRIP_FIFO_DEPTH(8)
    ) DUT (
        .clk                            (clk),
        .rst                            (rst),
        .sequence_rearm                 (1'b0),
        .s_axis_cmac_rx_tvalid          (s_axis_cmac_rx_tvalid),
        .s_axis_cmac_rx_tready          (s_axis_cmac_rx_tready),
        .s_axis_cmac_rx_tdata           (s_axis_cmac_rx_tdata),
        .s_axis_cmac_rx_tkeep           (s_axis_cmac_rx_tkeep),
        .s_axis_cmac_rx_tlast           (s_axis_cmac_rx_tlast),
        .s_axis_cmac_rx_tuser_bad_frame (s_axis_cmac_rx_tuser_bad_frame),
        .event_valid                    (event_valid),
        .event_ready                    (event_ready),
        .event_data                     (event_data),
        .event_new_order_ref            (event_new_order_ref),
        .event_keep                     (event_keep),
        .event_last                     (event_last),
        .session_change_pulse           (),
        .feed_healthy_status            (1'b1),
        .feed_rebuilding_status         (1'b0),
        .feed_rebuild_ready_status      (1'b0),
        .feed_gap_count_status          (32'd0),
        .feed_suppressed_event_count_status(32'd0),
        .feed_idle_cycles_status        (32'd0),
        .feed_timeout_count_status      (32'd0),
        .feed_activation_reject_count_status(32'd0),
        .feed_session_change_count_status(32'd0),
        .feed_recover_pulse             (feed_recover_pulse),
        .feed_activate_pulse            (feed_activate_pulse),
        .feed_timeout_cycles_config     (),
        .cmac_axis_accepted_packet_count_status(32'd0),
        .cmac_axis_overflow_packet_count_status(32'd0),
        .cmac_axis_dropped_beat_count_status(32'd0),
        .cmac_axis_fifo_level_status    (16'd0),
        .cmac_axis_fifo_high_watermark_status(16'd0),
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
        .cmac_accepted_frame_count      (cmac_accepted_frame_count),
        .cmac_dropped_frame_count       (cmac_dropped_frame_count),
        .cmac_header_error_count        (cmac_header_error_count),
        .cmac_payload_packet_count      (cmac_payload_packet_count),
        .cmac_payload_fifo_level        (cmac_payload_fifo_level)
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic check(input bit condition, input string msg);
        if (condition) begin
            passed++;
            $display("PASS: %s", msg);
        end else begin
            failed++;
            $error("FAIL: %s", msg);
        end
    endtask

    task automatic reset_dut();
        rst                            = 1'b1;
        s_axis_cmac_rx_tvalid          = 1'b0;
        s_axis_cmac_rx_tdata           = '0;
        s_axis_cmac_rx_tkeep           = '0;
        s_axis_cmac_rx_tlast           = 1'b0;
        s_axis_cmac_rx_tuser_bad_frame = 1'b0;
        event_ready                    = 1'b0;
        s_axi_awaddr                   = '0;
        s_axi_awvalid                  = 1'b0;
        s_axi_wdata                    = '0;
        s_axi_wstrb                    = '0;
        s_axi_wvalid                   = 1'b0;
        s_axi_bready                   = 1'b1;
        s_axi_araddr                   = '0;
        s_axi_arvalid                  = 1'b0;
        s_axi_rready                   = 1'b0;
        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);
    endtask

    task automatic load_vectors();
        string mixed_path;
        string expected_path;
        mixed_path    = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        expected_path = {VECTOR_DIR, "/expected_events.hex"};
        $readmemh(mixed_path, mixed_packet_mem);
        $readmemh(expected_path, expected_event_mem);
    endtask

    task automatic build_raw_packet(input bit valid_feed_port);
        logic [15:0] ip_total_length;
        logic [15:0] udp_length;
        logic [15:0] dst_port;

        ip_total_length = 16'(20 + 8 + MIXED_PACKET_BYTES);
        udp_length      = 16'(8 + MIXED_PACKET_BYTES);
        dst_port        = valid_feed_port ? FEED_UDP_PORT : 16'd5001;

        for (int i = 0; i < RAW_PACKET_BYTES; i++) begin
            raw_packet_mem[i] = 8'h00;
        end

        raw_packet_mem[0]  = 8'h01;
        raw_packet_mem[1]  = 8'h02;
        raw_packet_mem[2]  = 8'h03;
        raw_packet_mem[3]  = 8'h04;
        raw_packet_mem[4]  = 8'h05;
        raw_packet_mem[5]  = 8'h06;
        raw_packet_mem[6]  = 8'h0a;
        raw_packet_mem[7]  = 8'h0b;
        raw_packet_mem[8]  = 8'h0c;
        raw_packet_mem[9]  = 8'h0d;
        raw_packet_mem[10] = 8'h0e;
        raw_packet_mem[11] = 8'h0f;
        raw_packet_mem[12] = 8'h08;
        raw_packet_mem[13] = 8'h00;

        raw_packet_mem[14] = 8'h45;
        raw_packet_mem[15] = 8'h00;
        raw_packet_mem[16] = ip_total_length[15:8];
        raw_packet_mem[17] = ip_total_length[7:0];
        raw_packet_mem[18] = 8'h00;
        raw_packet_mem[19] = 8'h01;
        raw_packet_mem[20] = 8'h40;
        raw_packet_mem[21] = 8'h00;
        raw_packet_mem[22] = 8'h40;
        raw_packet_mem[23] = 8'h11;
        raw_packet_mem[24] = 8'h00;
        raw_packet_mem[25] = 8'h00;
        raw_packet_mem[26] = 8'h0a;
        raw_packet_mem[27] = 8'h00;
        raw_packet_mem[28] = 8'h00;
        raw_packet_mem[29] = 8'h01;
        raw_packet_mem[30] = 8'hef;
        raw_packet_mem[31] = 8'hc0;
        raw_packet_mem[32] = 8'h00;
        raw_packet_mem[33] = 8'h01;

        raw_packet_mem[34] = 8'h9c;
        raw_packet_mem[35] = 8'h40;
        raw_packet_mem[36] = dst_port[15:8];
        raw_packet_mem[37] = dst_port[7:0];
        raw_packet_mem[38] = udp_length[15:8];
        raw_packet_mem[39] = udp_length[7:0];
        raw_packet_mem[40] = 8'h00;
        raw_packet_mem[41] = 8'h00;

        for (int i = 0; i < MIXED_PACKET_BYTES; i++) begin
            raw_packet_mem[HEADER_BYTES + i] = mixed_packet_mem[i];
        end
    endtask

    task automatic send_packet_100g_burst(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int bytes_left;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [ 63:0] beat_keep;

        offset = 0;
        @(negedge clk);
        while (offset < packet_bytes) begin
            bytes_left = packet_bytes - offset;
            beat_bytes = (bytes_left >= RX_BYTES_PER_BEAT) ? RX_BYTES_PER_BEAT : bytes_left;
            beat_data  = '0;
            beat_keep  = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                beat_keep[lane]        = 1'b1;
            end

            s_axis_cmac_rx_tvalid          = 1'b1;
            s_axis_cmac_rx_tdata           = beat_data;
            s_axis_cmac_rx_tkeep           = beat_keep;
            s_axis_cmac_rx_tlast           = (offset + beat_bytes >= packet_bytes);
            s_axis_cmac_rx_tuser_bad_frame = 1'b0;
            while (!s_axis_cmac_rx_tready) begin
                ingress_stall_cycles_seen++;
                @(negedge clk);
            end
            @(negedge clk);
            offset += beat_bytes;
            raw_beat_count++;
        end
        s_axis_cmac_rx_tvalid          = 1'b0;
        s_axis_cmac_rx_tdata           = '0;
        s_axis_cmac_rx_tkeep           = '0;
        s_axis_cmac_rx_tlast           = 1'b0;
        s_axis_cmac_rx_tuser_bad_frame = 1'b0;
    endtask

    task automatic wait_for_event(output logic [255:0] observed_event,
                                  input string msg);
        int cycles;
        cycles = 0;
        event_ready = 1'b0;
        while (!event_valid && cycles < 1500) begin
            @(posedge clk);
            cycles++;
        end
        check(event_valid, {msg, " became valid"});
        observed_event = event_data;
        check(event_keep == 32'hffff_ffff, {msg, " keep is full"});
        event_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        event_ready = 1'b0;
    endtask

    initial begin : run_tests
        logic [255:0] observed_event;

        passed = 0;
        failed = 0;
        ingress_stall_cycles_seen = 0;
        raw_beat_count = 0;
        reset_dut();
        load_vectors();

        $display("\n========================================================");
        $display("MARKET PARSER 100G CMAC SYSTEM TESTS");
        $display("========================================================");

        build_raw_packet(1'b1);
        fork
            send_packet_100g_burst(RAW_PACKET_BYTES, raw_packet_mem);
            begin
                for (int i = 2; i < EXPECTED_EVENTS; i++) begin
                    wait_for_event(observed_event, $sformatf("CMAC shell event %0d", i - 2));
                    check(observed_event == expected_event_mem[i],
                          $sformatf("CMAC shell event %0d matches generated vector", i - 2));
                end
            end
        join

        check(ingress_stall_cycles_seen == 0, "CMAC shell accepts valid frame with no input stalls");
        check(raw_beat_count == EXPECTED_RAW_BEATS, "CMAC shell raw beat count");
        check(cmac_accepted_frame_count == 32'd1, "CMAC shell accepted-frame counter");
        check(cmac_payload_packet_count == 32'd1, "CMAC shell payload-packet counter");
        check(cmac_dropped_frame_count == 32'd0, "CMAC shell drop counter stays zero");
        check(cmac_header_error_count == 32'd0, "CMAC shell header-error counter stays zero");

        build_raw_packet(1'b0);
        send_packet_100g_burst(RAW_PACKET_BYTES, raw_packet_mem);
        repeat (20) @(posedge clk);
        check(!event_valid, "wrong UDP port emits no parser event");
        check(cmac_accepted_frame_count == 32'd1, "wrong-port frame does not increment accepted counter");
        check(cmac_payload_packet_count == 32'd1, "wrong-port frame does not increment payload counter");
        check(cmac_dropped_frame_count == 32'd1, "wrong-port frame increments drop counter");
        check(cmac_header_error_count == 32'd1, "wrong-port frame increments header-error counter");
        check(cmac_payload_fifo_level == 16'd0, "CMAC shell payload FIFO drains");

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_100g_cmac_system_tb failed");
    end

endmodule
`default_nettype wire
