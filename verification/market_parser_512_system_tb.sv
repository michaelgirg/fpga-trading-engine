`timescale 1ns / 100ps
`default_nettype none
// =============================================================================
// Module: market_parser_512_system_tb
// =============================================================================
// Test the pre-hardware 512-bit parser system wrapper with AXI-Lite registers.
module market_parser_512_system_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter string   VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam int MIXED_PACKET_BYTES = 276;

    localparam logic [11:0] REG_CONTROL          = 12'h000;
    localparam logic [11:0] REG_STATUS           = 12'h004;
    localparam logic [11:0] REG_BUILD_ID         = 12'h008;
    localparam logic [11:0] REG_PACKET_COUNT     = 12'h010;
    localparam logic [11:0] REG_DESCRIPTOR_COUNT = 12'h014;
    localparam logic [11:0] REG_EVENT_COUNT      = 12'h018;
    localparam logic [11:0] REG_ERROR_COUNT      = 12'h01c;
    localparam logic [11:0] REG_ERROR_FLAGS      = 12'h030;
    localparam logic [11:0] REG_EVENT_FIFO_STAT  = 12'h080;
    localparam logic [11:0] REG_EVENT_FIFO_WR    = 12'h0a4;
    localparam logic [11:0] REG_EVENT_FIFO_RD    = 12'h0a8;
    localparam logic [11:0] REG_FEED_STATUS      = 12'h0b0;
    localparam logic [11:0] REG_FEED_GAP_COUNT   = 12'h0b4;
    localparam logic [11:0] REG_FEED_SUPPRESSED  = 12'h0b8;
    localparam logic [11:0] REG_CMAC_AXIS_FIFO   = 12'h0bc;
    localparam logic [11:0] REG_CMAC_AXIS_ACCEPT = 12'h0c0;
    localparam logic [11:0] REG_CMAC_AXIS_OVFL   = 12'h0c4;
    localparam logic [11:0] REG_CMAC_AXIS_DROP   = 12'h0c8;
    localparam logic [11:0] REG_FEED_IDLE_CYCLES = 12'h0cc;
    localparam logic [11:0] REG_FEED_TIMEOUT_CFG = 12'h0d0;
    localparam logic [11:0] REG_FEED_TIMEOUT_CNT = 12'h0d4;
    localparam logic [11:0] REG_FEED_ACT_REJECT = 12'h0d8;
    localparam logic [11:0] REG_FEED_SESSION_CHANGE = 12'h0dc;
    localparam logic [11:0] REG_FEED_END_OF_SESSION = 12'h0e0;

    typedef logic [7:0] byte_t;

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
    logic        feed_healthy_status;
    logic        feed_rebuilding_status;
    logic        feed_rebuild_ready_status;
    logic [31:0] feed_gap_count_status;
    logic [31:0] feed_suppressed_event_count_status;
    logic [31:0] feed_idle_cycles_status;
    logic [31:0] feed_timeout_count_status;
    logic [31:0] feed_activation_reject_count_status;
    logic [31:0] feed_session_change_count_status;
    logic [31:0] feed_end_of_session_count_status;
    logic        feed_recover_pulse;
    logic        feed_activate_pulse;
    logic [31:0] feed_timeout_cycles_config;
    logic        feed_recover_seen_r;
    logic        feed_activate_seen_r;
    logic [31:0] cmac_axis_accepted_packet_count_status;
    logic [31:0] cmac_axis_overflow_packet_count_status;
    logic [31:0] cmac_axis_dropped_beat_count_status;
    logic [15:0] cmac_axis_fifo_level_status;
    logic [15:0] cmac_axis_fifo_high_watermark_status;

    int passed;
    int failed;

    byte_t mixed_packet_mem[MIXED_PACKET_BYTES];

    market_parser_512_system #(
        .FEED_TIMEOUT_CYCLES_DEFAULT(32'd1234)
    ) DUT (
        .clk                       (clk),
        .rst                       (rst),
        .sequence_rearm            (1'b0),
        .s_axis_rx_tvalid          (s_axis_rx_tvalid),
        .s_axis_rx_tready          (s_axis_rx_tready),
        .s_axis_rx_tdata           (s_axis_rx_tdata),
        .s_axis_rx_tkeep           (s_axis_rx_tkeep),
        .s_axis_rx_tlast           (s_axis_rx_tlast),
        .s_axis_rx_tuser_bad_frame (s_axis_rx_tuser_bad_frame),
        .event_valid               (event_valid),
        .event_ready               (event_ready),
        .event_data                (event_data),
        .event_new_order_ref       (event_new_order_ref),
        .event_keep                (event_keep),
        .event_last                (event_last),
        .session_change_pulse      (),
        .end_of_session_pulse      (),
        .feed_healthy_status       (feed_healthy_status),
        .feed_rebuilding_status    (feed_rebuilding_status),
        .feed_rebuild_ready_status (feed_rebuild_ready_status),
        .feed_gap_count_status     (feed_gap_count_status),
        .feed_suppressed_event_count_status(feed_suppressed_event_count_status),
        .feed_idle_cycles_status   (feed_idle_cycles_status),
        .feed_timeout_count_status (feed_timeout_count_status),
        .feed_activation_reject_count_status(feed_activation_reject_count_status),
        .feed_session_change_count_status(feed_session_change_count_status),
        .feed_end_of_session_count_status(feed_end_of_session_count_status),
        .feed_recover_pulse        (feed_recover_pulse),
        .feed_activate_pulse       (feed_activate_pulse),
        .feed_timeout_cycles_config(feed_timeout_cycles_config),
        .cmac_axis_accepted_packet_count_status(cmac_axis_accepted_packet_count_status),
        .cmac_axis_overflow_packet_count_status(cmac_axis_overflow_packet_count_status),
        .cmac_axis_dropped_beat_count_status(cmac_axis_dropped_beat_count_status),
        .cmac_axis_fifo_level_status(cmac_axis_fifo_level_status),
        .cmac_axis_fifo_high_watermark_status(cmac_axis_fifo_high_watermark_status),
        .s_axi_awaddr              (s_axi_awaddr),
        .s_axi_awvalid             (s_axi_awvalid),
        .s_axi_awready             (s_axi_awready),
        .s_axi_wdata               (s_axi_wdata),
        .s_axi_wstrb               (s_axi_wstrb),
        .s_axi_wvalid              (s_axi_wvalid),
        .s_axi_wready              (s_axi_wready),
        .s_axi_bresp               (s_axi_bresp),
        .s_axi_bvalid              (s_axi_bvalid),
        .s_axi_bready              (s_axi_bready),
        .s_axi_araddr              (s_axi_araddr),
        .s_axi_arvalid             (s_axi_arvalid),
        .s_axi_arready             (s_axi_arready),
        .s_axi_rdata               (s_axi_rdata),
        .s_axi_rresp               (s_axi_rresp),
        .s_axi_rvalid              (s_axi_rvalid),
        .s_axi_rready              (s_axi_rready)
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            feed_recover_seen_r  <= 1'b0;
            feed_activate_seen_r <= 1'b0;
        end else begin
            if (feed_recover_pulse) feed_recover_seen_r <= 1'b1;
            if (feed_activate_pulse) feed_activate_seen_r <= 1'b1;
        end
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
        rst                       = 1'b1;
        s_axis_rx_tvalid          = 1'b0;
        s_axis_rx_tdata           = '0;
        s_axis_rx_tkeep           = '0;
        s_axis_rx_tlast           = 1'b0;
        s_axis_rx_tuser_bad_frame = 1'b0;
        event_ready               = 1'b0;
        feed_healthy_status       = 1'b1;
        feed_rebuilding_status    = 1'b0;
        feed_rebuild_ready_status = 1'b0;
        feed_gap_count_status     = 32'd0;
        feed_suppressed_event_count_status = 32'd0;
        feed_idle_cycles_status = 32'd0;
        feed_timeout_count_status = 32'd0;
        feed_activation_reject_count_status = 32'd0;
        feed_session_change_count_status = 32'd0;
        feed_end_of_session_count_status = 32'd0;
        cmac_axis_accepted_packet_count_status = 32'd0;
        cmac_axis_overflow_packet_count_status = 32'd0;
        cmac_axis_dropped_beat_count_status = 32'd0;
        cmac_axis_fifo_level_status = 16'd0;
        cmac_axis_fifo_high_watermark_status = 16'd0;
        s_axi_awaddr              = '0;
        s_axi_awvalid             = 1'b0;
        s_axi_wdata               = '0;
        s_axi_wstrb               = '0;
        s_axi_wvalid              = 1'b0;
        s_axi_bready              = 1'b1;
        s_axi_araddr              = '0;
        s_axi_arvalid             = 1'b0;
        s_axi_rready              = 1'b0;
        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);
    endtask

    task automatic load_vectors();
        string mixed_path;
        mixed_path = {VECTOR_DIR, "/mixed_messages_packet.hex"};
        $readmemh(mixed_path, mixed_packet_mem);
    endtask

    task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
        @(negedge clk);
        s_axi_awaddr  = addr;
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = data;
        s_axi_wstrb   = 4'hf;
        s_axi_wvalid  = 1'b1;
        while (!(s_axi_awready && s_axi_wready)) @(negedge clk);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_wstrb   = 4'h0;
        while (!s_axi_bvalid) @(negedge clk);
        check(s_axi_bresp == 2'b00, $sformatf("AXI write 0x%03h response OKAY", addr));
        @(negedge clk);
    endtask

    task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
        @(negedge clk);
        s_axi_araddr  = addr;
        s_axi_arvalid = 1'b1;
        s_axi_rready  = 1'b1;
        while (!s_axi_arready) @(negedge clk);
        @(negedge clk);
        s_axi_arvalid = 1'b0;
        while (!s_axi_rvalid) @(negedge clk);
        data = s_axi_rdata;
        check(s_axi_rresp == 2'b00, $sformatf("AXI read 0x%03h response OKAY", addr));
        @(negedge clk);
        s_axi_rready = 1'b0;
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
        s_axis_rx_tvalid = 1'b0;
        s_axis_rx_tdata  = '0;
        s_axis_rx_tkeep  = '0;
        s_axis_rx_tlast  = 1'b0;
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

    task automatic wait_reg_equals(input logic [11:0] addr,
                                   input logic [31:0] expected,
                                   input string msg);
        logic [31:0] value;
        int cycles;
        cycles = 0;
        value = '0;
        while (value != expected && cycles < 500) begin
            axi_read(addr, value);
            cycles++;
        end
        check(value == expected, msg);
    endtask

    initial begin : run_tests
        logic [31:0] value;
        logic [31:0] fifo_status;

        passed = 0;
        failed = 0;
        load_vectors();
        reset_dut();

        $display("\n========================================================");
        $display("MARKET PARSER 512-BIT SYSTEM / AXI-LITE TESTS");
        $display("========================================================");

        axi_read(REG_BUILD_ID, value);
        check(value == 32'h4d50_5253, "build ID register");

        axi_read(REG_STATUS, value);
        check(value[0], "parser enabled after reset");
        check(value[5], "feed health visible in aggregate status");
        axi_read(REG_FEED_STATUS, value);
        check(value == 32'd1, "feed health register");
        axi_read(REG_FEED_TIMEOUT_CFG, value);
        check(value == 32'd1234 && feed_timeout_cycles_config == 32'd1234,
              "feed timeout resets to configured default");
        axi_write(REG_FEED_TIMEOUT_CFG, 32'd64);
        axi_read(REG_FEED_TIMEOUT_CFG, value);
        check(value == 32'd64 && feed_timeout_cycles_config == 32'd64,
              "feed timeout configuration is software writable");

        @(negedge clk);
        cmac_axis_accepted_packet_count_status = 32'd11;
        cmac_axis_overflow_packet_count_status = 32'd2;
        cmac_axis_dropped_beat_count_status = 32'd7;
        cmac_axis_fifo_level_status = 16'd3;
        cmac_axis_fifo_high_watermark_status = 16'd9;
        axi_read(REG_CMAC_AXIS_FIFO, value);
        check(value == {16'd9, 16'd3}, "CMAC AXIS FIFO level and high watermark readable");
        axi_read(REG_CMAC_AXIS_ACCEPT, value);
        check(value == 32'd11, "CMAC AXIS accepted-packet counter readable");
        axi_read(REG_CMAC_AXIS_OVFL, value);
        check(value == 32'd2, "CMAC AXIS overflow counter readable");
        axi_read(REG_CMAC_AXIS_DROP, value);
        check(value == 32'd7, "CMAC AXIS dropped-beat counter readable");
        axi_read(REG_STATUS, value);
        check(value[6], "aggregate status reports CMAC AXIS overflow");

        @(negedge clk);
        feed_idle_cycles_status = 32'd19;
        feed_timeout_count_status = 32'd3;
        axi_read(REG_FEED_IDLE_CYCLES, value);
        check(value == 32'd19, "feed idle-cycle telemetry readable");
        axi_read(REG_FEED_TIMEOUT_CNT, value);
        check(value == 32'd3, "feed timeout counter readable");
        axi_read(REG_STATUS, value);
        check(value[7], "aggregate status reports feed timeout history");

        @(negedge clk);
        feed_healthy_status = 1'b0;
        feed_rebuilding_status = 1'b1;
        feed_rebuild_ready_status = 1'b1;
        feed_gap_count_status = 32'd2;
        feed_suppressed_event_count_status = 32'd7;
        feed_activation_reject_count_status = 32'd2;
        feed_session_change_count_status = 32'd3;
        feed_end_of_session_count_status = 32'd4;
        axi_read(REG_FEED_STATUS, value);
        check(value == 32'h0000_007e,
              "feed status reports rebuild, timeout, activation, session, and end history");
        axi_read(REG_STATUS, value);
        check(value[8] && value[9] && value[10] && value[11],
              "aggregate status reports rebuild, activation, session, and end history");
        axi_read(REG_FEED_GAP_COUNT, value);
        check(value == 32'd2, "feed gap counter readable");
        axi_read(REG_FEED_SUPPRESSED, value);
        check(value == 32'd7, "suppressed-event counter readable");
        axi_read(REG_FEED_ACT_REJECT, value);
        check(value == 32'd2, "activation rejection counter readable");
        axi_read(REG_FEED_SESSION_CHANGE, value);
        check(value == 32'd3, "session-change counter readable");
        axi_read(REG_FEED_END_OF_SESSION, value);
        check(value == 32'd4, "end-of-session counter readable");
        axi_write(REG_CONTROL, 32'h0000_0005);
        repeat (2) @(posedge clk);
        check(feed_recover_seen_r, "control bit 2 emits feed recovery pulse");
        axi_write(REG_CONTROL, 32'h0000_0009);
        repeat (2) @(posedge clk);
        check(feed_activate_seen_r, "control bit 3 emits feed activation pulse");
        axi_read(REG_CONTROL, value);
        check(value == 32'h0000_0001,
              "recovery and activation control bits are self-clearing");

        @(negedge clk);
        feed_healthy_status = 1'b1;
        feed_rebuilding_status = 1'b0;
        feed_rebuild_ready_status = 1'b0;

        axi_write(REG_CONTROL, 32'h0000_0000);
        @(negedge clk);
        s_axis_rx_tvalid = 1'b1;
        s_axis_rx_tdata  = '0;
        s_axis_rx_tkeep  = 64'hffff_ffff_ffff_ffff;
        s_axis_rx_tlast  = 1'b0;
        repeat (3) @(posedge clk);
        check(!s_axis_rx_tready, "disabled parser holds ingress not-ready");
        s_axis_rx_tvalid = 1'b0;
        s_axis_rx_tkeep  = '0;
        axi_read(REG_STATUS, value);
        check(!value[0], "status reflects disabled parser");

        axi_write(REG_CONTROL, 32'h0000_0001);
        axi_read(REG_STATUS, value);
        check(value[0], "status reflects enabled parser");

        send_packet(MIXED_PACKET_BYTES, mixed_packet_mem);
        wait_reg_equals(REG_PACKET_COUNT, 32'd1, "packet counter readable through AXI-Lite");
        wait_reg_equals(REG_DESCRIPTOR_COUNT, 32'd8, "descriptor counter readable through AXI-Lite");
        wait_reg_equals(REG_EVENT_COUNT, 32'd8, "event counter readable through AXI-Lite");
        wait_reg_equals(REG_ERROR_COUNT, 32'd1, "extractor error counter readable through AXI-Lite");
        wait_reg_equals(REG_EVENT_FIFO_WR, 32'd8, "event FIFO write counter readable through AXI-Lite");
        axi_read(REG_EVENT_FIFO_STAT, fifo_status);
        check(fifo_status[31:16] == 16'd8, "event FIFO level in status register");
        check(!fifo_status[0], "event FIFO status not empty");
        axi_read(REG_ERROR_FLAGS, value);
        check(value[1], "sticky extractor error flag set");

        axi_write(REG_CONTROL, 32'h0000_0003);
        repeat (2) @(posedge clk);
        axi_read(REG_PACKET_COUNT, value);
        check(value == 32'd0, "packet counter clears via baseline");
        axi_read(REG_EVENT_COUNT, value);
        check(value == 32'd0, "event counter clears via baseline");
        axi_read(REG_ERROR_COUNT, value);
        check(value == 32'd0, "error counter clears via baseline");
        axi_read(REG_EVENT_FIFO_WR, value);
        check(value == 32'd0, "FIFO write counter clears via baseline");
        axi_read(REG_FEED_GAP_COUNT, value);
        check(value == 32'd0, "feed gap counter clears via baseline");
        axi_read(REG_FEED_SUPPRESSED, value);
        check(value == 32'd0, "suppressed-event counter clears via baseline");
        axi_read(REG_FEED_TIMEOUT_CNT, value);
        check(value == 32'd0, "feed timeout counter clears via baseline");
        axi_read(REG_FEED_ACT_REJECT, value);
        check(value == 32'd0, "activation rejection counter clears via baseline");
        axi_read(REG_FEED_SESSION_CHANGE, value);
        check(value == 32'd0, "session-change counter clears via baseline");
        axi_read(REG_FEED_END_OF_SESSION, value);
        check(value == 32'd0, "end-of-session counter clears via baseline");
        axi_read(REG_CMAC_AXIS_ACCEPT, value);
        check(value == 32'd0, "CMAC AXIS accepted counter clears via baseline");
        axi_read(REG_CMAC_AXIS_OVFL, value);
        check(value == 32'd0, "CMAC AXIS overflow counter clears via baseline");
        axi_read(REG_CMAC_AXIS_DROP, value);
        check(value == 32'd0, "CMAC AXIS dropped-beat counter clears via baseline");
        axi_read(REG_STATUS, value);
        check(!value[7] && !value[6],
              "counter clear removes aggregate timeout and overflow status");
        axi_read(REG_ERROR_FLAGS, value);
        check(value == 32'd0, "sticky error flags clear with counter clear");
        axi_read(REG_STATUS, value);
        check(value[0], "clear preserves parser enable bit");

        event_ready = 1'b1;
        wait_reg_equals(REG_EVENT_FIFO_RD, 32'd8, "FIFO read counter increments while draining");
        axi_read(REG_EVENT_FIFO_STAT, fifo_status);
        check(fifo_status[31:16] == 16'd0, "event FIFO level returns to zero after drain");
        check(fifo_status[0], "event FIFO empty after drain");
        event_ready = 1'b0;

        $display("========================================================");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("========================================================\n");

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_512_system_tb failed");
    end

endmodule
`default_nettype wire
