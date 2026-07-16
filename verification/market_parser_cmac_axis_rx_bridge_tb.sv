`default_nettype none
// =============================================================================
// Module: market_parser_cmac_axis_rx_bridge_tb
// =============================================================================
module market_parser_cmac_axis_rx_bridge_tb;
    localparam int DATA_WIDTH = 64;
    localparam int KEEP_WIDTH = DATA_WIDTH / 8;
    localparam int FIFO_DEPTH = 4;

    logic                  clk;
    logic                  rst;
    logic                  rx_axis_tvalid;
    logic [DATA_WIDTH-1:0] rx_axis_tdata;
    logic [KEEP_WIDTH-1:0] rx_axis_tkeep;
    logic                  rx_axis_tlast;
    logic                  rx_axis_tuser;
    logic                  m_axis_tvalid;
    logic                  m_axis_tready;
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic [KEEP_WIDTH-1:0] m_axis_tkeep;
    logic                  m_axis_tlast;
    logic                  m_axis_tuser_bad_frame;
    logic [31:0]           accepted_packet_count;
    logic [31:0]           overflow_packet_count;
    logic [31:0]           dropped_beat_count;
    logic [15:0]           fifo_level;
    logic [15:0]           fifo_high_watermark;
    logic [15:0]           buffered_packet_count;
    int                    failed;

    market_parser_cmac_axis_rx_bridge #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk                  (clk),
        .rst                  (rst),
        .rx_axis_tvalid       (rx_axis_tvalid),
        .rx_axis_tdata        (rx_axis_tdata),
        .rx_axis_tkeep        (rx_axis_tkeep),
        .rx_axis_tlast        (rx_axis_tlast),
        .rx_axis_tuser        (rx_axis_tuser),
        .m_axis_tvalid        (m_axis_tvalid),
        .m_axis_tready        (m_axis_tready),
        .m_axis_tdata         (m_axis_tdata),
        .m_axis_tkeep         (m_axis_tkeep),
        .m_axis_tlast         (m_axis_tlast),
        .m_axis_tuser_bad_frame(m_axis_tuser_bad_frame),
        .accepted_packet_count(accepted_packet_count),
        .overflow_packet_count(overflow_packet_count),
        .dropped_beat_count   (dropped_beat_count),
        .fifo_level           (fifo_level),
        .fifo_high_watermark  (fifo_high_watermark),
        .buffered_packet_count(buffered_packet_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            failed++;
            $display("FAIL: %s", message);
        end else begin
            $display("PASS: %s", message);
        end
    endtask

    task automatic reset_dut();
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata  = '0;
        rx_axis_tkeep  = '0;
        rx_axis_tlast  = 1'b0;
        rx_axis_tuser  = 1'b0;
        m_axis_tready  = 1'b0;
        rst            = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);
    endtask

    task automatic send_beat(input logic [DATA_WIDTH-1:0] data,
                             input logic                  last,
                             input logic                  user);
        @(negedge clk);
        rx_axis_tvalid = 1'b1;
        rx_axis_tdata  = data;
        rx_axis_tkeep  = '1;
        rx_axis_tlast  = last;
        rx_axis_tuser  = user;
        @(negedge clk);
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata  = '0;
        rx_axis_tkeep  = '0;
        rx_axis_tlast  = 1'b0;
        rx_axis_tuser  = 1'b0;
    endtask

    task automatic send_packet(input int beats, input logic [DATA_WIDTH-1:0] base);
        for (int idx = 0; idx < beats; idx++) begin
            send_beat(base + DATA_WIDTH'(idx), idx == beats - 1, 1'b0);
        end
    endtask

    task automatic send_packet_contiguous(input int beats,
                                          input logic [DATA_WIDTH-1:0] base);
        @(negedge clk);
        for (int idx = 0; idx < beats; idx++) begin
            rx_axis_tvalid = 1'b1;
            rx_axis_tdata  = base + DATA_WIDTH'(idx);
            rx_axis_tkeep  = '1;
            rx_axis_tlast  = (idx == beats - 1);
            rx_axis_tuser  = 1'b0;
            @(negedge clk);
        end
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata  = '0;
        rx_axis_tkeep  = '0;
        rx_axis_tlast  = 1'b0;
        rx_axis_tuser  = 1'b0;
    endtask

    task automatic expect_beat(input logic [DATA_WIDTH-1:0] data,
                               input logic                  last,
                               input logic                  user);
        int timeout;
        timeout = 0;
        while (!m_axis_tvalid && timeout < 20) begin
            @(negedge clk);
            timeout++;
        end
        check(m_axis_tvalid, "output beat becomes valid");
        check(m_axis_tdata == data, "output beat data matches");
        check(m_axis_tkeep == '1, "output keep is full");
        check(m_axis_tlast == last, "output last matches");
        check(m_axis_tuser_bad_frame == user, "output user matches");
        m_axis_tready = 1'b1;
        @(negedge clk);
        m_axis_tready = 1'b0;
    endtask

    initial begin
        failed = 0;
        reset_dut();

        send_packet(3, 64'h1000);
        repeat (2) @(negedge clk);
        check(accepted_packet_count == 32'd1, "one complete packet accepted");
        check(buffered_packet_count == 16'd1, "one complete packet buffered");
        check(fifo_level == 16'd3, "three packet beats buffered");
        check(fifo_high_watermark == 16'd3, "FIFO high watermark records occupancy");
        expect_beat(64'h1000, 1'b0, 1'b0);
        expect_beat(64'h1001, 1'b0, 1'b0);
        expect_beat(64'h1002, 1'b1, 1'b0);
        repeat (2) @(negedge clk);
        check(buffered_packet_count == 16'd0, "buffered packet count drains");
        check(fifo_level == 16'd0, "FIFO drains after packet readout");

        reset_dut();
        send_packet(5, 64'h2000);
        repeat (4) @(negedge clk);
        check(!m_axis_tvalid, "overflowed packet is not emitted");
        check(accepted_packet_count == 32'd0, "overflowed packet is not accepted");
        check(overflow_packet_count == 32'd1, "overflow packet counted");
        check(dropped_beat_count == 32'd5, "overflow dropped beats counted");
        check(buffered_packet_count == 16'd0, "no complete packet after overflow");
        check(fifo_level == 16'd0, "partial packet rolled back on overflow");
        check(fifo_high_watermark == 16'd4, "overflow run records full FIFO watermark");

        send_packet(1, 64'h3000);
        repeat (2) @(negedge clk);
        check(accepted_packet_count == 32'd1, "bridge recovers after overflow");
        expect_beat(64'h3000, 1'b1, 1'b0);

        reset_dut();
        send_packet_contiguous(4, 64'h4000);
        repeat (2) @(negedge clk);
        check(accepted_packet_count == 32'd1, "full-depth contiguous packet accepted");
        check(overflow_packet_count == 32'd0, "full-depth packet does not overflow");
        check(fifo_high_watermark == 16'd4, "contiguous packet reaches full-depth watermark");
        for (int idx = 0; idx < 4; idx++) begin
            expect_beat(64'h4000 + 64'(idx), idx == 3, 1'b0);
        end

        reset_dut();
        send_packet_contiguous(2, 64'h5000);
        send_packet_contiguous(3, 64'h6000);
        repeat (2) @(negedge clk);
        check(accepted_packet_count == 32'd1, "complete packet retained before later overflow");
        check(overflow_packet_count == 32'd1, "later contiguous overflow counted once");
        check(dropped_beat_count == 32'd3, "only overflowing packet beats are dropped");
        check(fifo_level == 16'd2, "overflow rollback preserves earlier complete packet");
        check(buffered_packet_count == 16'd1, "earlier complete packet remains available");
        expect_beat(64'h5000, 1'b0, 1'b0);
        expect_beat(64'h5001, 1'b1, 1'b0);

        $display("MARKET PARSER CMAC AXIS RX BRIDGE TESTS");
        $display("Tests failed: %0d", failed);

        if (failed == 0) $finish;
        else $fatal(1, "market_parser_cmac_axis_rx_bridge_tb failed");
    end

endmodule
`default_nettype wire
