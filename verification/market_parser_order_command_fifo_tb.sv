`timescale 1ns / 1ps
`default_nettype none

module market_parser_order_command_fifo_tb;
    localparam time HALF = 1ns;
    logic clk = 1'b0;
    logic rst;
    logic input_valid;
    logic input_ready;
    logic input_cancel;
    logic [63:0] input_id;
    logic [15:0] input_stock_locate;
    logic input_side;
    logic [31:0] input_price;
    logic [31:0] input_quantity;
    logic output_valid;
    logic output_ready;
    logic output_cancel;
    logic [63:0] output_id;
    logic [15:0] output_stock_locate;
    logic output_side;
    logic [31:0] output_price;
    logic [31:0] output_quantity;
    logic [1:0] occupancy;
    int failed;

    always #HALF clk = ~clk;
    market_parser_order_command_fifo dut (.*);

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    task automatic push(
        input logic cancel,
        input logic [63:0] id,
        input logic [31:0] price
    );
        @(negedge clk);
        input_valid = 1'b1;
        input_cancel = cancel;
        input_id = id;
        input_stock_locate = 16'h1234 + id[15:0];
        input_side = id[0];
        input_price = price;
        input_quantity = id[31:0] + 32'd10;
        while (!input_ready) @(negedge clk);
        @(negedge clk);
        input_valid = 1'b0;
    endtask

    task automatic pop_check(
        input logic cancel,
        input logic [63:0] id,
        input logic [31:0] price
    );
        while (!output_valid) @(negedge clk);
        check(output_cancel == cancel && output_id == id &&
              output_stock_locate == 16'h1234 + id[15:0] &&
              output_side == id[0] && output_price == price &&
              output_quantity == id[31:0] + 32'd10,
              "FIFO output preserves the complete command payload");
        output_ready = 1'b1;
        @(negedge clk);
        output_ready = 1'b0;
    endtask

    initial begin
        logic [176:0] held_payload;
        failed = 0;
        rst = 1'b1;
        input_valid = 1'b0;
        input_cancel = 1'b0;
        input_id = '0;
        input_stock_locate = '0;
        input_side = 1'b0;
        input_price = '0;
        input_quantity = '0;
        output_ready = 1'b0;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        push(1'b0, 64'd1, 32'd101);
        while (!output_valid) @(negedge clk);
        held_payload = {output_cancel, output_id, output_stock_locate,
                        output_side, output_price, output_quantity, occupancy};
        repeat (3) begin
            @(negedge clk);
            check(output_valid &&
                  {output_cancel, output_id, output_stock_locate,
                   output_side, output_price, output_quantity, occupancy} ==
                  held_payload,
                  "FIFO output remains stable under backpressure");
        end

        push(1'b1, 64'd2, 32'd202);
        check(occupancy == 2 && !input_ready,
              "two queued commands apply backpressure using occupancy only");
        pop_check(1'b0, 64'd1, 32'd101);
        check(occupancy == 1 && input_ready,
              "popping restores lifecycle-side readiness");

        @(negedge clk);
        input_valid = 1'b1;
        input_cancel = 1'b0;
        input_id = 64'd3;
        input_stock_locate = 16'h1237;
        input_side = 1'b1;
        input_price = 32'd303;
        input_quantity = 32'd13;
        output_ready = 1'b1;
        @(negedge clk);
        input_valid = 1'b0;
        output_ready = 1'b0;
        check(occupancy == 1 && output_valid && output_id == 64'd3,
              "simultaneous push and pop preserves full throughput and ordering");
        pop_check(1'b0, 64'd3, 32'd303);
        check(occupancy == 0 && !output_valid,
              "FIFO drains without stale commands");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
