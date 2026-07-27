`timescale 1ns / 1ps
`default_nettype none

module market_parser_ouch5_gateway_tb;
    localparam time HALF = 1ns;
    logic clk = 1'b0;
    logic rst;
    logic transport_connected;
    logic login_valid;
    logic login_ready;
    logic [47:0] login_username;
    logic [79:0] login_password;
    logic [79:0] requested_session;
    logic [63:0] requested_sequence;
    logic logout_valid;
    logic logout_ready;
    logic command_valid;
    logic command_ready;
    logic command_cancel;
    logic [63:0] command_id;
    logic [15:0] command_stock_locate;
    logic command_side;
    logic [31:0] command_price;
    logic [31:0] command_quantity;
    logic exchange_event_valid;
    logic exchange_event_ready;
    logic [1:0] exchange_event_type;
    logic [63:0] exchange_event_order_id;
    logic [31:0] exchange_event_price;
    logic [31:0] exchange_event_quantity;
    logic soup_tx_valid;
    logic soup_tx_ready;
    logic [511:0] soup_tx_data;
    logic [63:0] soup_tx_keep;
    logic soup_tx_last;
    logic soup_rx_valid;
    logic soup_rx_ready;
    logic [511:0] soup_rx_data;
    logic [63:0] soup_rx_keep;
    logic soup_rx_last;
    logic session_active;
    logic session_fault;
    logic login_in_progress;
    logic [79:0] current_session;
    logic [63:0] next_sequence;
    logic [31:0] login_request_count;
    logic [31:0] logout_request_count;
    logic [31:0] client_heartbeat_count;
    logic [31:0] encoded_new_count;
    logic [31:0] encoded_cancel_count;
    logic [31:0] encode_reject_count;
    logic [31:0] transport_reject_count;
    logic [31:0] decoded_event_count;
    logic [31:0] malformed_response_count;
    logic [31:0] unsupported_response_count;
    logic [31:0] heartbeat_count;
    logic [31:0] sequenced_packet_count;
    logic [31:0] malformed_soup_count;
    logic [31:0] watchdog_timeout_count;
    int failed;

    always #HALF clk = ~clk;

    market_parser_ouch5_gateway #(
        .NUM_SYMBOLS(1),
        .SYMBOL_LOCATES(16'h1234),
        .OUCH_SYMBOLS(64'h5445535420202020),
        .WATCHDOG_CYCLES(256)
    ) dut (.*);

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    function automatic logic [63:0] mask(input int count);
        if (count >= 64) mask = 64'hffff_ffff_ffff_ffff;
        else mask = (64'h1 << count) - 1'b1;
    endfunction

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
        input logic [15:0] locate
    );
        @(negedge clk);
        command_valid = 1'b1;
        command_cancel = cancel;
        command_id = id;
        command_stock_locate = locate;
        command_side = 1'b0;
        command_price = 32'd100500;
        command_quantity = 32'd10;
        while (!command_ready) @(negedge clk);
        @(negedge clk);
        command_valid = 1'b0;
    endtask

    task automatic send_soup(
        input logic [511:0] frame,
        input logic [63:0] keep,
        input logic last
    );
        @(negedge clk);
        soup_rx_valid = 1'b1;
        soup_rx_data = frame;
        soup_rx_keep = keep;
        soup_rx_last = last;
        while (!soup_rx_ready) @(negedge clk);
        @(negedge clk);
        soup_rx_valid = 1'b0;
    endtask

    task automatic login;
        logic [511:0] frame;
        frame = '0;
        frame[15:8] = 8'd31;
        frame[23:16] = "A";
        for (int i = 0; i < 10; i++) begin
            frame[(3+i)*8 +: 8] = "S";
            frame[(13+i)*8 +: 8] = " ";
            frame[(23+i)*8 +: 8] = " ";
        end
        frame[32*8 +: 8] = "1";
        send_soup(frame, mask(33), 1'b1);
        while (!session_active) @(negedge clk);
    endtask

    task automatic send_ouch_response(
        input logic [511:0] payload,
        input int payload_bytes
    );
        logic [511:0] frame;
        int total_bytes;
        total_bytes = payload_bytes + 3;
        frame = payload << 24;
        frame[7:0] = 8'd0;
        frame[15:8] = payload_bytes + 1;
        frame[23:16] = "S";
        if (total_bytes <= 64) begin
            send_soup(frame, mask(total_bytes), 1'b1);
        end else begin
            send_soup(frame, 64'hffff_ffff_ffff_ffff, 1'b0);
            frame = '0;
            for (int i = 0; i < 3; i++) begin
                frame[i*8 +: 8] = payload[(61+i)*8 +: 8];
            end
            send_soup(frame, mask(total_bytes - 64), 1'b1);
        end
    endtask

    task automatic consume_event(
        input logic [1:0] event_type,
        input logic [63:0] id,
        input logic [31:0] price,
        input logic [31:0] quantity
    );
        while (!exchange_event_valid) @(negedge clk);
        check(exchange_event_type == event_type &&
              exchange_event_order_id == id &&
              exchange_event_price == price &&
              exchange_event_quantity == quantity,
              "gateway returns the expected lifecycle event");
        exchange_event_ready = 1'b1;
        @(negedge clk);
        exchange_event_ready = 1'b0;
    endtask

    initial begin
        logic [511:0] payload;

        failed = 0;
        rst = 1'b1;
        transport_connected = 1'b1;
        login_valid = 1'b0;
        login_username = '0;
        login_password = '0;
        requested_session = '0;
        requested_sequence = 64'd1;
        logout_valid = 1'b0;
        command_valid = 1'b0;
        command_cancel = 1'b0;
        command_id = '0;
        command_stock_locate = '0;
        command_side = 1'b0;
        command_price = '0;
        command_quantity = '0;
        exchange_event_ready = 1'b0;
        soup_tx_ready = 1'b0;
        soup_rx_valid = 1'b0;
        soup_rx_data = '0;
        soup_rx_keep = '0;
        soup_rx_last = 1'b0;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        login();
        check(session_active, "venue login enables the command gateway");

        send_command(1'b0, 64'd1, 16'h1234);
        while (!soup_tx_valid) @(negedge clk);
        check(soup_tx_data[23:16] == "U" &&
              soup_tx_data[31:24] == "O" &&
              soup_tx_data[39:32] == 8'd0 &&
              soup_tx_data[47:40] == 8'd0 &&
              soup_tx_data[55:48] == 8'd0 &&
              soup_tx_data[63:56] == 8'd1 &&
              soup_tx_keep == mask(50),
              "risk-cleared command becomes a framed OUCH Enter Order");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        payload = '0;
        payload[7:0] = "A";
        put_u32_be(payload, 9, 32'd1);
        payload[47*8 +: 8] = "L";
        send_ouch_response(payload, 64);
        consume_event(2'd0, 64'd1, 32'd0, 32'd0);

        payload = '0;
        payload[7:0] = "E";
        put_u32_be(payload, 9, 32'd1);
        put_u32_be(payload, 13, 32'd10);
        put_u32_be(payload, 21, 32'd100500);
        send_ouch_response(payload, 36);
        consume_event(2'd2, 64'd1, 32'd100500, 32'd10);

        send_command(1'b1, 64'd1, 16'h1234);
        while (!soup_tx_valid) @(negedge clk);
        check(soup_tx_data[23:16] == "U" &&
              soup_tx_data[31:24] == "X" &&
              soup_tx_keep == mask(14),
              "cancel command becomes a framed OUCH full cancel");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        payload = '0;
        payload[7:0] = "C";
        put_u32_be(payload, 9, 32'd1);
        put_u32_be(payload, 13, 32'd0);
        send_ouch_response(payload, 20);
        consume_event(2'd3, 64'd1, 32'd0, 32'd0);

        send_command(1'b0, 64'd2, 16'h9999);
        consume_event(2'd1, 64'd2, 32'd0, 32'd0);

        payload = '0;
        payload[15:8] = 8'd1;
        payload[23:16] = "Z";
        send_soup(payload, mask(3), 1'b1);
        @(negedge clk);
        check(!session_active, "End Of Session closes the gateway");
        send_command(1'b1, 64'd3, 16'h1234);
        consume_event(2'd1, 64'd3, 32'd0, 32'd0);

        check(encoded_new_count == 1 && encoded_cancel_count == 1 &&
              encode_reject_count == 1 && transport_reject_count == 1,
              "command-path counters distinguish codec and transport rejects");
        check(decoded_event_count == 3 && sequenced_packet_count == 3 &&
              malformed_response_count == 0 && malformed_soup_count == 0,
              "venue response counters are exact");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
