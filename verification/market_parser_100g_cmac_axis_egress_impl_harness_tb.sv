`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_cmac_axis_egress_impl_harness_tb;
    localparam realtime CLK_PERIOD = 3.102ns;
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    logic clk = 1'b0;
    logic rst;
    logic [31:0] status;
    logic [31:0] initial_status;
    int failed;

    always #HALF_CLK_PERIOD clk <= ~clk;

    market_parser_100g_cmac_axis_egress_impl_harness dut (
        .clk(clk),
        .rst(rst),
        .status(status)
    );

    task automatic check(input bit condition, input string message);
        if (condition) begin
            $display("PASS: %s", message);
        end else begin
            $display("FAIL: %s", message);
            failed++;
        end
    endtask

    initial begin
        int wait_cycles;

        failed = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        initial_status = status;

        wait_cycles = 0;
        while ((dut.cmac_axis_accepted_packet_count == 32'd0 ||
                dut.new_command_count == 32'd0 ||
                dut.passed_new_count == 32'd0 ||
                dut.acknowledged_order_count == 32'd0 ||
                dut.lifecycle_fill_count == 32'd0 ||
                dut.applied_fill_count == 32'd0) &&
               wait_cycles < 10000) begin
            @(posedge clk);
            wait_cycles++;
        end
        repeat (5) @(posedge clk);

        check(wait_cycles < 10000,
              "deterministic packet-to-order exchange loop completes");
        check(dut.cmac_axis_accepted_packet_count != 32'd0 &&
              dut.book_quote_update_count != 32'd0,
              "packet replay reaches the guarded book path");
        check(dut.generated_intent_count != 32'd0 &&
              dut.accepted_intent_count != 32'd0 &&
              dut.new_command_count != 32'd0 &&
              dut.passed_new_count != 32'd0,
              "decision intent passes final risk and becomes an order command");
        check(dut.acknowledged_order_count != 32'd0 &&
              dut.lifecycle_fill_count != 32'd0 &&
              dut.applied_fill_count != 32'd0,
              "exchange acknowledgment and fill close the position loop");
        check(dut.protocol_error_count == 32'd0 &&
              dut.cmac_axis_overflow_packet_count == 32'd0 &&
              dut.cmac_axis_dropped_beat_count == 32'd0,
              "closed-loop deterministic replay remains lossless and valid");
        check(dut.control_reject_count == 32'd0 &&
              dut.quantity_reject_count == 32'd0 &&
              dut.price_reject_count == 32'd0 &&
              dut.outstanding_reject_count == 32'd0 &&
              dut.rate_reject_count == 32'd0,
              "valid replay produces no final-risk rejection");
        check(status != initial_status,
              "compact egress-risk status reflects internal activity");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
