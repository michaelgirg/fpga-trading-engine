`timescale 1ns / 1ps
`default_nettype none

module market_parser_ouch5_codec_tb;
    localparam time HALF = 1ns;

    logic clk = 1'b0;
    logic rst;
    logic command_valid;
    logic command_ready;
    logic command_cancel;
    logic [63:0] command_id;
    logic [15:0] command_stock_locate;
    logic command_side;
    logic [31:0] command_price;
    logic [31:0] command_quantity;
    logic tx_valid;
    logic tx_ready;
    logic [511:0] tx_data;
    logic [63:0] tx_keep;
    logic tx_last;
    logic local_reject_valid;
    logic local_reject_ready;
    logic [63:0] local_reject_order_id;
    logic [1:0] local_reject_reason;
    logic rx_valid;
    logic rx_ready;
    logic [511:0] rx_data;
    logic [63:0] rx_keep;
    logic rx_last;
    logic exchange_event_valid;
    logic exchange_event_ready;
    logic [1:0] exchange_event_type;
    logic [63:0] exchange_event_order_id;
    logic [31:0] exchange_event_price;
    logic [31:0] exchange_event_quantity;
    logic [31:0] encoded_new_count;
    logic [31:0] encoded_cancel_count;
    logic [31:0] encode_reject_count;
    logic [31:0] decoded_event_count;
    logic [31:0] malformed_response_count;
    logic [31:0] unsupported_response_count;
    int failed;

    always #HALF clk = ~clk;

    market_parser_ouch5_codec #(
        .NUM_SYMBOLS(2),
        .SYMBOL_LOCATES({16'h2222, 16'h1111}),
        .OUCH_SYMBOLS({64'h4242424220202020, 64'h4141414120202020})
    ) dut (.*);

    task automatic check(input bit condition, input string message);
        if (condition) begin
            $display("PASS: %s", message);
        end else begin
            $display("FAIL: %s", message);
            failed++;
        end
    endtask

    task automatic put_u32_be(
        inout logic [511:0] frame,
        input int offset,
        input logic [31:0] value
    );
        frame[(offset+0)*8 +: 8] = value[31:24];
        frame[(offset+1)*8 +: 8] = value[23:16];
        frame[(offset+2)*8 +: 8] = value[15:8];
        frame[(offset+3)*8 +: 8] = value[7:0];
    endtask

    task automatic send_command(
        input logic cancel,
        input logic [63:0] id,
        input logic [15:0] locate,
        input logic side,
        input logic [31:0] price,
        input logic [31:0] quantity
    );
        @(negedge clk);
        command_valid = 1'b1;
        command_cancel = cancel;
        command_id = id;
        command_stock_locate = locate;
        command_side = side;
        command_price = price;
        command_quantity = quantity;
        while (!command_ready) @(negedge clk);
        @(negedge clk);
        command_valid = 1'b0;
    endtask

    task automatic consume_tx;
        tx_ready = 1'b1;
        @(negedge clk);
        tx_ready = 1'b0;
    endtask

    task automatic consume_local_reject(
        input logic [63:0] expected_id,
        input logic [1:0] expected_reason
    );
        while (!local_reject_valid) @(negedge clk);
        check(local_reject_order_id == expected_id &&
              local_reject_reason == expected_reason,
              "invalid command produces the expected local rejection");
        local_reject_ready = 1'b1;
        @(negedge clk);
        local_reject_ready = 1'b0;
    endtask

    task automatic send_response(
        input logic [511:0] frame,
        input logic [63:0] keep,
        input logic last
    );
        @(negedge clk);
        rx_valid = 1'b1;
        rx_data = frame;
        rx_keep = keep;
        rx_last = last;
        while (!rx_ready) @(negedge clk);
        @(negedge clk);
        rx_valid = 1'b0;
    endtask

    task automatic consume_event(
        input logic [1:0] expected_type,
        input logic [63:0] expected_id,
        input logic [31:0] expected_price,
        input logic [31:0] expected_quantity
    );
        while (!exchange_event_valid) @(negedge clk);
        check(exchange_event_type == expected_type &&
              exchange_event_order_id == expected_id &&
              exchange_event_price == expected_price &&
              exchange_event_quantity == expected_quantity,
              "decoded exchange event payload");
        exchange_event_ready = 1'b1;
        @(negedge clk);
        exchange_event_ready = 1'b0;
    endtask

    initial begin
        logic [511:0] expected;
        logic [511:0] response;
        logic [129:0] held_event;

        failed = 0;
        rst = 1'b1;
        command_valid = 1'b0;
        command_cancel = 1'b0;
        command_id = '0;
        command_stock_locate = '0;
        command_side = 1'b0;
        command_price = '0;
        command_quantity = '0;
        tx_ready = 1'b0;
        local_reject_ready = 1'b0;
        rx_valid = 1'b0;
        rx_data = '0;
        rx_keep = '0;
        rx_last = 1'b0;
        exchange_event_ready = 1'b0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        send_command(1'b0, 64'd1, 16'h1111, 1'b0,
                     32'd123456, 32'd100);
        while (!tx_valid) @(negedge clk);
        expected = '0;
        expected[0*8 +: 8] = "O";
        put_u32_be(expected, 1, 32'd1);
        expected[5*8 +: 8] = "B";
        put_u32_be(expected, 6, 32'd100);
        expected[10*8 +: 8] = "A";
        expected[11*8 +: 8] = "A";
        expected[12*8 +: 8] = "A";
        expected[13*8 +: 8] = "A";
        expected[14*8 +: 32] = 32'h20202020;
        expected[18*8 +: 32] = 32'd0;
        put_u32_be(expected, 22, 32'd123456);
        expected[26*8 +: 8] = "0";
        expected[27*8 +: 8] = "Y";
        expected[28*8 +: 8] = "A";
        expected[29*8 +: 8] = "N";
        expected[30*8 +: 8] = "N";
        expected[31*8 +: 8] = "F";
        expected[32*8 +: 8] = "P";
        expected[33*8 +: 8] = "G";
        expected[34*8 +: 8] = "A";
        for (int i = 35; i < 44; i++) expected[i*8 +: 8] = "0";
        expected[44*8 +: 8] = "1";
        check(tx_data == expected && tx_keep == 64'h0000_7fff_ffff_ffff &&
              tx_last,
              "Enter Order is byte-exact OUCH 5.0 without appendages");
        repeat (3) begin
            @(negedge clk);
            check(tx_valid && tx_data == expected &&
                  tx_keep == 64'h0000_7fff_ffff_ffff,
                  "encoded order remains stable under AXI backpressure");
        end
        consume_tx();

        send_command(1'b1, 64'd1, 16'h1111, 1'b0, 32'd0, 32'd0);
        while (!tx_valid) @(negedge clk);
        expected = '0;
        expected[0*8 +: 8] = "X";
        put_u32_be(expected, 1, 32'd1);
        check(tx_data == expected && tx_keep == 64'h0000_0000_0000_07ff &&
              tx_last,
              "Cancel Order encodes a full cancel with intended quantity zero");
        consume_tx();

        send_command(1'b0, 64'd2, 16'h9999, 1'b1, 32'd1, 32'd1);
        consume_local_reject(64'd2, 2'd2);
        check(!tx_valid, "unmapped symbol is never transmitted");

        send_command(1'b0, 64'h0000_0001_0000_0001,
                     16'h1111, 1'b0, 32'd1, 32'd1);
        consume_local_reject(64'h0000_0001_0000_0001, 2'd1);
        check(!tx_valid, "order ID outside OUCH UserRefNum range is rejected");

        response = '0;
        response[0*8 +: 8] = "A";
        put_u32_be(response, 9, 32'd1);
        response[47*8 +: 8] = "L";
        send_response(response, 64'hffff_ffff_ffff_ffff, 1'b1);
        while (!exchange_event_valid) @(negedge clk);
        held_event = {exchange_event_type, exchange_event_order_id,
                      exchange_event_price, exchange_event_quantity};
        repeat (3) begin
            @(negedge clk);
            check(exchange_event_valid &&
                  {exchange_event_type, exchange_event_order_id,
                   exchange_event_price, exchange_event_quantity} == held_event,
                  "decoded response remains stable under backpressure");
        end
        consume_event(2'd0, 64'd1, 32'd0, 32'd0);

        response = '0;
        response[0*8 +: 8] = "J";
        put_u32_be(response, 9, 32'd2);
        send_response(response, 64'h0000_0000_7fff_ffff, 1'b1);
        consume_event(2'd1, 64'd2, 32'd0, 32'd0);

        response = '0;
        response[0*8 +: 8] = "E";
        put_u32_be(response, 9, 32'd3);
        put_u32_be(response, 13, 32'd25);
        put_u32_be(response, 21, 32'd654321);
        send_response(response, 64'h0000_000f_ffff_ffff, 1'b1);
        consume_event(2'd2, 64'd3, 32'd654321, 32'd25);

        response = '0;
        response[0*8 +: 8] = "C";
        put_u32_be(response, 9, 32'd4);
        put_u32_be(response, 13, 32'd10);
        send_response(response, 64'h0000_0000_000f_ffff, 1'b1);
        consume_event(2'd3, 64'd4, 32'd0, 32'd10);

        response = '0;
        response[0*8 +: 8] = "E";
        put_u32_be(response, 9, 32'd5);
        send_response(response, 64'h0000_0000_0000_ffff, 1'b1);
        @(negedge clk);
        check(!exchange_event_valid,
              "truncated supported response is classified as malformed");

        response = '0;
        response[0*8 +: 8] = "Q";
        send_response(response, 64'h1, 1'b1);
        @(negedge clk);
        check(!exchange_event_valid,
              "unsupported response does not enter the lifecycle stream");

        check(encoded_new_count == 32'd1 &&
              encoded_cancel_count == 32'd1 &&
              encode_reject_count == 32'd2,
              "encode counters are exact");
        check(decoded_event_count == 32'd4 &&
              malformed_response_count == 32'd1 &&
              unsupported_response_count == 32'd1,
              "decode counters are exact");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
