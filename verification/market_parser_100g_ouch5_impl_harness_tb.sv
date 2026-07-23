`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_ouch5_impl_harness_tb;
    localparam realtime CLK_PERIOD = 3.102ns;
    logic clk = 1'b0;
    logic rst;
    logic [31:0] status;
    logic [31:0] initial_status;
    int failed;

    always #(CLK_PERIOD/2.0) clk = ~clk;
    market_parser_100g_ouch5_impl_harness dut (.*);

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    initial begin
        int wait_cycles;
        failed = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        initial_status = status;

        wait_cycles = 0;
        while ((dut.ouch_encoded_new_count == 0 ||
                dut.acknowledged_order_count == 0 ||
                dut.lifecycle_fill_count == 0 ||
                dut.applied_fill_count == 0) && wait_cycles < 12000) begin
            @(posedge clk);
            wait_cycles++;
        end
        repeat (5) @(posedge clk);

        check(wait_cycles < 12000,
              "routed harness completes packet-to-OUCH-to-fill replay");
        check(dut.gateway_session_active &&
              dut.cmac_axis_accepted_packet_count != 0,
              "Soup session and market-data ingress become active");
        check(dut.generated_intent_count != 0 &&
              dut.passed_new_count != 0 &&
              dut.ouch_encoded_new_count != 0,
              "decision and final risk produce an encoded OUCH order");
        check(dut.acknowledged_order_count != 0 &&
              dut.lifecycle_fill_count != 0 &&
              dut.applied_fill_count != 0 &&
              dut.ouch_decoded_event_count >= 2,
              "Soup-framed acceptance and fill close the lifecycle loop");
        check(dut.protocol_error_count == 0 &&
              dut.gateway_protocol_error_count == 0 &&
              dut.cmac_axis_overflow_packet_count == 0 &&
              dut.cmac_axis_dropped_beat_count == 0,
              "routed harness replay remains protocol-clean and lossless");
        check(status != initial_status,
              "compact OUCH implementation status reflects activity");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
