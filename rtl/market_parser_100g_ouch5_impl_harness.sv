`default_nettype none
// Compact routed harness for the complete packet-to-Soup/OUCH datapath.
// A deterministic logical exchange accepts and fills generated new orders.
module market_parser_100g_ouch5_impl_harness (
    input  wire logic        clk,
    input  wire logic        rst,
    output logic [31:0]      status
);
    localparam logic [3:0] LAST_BEAT_INDEX = 4'd8;
    localparam logic [2:0] RESP_WAIT_LOGIN = 3'd0;
    localparam logic [2:0] RESP_LOGIN      = 3'd1;
    localparam logic [2:0] RESP_WAIT       = 3'd2;
    localparam logic [2:0] RESP_ACK_0      = 3'd3;
    localparam logic [2:0] RESP_ACK_1      = 3'd4;
    localparam logic [2:0] RESP_FILL       = 3'd5;
    localparam logic [2:0] RESP_CANCEL     = 3'd6;

    logic rx_axis_tvalid;
    logic [511:0] rx_axis_tdata;
    logic [63:0] rx_axis_tkeep;
    logic rx_axis_tlast;
    logic [3:0] beat_index_r;
    logic [5:0] gap_count_r;

    (* keep = "true" *) logic soup_tx_valid;
    (* keep = "true" *) logic [511:0] soup_tx_data;
    (* keep = "true" *) logic [63:0] soup_tx_keep;
    logic soup_rx_valid;
    logic soup_rx_ready;
    logic [511:0] soup_rx_data;
    logic [63:0] soup_rx_keep;
    logic soup_rx_last;
    logic [2:0] response_state_r;
    logic [31:0] response_order_id_r;
    logic [31:0] response_price_r;
    logic [31:0] response_quantity_r;

    (* keep = "true" *) logic gateway_session_active;
    (* keep = "true" *) logic [127:0] position_by_symbol;
    (* keep = "true" *) logic [3:0] working_order_mask;
    (* keep = "true" *) logic [3:0] live_order_mask;
    (* keep = "true" *) logic [15:0] outstanding_order_count;
    (* keep = "true" *) logic [31:0] generated_intent_count;
    (* keep = "true" *) logic [31:0] passed_new_count;
    (* keep = "true" *) logic [31:0] acknowledged_order_count;
    (* keep = "true" *) logic [31:0] lifecycle_fill_count;
    (* keep = "true" *) logic [31:0] applied_fill_count;
    (* keep = "true" *) logic [31:0] ouch_encoded_new_count;
    (* keep = "true" *) logic [31:0] ouch_decoded_event_count;
    (* keep = "true" *) logic [31:0] soup_sequenced_packet_count;
    (* keep = "true" *) logic [31:0] gateway_protocol_error_count;
    (* keep = "true" *) logic [31:0] protocol_error_count;
    (* keep = "true" *) logic [31:0] cmac_axis_accepted_packet_count;
    (* keep = "true" *) logic [31:0] cmac_axis_overflow_packet_count;
    (* keep = "true" *) logic [31:0] cmac_axis_dropped_beat_count;
    logic [31:0] status_sample_r;

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

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_axis_tvalid <= 1'b0;
            rx_axis_tdata <= '0;
            rx_axis_tkeep <= '0;
            rx_axis_tlast <= 1'b0;
            beat_index_r <= '0;
            gap_count_r <= 6'd16;
        end else if (gap_count_r != 0) begin
            rx_axis_tvalid <= 1'b0;
            rx_axis_tdata <= '0;
            rx_axis_tkeep <= '0;
            rx_axis_tlast <= 1'b0;
            gap_count_r <= gap_count_r - 1'b1;
        end else begin
            rx_axis_tvalid <= 1'b1;
            rx_axis_tdata <= replay_data(beat_index_r);
            rx_axis_tkeep <= (beat_index_r == LAST_BEAT_INDEX) ?
                             64'h00000001ffffffff :
                             64'hffffffffffffffff;
            rx_axis_tlast <= beat_index_r == LAST_BEAT_INDEX;
            if (beat_index_r == LAST_BEAT_INDEX) begin
                beat_index_r <= '0;
                gap_count_r <= 6'd32;
            end else begin
                beat_index_r <= beat_index_r + 1'b1;
            end
        end
    end

    always_comb begin
        soup_rx_valid = 1'b0;
        soup_rx_data = '0;
        soup_rx_keep = '0;
        soup_rx_last = 1'b1;
        case (response_state_r)
            RESP_LOGIN: begin
                soup_rx_valid = 1'b1;
                soup_rx_data[15:8] = 8'd31;
                soup_rx_data[23:16] = 8'h41;
                for (int i = 0; i < 10; i++) begin
                    soup_rx_data[(3+i)*8 +: 8] = 8'h53;
                    soup_rx_data[(13+i)*8 +: 8] = 8'h20;
                    soup_rx_data[(23+i)*8 +: 8] = 8'h20;
                end
                soup_rx_data[32*8 +: 8] = 8'h31;
                soup_rx_keep = 64'h00000001ffffffff;
            end
            RESP_ACK_0: begin
                soup_rx_valid = 1'b1;
                soup_rx_data[15:8] = 8'd65;
                soup_rx_data[23:16] = 8'h53;
                soup_rx_data[31:24] = 8'h41;
                soup_rx_data[12*8 +: 8] = response_order_id_r[31:24];
                soup_rx_data[13*8 +: 8] = response_order_id_r[23:16];
                soup_rx_data[14*8 +: 8] = response_order_id_r[15:8];
                soup_rx_data[15*8 +: 8] = response_order_id_r[7:0];
                soup_rx_data[50*8 +: 8] = 8'h4c;
                soup_rx_keep = 64'hffffffffffffffff;
                soup_rx_last = 1'b0;
            end
            RESP_ACK_1: begin
                soup_rx_valid = 1'b1;
                soup_rx_keep = 64'h7;
            end
            RESP_FILL: begin
                soup_rx_valid = 1'b1;
                soup_rx_data[15:8] = 8'd37;
                soup_rx_data[23:16] = 8'h53;
                soup_rx_data[31:24] = 8'h45;
                soup_rx_data[12*8 +: 8] = response_order_id_r[31:24];
                soup_rx_data[13*8 +: 8] = response_order_id_r[23:16];
                soup_rx_data[14*8 +: 8] = response_order_id_r[15:8];
                soup_rx_data[15*8 +: 8] = response_order_id_r[7:0];
                soup_rx_data[16*8 +: 8] = response_quantity_r[31:24];
                soup_rx_data[17*8 +: 8] = response_quantity_r[23:16];
                soup_rx_data[18*8 +: 8] = response_quantity_r[15:8];
                soup_rx_data[19*8 +: 8] = response_quantity_r[7:0];
                soup_rx_data[24*8 +: 8] = response_price_r[31:24];
                soup_rx_data[25*8 +: 8] = response_price_r[23:16];
                soup_rx_data[26*8 +: 8] = response_price_r[15:8];
                soup_rx_data[27*8 +: 8] = response_price_r[7:0];
                soup_rx_keep = 64'h0000007fffffffff;
            end
            RESP_CANCEL: begin
                soup_rx_valid = 1'b1;
                soup_rx_data[15:8] = 8'd21;
                soup_rx_data[23:16] = 8'h53;
                soup_rx_data[31:24] = 8'h43;
                soup_rx_data[12*8 +: 8] = response_order_id_r[31:24];
                soup_rx_data[13*8 +: 8] = response_order_id_r[23:16];
                soup_rx_data[14*8 +: 8] = response_order_id_r[15:8];
                soup_rx_data[15*8 +: 8] = response_order_id_r[7:0];
                soup_rx_keep = 64'h00000000007fffff;
            end
            default: begin
                soup_rx_valid = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            response_state_r <= RESP_WAIT_LOGIN;
            response_order_id_r <= '0;
            response_price_r <= '0;
            response_quantity_r <= '0;
        end else begin
            case (response_state_r)
                RESP_WAIT_LOGIN: begin
                    if (soup_tx_valid && soup_tx_data[23:16] == 8'h4c)
                        response_state_r <= RESP_LOGIN;
                end
                RESP_LOGIN: begin
                    if (soup_rx_ready) response_state_r <= RESP_WAIT;
                end
                RESP_WAIT: begin
                    if (soup_tx_valid && soup_tx_data[23:16] == 8'h55) begin
                        response_order_id_r <= {
                            soup_tx_data[39:32], soup_tx_data[47:40],
                            soup_tx_data[55:48], soup_tx_data[63:56]
                        };
                        response_quantity_r <= {
                            soup_tx_data[79:72], soup_tx_data[87:80],
                            soup_tx_data[95:88], soup_tx_data[103:96]
                        };
                        response_price_r <= {
                            soup_tx_data[207:200], soup_tx_data[215:208],
                            soup_tx_data[223:216], soup_tx_data[231:224]
                        };
                        response_state_r <=
                            (soup_tx_data[31:24] == 8'h58) ?
                            RESP_CANCEL : RESP_ACK_0;
                    end
                end
                RESP_ACK_0: begin
                    if (soup_rx_ready) response_state_r <= RESP_ACK_1;
                end
                RESP_ACK_1: begin
                    if (soup_rx_ready) response_state_r <= RESP_FILL;
                end
                RESP_FILL: begin
                    if (soup_rx_ready) response_state_r <= RESP_WAIT;
                end
                default: begin
                    if (soup_rx_ready) response_state_r <= RESP_WAIT;
                end
            endcase
        end
    end

    (* keep_hierarchy = "yes", dont_touch = "yes" *)
    market_parser_100g_ouch5_top #(
        .FEED_UDP_PORT(16'd5000),
        .NUM_SYMBOLS(4),
        .SYMBOL_LOCATES({16'h4444, 16'h3333, 16'h2222, 16'h1234}),
        .OUCH_SYMBOLS({
            64'h4444444420202020, 64'h4343434320202020,
            64'h4242424220202020, 64'h5445535420202020
        }),
        .ORDER_TABLE_DEPTH(8),
        .SOUP_WATCHDOG_CYCLES(4096),
        .SOUP_CLIENT_HEARTBEAT_CYCLES(4096)
    ) ouch5_top_i (
        .clk(clk), .rst(rst), .feed_recover(1'b0), .feed_activate(1'b0),
        .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep), .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(1'b0), .strategy_enable(1'b1), .kill_switch(1'b0),
        .position_clear(1'b0), .max_spread_ticks(32'd100),
        .min_top_shares(32'd1), .imbalance_shift(3'd1),
        .order_quantity(32'd2), .max_abs_position(32'd10),
        .egress_risk_enable(1'b1), .max_egress_order_quantity(32'd10),
        .min_egress_order_price(32'd1),
        .max_egress_order_price(32'hffffffff),
        .max_outstanding_orders(16'd4),
        .max_new_orders_per_window(16'd8),
        .transport_connected(1'b1), .soup_login_valid(1'b1),
        .soup_login_ready(),
        .soup_login_username(48'h202020202020),
        .soup_login_password(80'h20202020202020202020),
        .soup_requested_session(80'h20202020202020202020),
        .soup_requested_sequence(64'd1),
        .soup_logout_valid(1'b0), .soup_logout_ready(),
        .soup_tx_valid(soup_tx_valid), .soup_tx_ready(1'b1),
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
        .accepted_intent_count(), .busy_intent_count(), .new_command_count(),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(), .cancel_command_count(), .cancel_ack_count(),
        .lifecycle_fill_count(lifecycle_fill_count),
        .protocol_error_count(protocol_error_count),
        .generated_intent_count(generated_intent_count),
        .applied_fill_count(applied_fill_count),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
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

    always_ff @(posedge clk) begin
        if (rst) begin
            status_sample_r <= '0;
            status <= '0;
        end else begin
            status_sample_r <= {
                cmac_axis_accepted_packet_count[3:0],
                generated_intent_count[3:0], passed_new_count[3:0],
                ouch_encoded_new_count[3:0],
                acknowledged_order_count[3:0], lifecycle_fill_count[3:0],
                applied_fill_count[3:0], position_by_symbol[3:0]
            };
            status <= {status[30:0], status[31]} ^ status_sample_r ^
                {16'd0, gateway_session_active, soup_tx_valid,
                 response_state_r, working_order_mask, live_order_mask,
                 outstanding_order_count[1:0]} ^ 32'h4f55_4348;
        end
    end
endmodule
`default_nettype wire
