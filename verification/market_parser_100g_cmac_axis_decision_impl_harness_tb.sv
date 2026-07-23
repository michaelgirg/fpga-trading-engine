`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_cmac_axis_decision_impl_harness_tb;
    localparam realtime CLK_PERIOD = 3.102ns;
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    logic clk = 1'b0;
    logic rst;
    logic [31:0] status;
    logic [31:0] first_status;
    int failed;

    always #HALF_CLK_PERIOD clk <= ~clk;

    market_parser_100g_cmac_axis_decision_impl_harness dut (
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
        first_status = status;

        wait_cycles = 0;
        while ((dut.cmac_axis_accepted_packet_count == 32'd0 ||
                dut.book_quote_update_count == 32'd0 ||
                dut.generated_intent_count == 32'd0 ||
                dut.applied_fill_count == 32'd0) &&
               wait_cycles < 10000) begin
            @(posedge clk);
            wait_cycles++;
        end
        repeat (5) @(posedge clk);

        check(dut.cmac_axis_accepted_packet_count != 32'd0,
              "replay packet crosses the CMAC AXIS bridge");
        check(dut.book_quote_update_count != 32'd0 &&
              dut.evaluated_quote_count != 32'd0,
              "book updates reach the quote decision pipeline");
        check(dut.generated_intent_count != 32'd0,
              "an actionable quote emits an order intent");
        check(dut.applied_fill_count != 32'd0 &&
              dut.untracked_fill_count == 32'd0,
              "looped-back fills update a tracked position");
        check(dut.cmac_axis_overflow_packet_count == 32'd0 &&
              dut.cmac_axis_dropped_beat_count == 32'd0 &&
              dut.book_table_overflow_count == 32'd0,
              "the deterministic replay remains lossless");
        check(status != first_status,
              "compact implementation status reflects internal activity");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
