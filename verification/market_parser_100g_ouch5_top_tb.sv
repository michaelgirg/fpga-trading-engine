`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_ouch5_top_tb;
    localparam realtime CLK_PERIOD = 3.102ns;
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [3:0] LAST_BEAT_INDEX = 4'd8;

    logic clk = 1'b0;
    logic rst;
    logic rx_axis_tvalid;
    logic [511:0] rx_axis_tdata;
    logic [63:0] rx_axis_tkeep;
    logic rx_axis_tlast;
    logic soup_tx_valid;
    logic soup_tx_ready;
    logic [511:0] soup_tx_data;
    logic [63:0] soup_tx_keep;
    logic soup_rx_valid;
    logic soup_rx_ready;
    logic [511:0] soup_rx_data;
    logic [63:0] soup_rx_keep;
    logic soup_rx_last;
    logic gateway_session_active;
    logic [127:0] position_by_symbol;
    logic [3:0] working_order_mask;
    logic [3:0] live_order_mask;
    logic [15:0] outstanding_order_count;
    logic [31:0] generated_intent_count;
    logic [31:0] passed_new_count;
    logic [31:0] acknowledged_order_count;
    logic [31:0] lifecycle_fill_count;
    logic [31:0] applied_fill_count;
    logic [31:0] ouch_encoded_new_count;
    logic [31:0] ouch_decoded_event_count;
    logic [31:0] soup_sequenced_packet_count;
    logic [31:0] gateway_protocol_error_count;
    logic [31:0] protocol_error_count;
    logic [31:0] cmac_axis_overflow_packet_count;
    logic [31:0] cmac_axis_dropped_beat_count;
    int failed;

    always #HALF_CLK_PERIOD clk = ~clk;

    function automatic logic [511:0] replay_data(input logic [3:0] index);
        case (index)
            4'd0: replay_data = 512'h24000f006400000000000000313030303030304d49530000ff018813409c0100c0ef0100000a00001140004001001302004500080f0e0d0c0b0a060504030201;
            4'd1: replay_data = 512'h45540700000053020000000000000002000000000002003412412400e803000020202020545345540a0000004201000000000000000100000000000100341241;
            4'd2: replay_data = 512'h00000004000000000004003412412400de030000202020205453455406000000420300000000000000030000000000030034124124001a040000202020205453;
            4'd3: replay_data = 512'h000006003412581700171615141312111005000000010000000000000005000000000005003412451f00e8030000202020205453455404000000420400000000;
            4'd4: replay_data = 512'h00000008003412441300100400002020202054534554030000005305000000000000000700000000000700341241240006000000030000000000000006000000;
            4'd5: replay_data = 512'h0000000a00000000000a003412581700240400000400000028000000000000000400000000000000090000000000090034125523000200000000000000080000;
            4'd6: replay_data = 512'h4264000000000000000c00000000000c00999941240017161514131211100300000005000000000000000b00000000000b003412451f00040000000400000000;
            4'd7: replay_data = 512'h0c0027262524232221200604000020202020545345541400000053c8000000000000000d00000000000d003412502c00d0070000202020205453455464000000;
            4'd8: replay_data = 512'h0000000000000000000000000000000000000000000000000000000000000001000000000000000f00000000000f0034124413003f0e00000000000e0034125a;
            default: replay_data = '0;
        endcase
    endfunction

    function automatic logic [63:0] mask(input int count);
        if (count >= 64) mask = 64'hffff_ffff_ffff_ffff;
        else mask = (64'h1 << count) - 1'b1;
    endfunction

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
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

    task automatic send_soup_beat(
        input logic [511:0] data,
        input logic [63:0] keep,
        input logic last
    );
        @(negedge clk);
        soup_rx_valid = 1'b1;
        soup_rx_data = data;
        soup_rx_keep = keep;
        soup_rx_last = last;
        while (!soup_rx_ready) @(negedge clk);
        @(negedge clk);
        soup_rx_valid = 1'b0;
    endtask

    task automatic send_login_accepted;
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
        send_soup_beat(frame, mask(33), 1'b1);
        while (!gateway_session_active) @(negedge clk);
    endtask

    task automatic send_ouch_response(
        input logic [511:0] payload,
        input int payload_bytes
    );
        logic [511:0] frame;
        int total_bytes;
        total_bytes = payload_bytes + 3;
        frame = payload << 24;
        frame[15:8] = payload_bytes + 1;
        frame[23:16] = "S";
        if (total_bytes <= 64) begin
            send_soup_beat(frame, mask(total_bytes), 1'b1);
        end else begin
            send_soup_beat(frame, 64'hffff_ffff_ffff_ffff, 1'b0);
            frame = '0;
            for (int i = 0; i < 3; i++) begin
                frame[i*8 +: 8] = payload[(61+i)*8 +: 8];
            end
            send_soup_beat(frame, mask(total_bytes - 64), 1'b1);
        end
    endtask

    task automatic replay_market_packet;
        for (int i = 0; i <= LAST_BEAT_INDEX; i++) begin
            @(negedge clk);
            rx_axis_tvalid = 1'b1;
            rx_axis_tdata = replay_data(i);
            rx_axis_tkeep = (i == LAST_BEAT_INDEX) ?
                            64'h00000001ffffffff :
                            64'hffff_ffff_ffff_ffff;
            rx_axis_tlast = i == LAST_BEAT_INDEX;
        end
        @(negedge clk);
        rx_axis_tvalid = 1'b0;
        rx_axis_tlast = 1'b0;
    endtask

    market_parser_100g_ouch5_top #(
        .NUM_SYMBOLS(4),
        .SYMBOL_LOCATES({16'h4444, 16'h3333, 16'h2222, 16'h1234}),
        .OUCH_SYMBOLS({
            64'h4444444420202020, 64'h4343434320202020,
            64'h4242424220202020, 64'h5445535420202020
        }),
        .ORDER_TABLE_DEPTH(8),
        .SOUP_WATCHDOG_CYCLES(4096)
    ) dut (
        .clk(clk), .rst(rst), .feed_recover(1'b0), .feed_activate(1'b0),
        .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep), .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(1'b0), .strategy_enable(1'b1), .kill_switch(1'b0),
        .position_clear(1'b0), .max_spread_ticks(32'd100),
        .min_top_shares(32'd1), .imbalance_shift(3'd1),
        .order_quantity(32'd2), .max_abs_position(32'd10),
        .egress_risk_enable(1'b1), .max_egress_order_quantity(32'd10),
        .min_egress_order_price(32'd1),
        .max_egress_order_price(32'hffff_ffff),
        .max_outstanding_orders(16'd4),
        .max_new_orders_per_window(16'd8),
        .transport_connected(1'b1), .soup_login_valid(1'b0),
        .soup_login_ready(), .soup_login_username(48'd0),
        .soup_login_password(80'd0),
        .soup_requested_session(80'd0),
        .soup_requested_sequence(64'd1),
        .soup_logout_valid(1'b0), .soup_logout_ready(),
        .soup_tx_valid(soup_tx_valid), .soup_tx_ready(soup_tx_ready),
        .soup_tx_data(soup_tx_data), .soup_tx_keep(soup_tx_keep),
        .soup_tx_last(), .soup_rx_valid(soup_rx_valid),
        .soup_rx_ready(soup_rx_ready), .soup_rx_data(soup_rx_data),
        .soup_rx_keep(soup_rx_keep), .soup_rx_last(soup_rx_last),
        .s_axi_awaddr(12'd0), .s_axi_awvalid(1'b0), .s_axi_awready(),
        .s_axi_wdata(32'd0), .s_axi_wstrb(4'd0), .s_axi_wvalid(1'b0),
        .s_axi_wready(), .s_axi_bresp(), .s_axi_bvalid(), .s_axi_bready(1'b1),
        .s_axi_araddr(12'd0), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(), .s_axi_rready(1'b1),
        .gateway_session_active(gateway_session_active),
        .gateway_session_fault(), .soup_login_in_progress(),
        .soup_current_session(), .soup_next_sequence(),
        .soup_login_request_count(), .soup_logout_request_count(),
        .soup_client_heartbeat_count(),
        .position_by_symbol(position_by_symbol),
        .working_order_mask(working_order_mask), .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(), .busy_intent_count(),
        .new_command_count(), .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(), .cancel_command_count(), .cancel_ack_count(),
        .lifecycle_fill_count(lifecycle_fill_count),
        .protocol_error_count(protocol_error_count),
        .generated_intent_count(generated_intent_count),
        .applied_fill_count(applied_fill_count),
        .cmac_axis_accepted_packet_count(),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count(cmac_axis_dropped_beat_count),
        .book_quote_update_count(), .feed_healthy(),
        .passed_new_count(passed_new_count), .passed_cancel_count(),
        .control_reject_count(), .quantity_reject_count(),
        .price_reject_count(), .outstanding_reject_count(),
        .rate_reject_count(), .last_local_reject_reason(),
        .ouch_encoded_new_count(ouch_encoded_new_count),
        .ouch_encoded_cancel_count(), .ouch_encode_reject_count(),
        .transport_reject_count(),
        .ouch_decoded_event_count(ouch_decoded_event_count),
        .soup_heartbeat_count(),
        .soup_sequenced_packet_count(soup_sequenced_packet_count),
        .gateway_protocol_error_count(gateway_protocol_error_count)
    );

    initial begin
        logic [511:0] payload;
        logic [31:0] order_id;
        logic [31:0] order_price;
        logic [31:0] order_quantity_seen;
        int wait_cycles;

        failed = 0;
        rst = 1'b1;
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata = '0;
        rx_axis_tkeep = '0;
        rx_axis_tlast = 1'b0;
        soup_tx_ready = 1'b0;
        soup_rx_valid = 1'b0;
        soup_rx_data = '0;
        soup_rx_keep = '0;
        soup_rx_last = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        send_login_accepted();
        check(gateway_session_active,
              "Soup login activates packet-to-order processing");
        replay_market_packet();

        wait_cycles = 0;
        while (!soup_tx_valid && wait_cycles < 10000) begin
            @(negedge clk);
            wait_cycles++;
        end
        check(wait_cycles < 10000 && soup_tx_data[23:16] == "U" &&
              soup_tx_data[31:24] == "O",
              "market packet produces a Soup-framed OUCH Enter Order");
        order_id = {soup_tx_data[39:32], soup_tx_data[47:40],
                    soup_tx_data[55:48], soup_tx_data[63:56]};
        order_quantity_seen = {soup_tx_data[79:72], soup_tx_data[87:80],
                               soup_tx_data[95:88], soup_tx_data[103:96]};
        order_price = {soup_tx_data[207:200], soup_tx_data[215:208],
                       soup_tx_data[223:216], soup_tx_data[231:224]};
        check(order_id == 1 && order_quantity_seen == 2 &&
              soup_tx_keep == mask(50),
              "generated OUCH order preserves lifecycle ID and strategy size");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        payload = '0;
        payload[7:0] = "A";
        put_u32_be(payload, 9, order_id);
        payload[47*8 +: 8] = "L";
        send_ouch_response(payload, 64);

        payload = '0;
        payload[7:0] = "E";
        put_u32_be(payload, 9, order_id);
        put_u32_be(payload, 13, order_quantity_seen);
        put_u32_be(payload, 21, order_price);
        send_ouch_response(payload, 36);

        wait_cycles = 0;
        while ((acknowledged_order_count == 0 || lifecycle_fill_count == 0 ||
                applied_fill_count == 0) && wait_cycles < 1000) begin
            @(negedge clk);
            wait_cycles++;
        end
        check(wait_cycles < 1000 && acknowledged_order_count == 1 &&
              lifecycle_fill_count == 1 && applied_fill_count == 1,
              "accepted and executed OUCH responses close the lifecycle loop");
        check(generated_intent_count != 0 && passed_new_count == 1 &&
              ouch_encoded_new_count == 1 && ouch_decoded_event_count == 2 &&
              soup_sequenced_packet_count == 2,
              "packet, decision, risk, OUCH, and Soup counters agree");
        check(position_by_symbol[31:0] == 32'd2 &&
              working_order_mask[0] == 1'b0 && live_order_mask[0] == 1'b0 &&
              outstanding_order_count == 0,
              "full fill updates position and retires the working order");
        check(protocol_error_count == 0 && gateway_protocol_error_count == 0 &&
              cmac_axis_overflow_packet_count == 0 &&
              cmac_axis_dropped_beat_count == 0,
              "deterministic end-to-end replay is lossless and protocol-clean");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
