`default_nettype none
// Compact routed harness for packet-to-order lifecycle timing. A deterministic
// exchange responder acknowledges and fills transmitted new orders.
module market_parser_100g_cmac_axis_order_impl_harness (
    input  wire logic   clk,
    input  wire logic   rst,
    output logic [31:0] status
);
    localparam logic [3:0] LAST_BEAT_INDEX = 4'd8;
    localparam logic [1:0] RESP_IDLE = 2'd0;
    localparam logic [1:0] RESP_ACK  = 2'd1;
    localparam logic [1:0] RESP_FILL = 2'd2;
    localparam logic [1:0] RESP_CANCEL_ACK = 2'd3;

    logic         rx_axis_tvalid;
    logic [511:0] rx_axis_tdata;
    logic [ 63:0] rx_axis_tkeep;
    logic         rx_axis_tlast;
    logic         rx_axis_tuser;

    (* keep = "true" *) logic        order_cmd_valid;
    (* keep = "true" *) logic        order_cmd_cancel;
    (* keep = "true" *) logic [63:0] order_cmd_id;
    (* keep = "true" *) logic [15:0] order_cmd_stock_locate;
    (* keep = "true" *) logic        order_cmd_side;
    (* keep = "true" *) logic [31:0] order_cmd_price;
    (* keep = "true" *) logic [31:0] order_cmd_quantity;
    (* keep = "true" *) logic [47:0] order_cmd_timestamp;

    logic        exchange_event_valid;
    logic [ 1:0] exchange_event_type;
    logic [63:0] exchange_event_order_id;
    logic [31:0] exchange_event_price;
    logic [31:0] exchange_event_quantity;
    logic [ 1:0] exchange_response_state;
    logic [63:0] response_order_id;
    logic [31:0] response_price;
    logic [31:0] response_quantity;

    logic        s_axi_awready;
    logic        s_axi_wready;
    logic [ 1:0] s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [ 1:0] s_axi_rresp;
    logic        s_axi_rvalid;

    (* keep = "true" *) logic [127:0] position_by_symbol;
    (* keep = "true" *) logic [3:0] working_order_mask;
    (* keep = "true" *) logic [3:0] live_order_mask;
    (* keep = "true" *) logic [127:0] leaves_quantity_by_symbol;
    (* keep = "true" *) logic [15:0] outstanding_order_count;
    (* keep = "true" *) logic [31:0] accepted_intent_count;
    (* keep = "true" *) logic [31:0] busy_intent_count;
    (* keep = "true" *) logic [31:0] new_command_count;
    (* keep = "true" *) logic [31:0] acknowledged_order_count;
    (* keep = "true" *) logic [31:0] lifecycle_fill_count;
    (* keep = "true" *) logic [31:0] protocol_error_count;
    (* keep = "true" *) logic [31:0] generated_intent_count;
    (* keep = "true" *) logic [31:0] applied_fill_count;
    (* keep = "true" *) logic [31:0] cmac_axis_accepted_packet_count;
    (* keep = "true" *) logic [31:0] cmac_axis_overflow_packet_count;
    (* keep = "true" *) logic [31:0] cmac_axis_dropped_beat_count;
    (* keep = "true" *) logic [31:0] book_quote_update_count;
    (* keep = "true" *) logic feed_healthy;

    logic [3:0] beat_index;
    logic [5:0] gap_count;
    logic [31:0] status_sample;

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

    function automatic logic [63:0] replay_keep(input logic [3:0] index);
        replay_keep = (index == LAST_BEAT_INDEX) ?
                      64'h00000001ffffffff : 64'hffffffffffffffff;
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_axis_tvalid <= 1'b0;
            rx_axis_tdata  <= '0;
            rx_axis_tkeep  <= '0;
            rx_axis_tlast  <= 1'b0;
            rx_axis_tuser  <= 1'b0;
            beat_index     <= '0;
            gap_count      <= 6'd16;
        end else if (gap_count != 6'd0) begin
            rx_axis_tvalid <= 1'b0;
            rx_axis_tdata  <= '0;
            rx_axis_tkeep  <= '0;
            rx_axis_tlast  <= 1'b0;
            rx_axis_tuser  <= 1'b0;
            gap_count      <= gap_count - 6'd1;
        end else begin
            rx_axis_tvalid <= 1'b1;
            rx_axis_tdata  <= replay_data(beat_index);
            rx_axis_tkeep  <= replay_keep(beat_index);
            rx_axis_tlast  <= beat_index == LAST_BEAT_INDEX;
            rx_axis_tuser  <= 1'b0;
            if (beat_index == LAST_BEAT_INDEX) begin
                beat_index <= '0;
                gap_count  <= 6'd32;
            end else begin
                beat_index <= beat_index + 4'd1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            exchange_response_state  <= RESP_IDLE;
            exchange_event_valid     <= 1'b0;
            exchange_event_type      <= '0;
            exchange_event_order_id  <= '0;
            exchange_event_price     <= '0;
            exchange_event_quantity  <= '0;
            response_order_id        <= '0;
            response_price           <= '0;
            response_quantity        <= '0;
        end else begin
            exchange_event_valid <= 1'b0;
            case (exchange_response_state)
                RESP_IDLE: begin
                    if (order_cmd_valid) begin
                        response_order_id <= order_cmd_id;
                        response_price <= order_cmd_price;
                        response_quantity <= order_cmd_quantity;
                        exchange_response_state <= order_cmd_cancel ?
                                                   RESP_CANCEL_ACK : RESP_ACK;
                    end
                end
                RESP_ACK: begin
                    exchange_event_valid    <= 1'b1;
                    exchange_event_type     <= 2'd0;
                    exchange_event_order_id <= response_order_id;
                    exchange_event_price    <= '0;
                    exchange_event_quantity <= '0;
                    exchange_response_state <= RESP_FILL;
                end
                RESP_FILL: begin
                    exchange_event_valid    <= 1'b1;
                    exchange_event_type     <= 2'd2;
                    exchange_event_order_id <= response_order_id;
                    exchange_event_price    <= response_price;
                    exchange_event_quantity <= response_quantity;
                    exchange_response_state <= RESP_IDLE;
                end
                default: begin
                    exchange_event_valid    <= 1'b1;
                    exchange_event_type     <= 2'd3;
                    exchange_event_order_id <= response_order_id;
                    exchange_event_price    <= '0;
                    exchange_event_quantity <= '0;
                    exchange_response_state <= RESP_IDLE;
                end
            endcase
        end
    end

    (* keep_hierarchy = "yes", dont_touch = "yes" *)
    market_parser_100g_cmac_axis_order_top #(
        .FEED_UDP_PORT(16'd5000),
        .NUM_SYMBOLS(4),
        .SYMBOL_LOCATES({16'h4444, 16'h3333, 16'h2222, 16'h1234}),
        .CMAC_RX_FIFO_DEPTH(64),
        .ORDER_TABLE_DEPTH(8)
    ) order_top_i (
        .clk(clk),
        .rst(rst),
        .feed_recover(1'b0),
        .feed_activate(1'b0),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),
        .strategy_enable(1'b1),
        .kill_switch(1'b0),
        .position_clear(1'b0),
        .max_spread_ticks(32'd100),
        .min_top_shares(32'd1),
        .imbalance_shift(3'd1),
        .order_quantity(32'd2),
        .max_abs_position(32'd10),
        .order_cmd_valid(order_cmd_valid),
        .order_cmd_ready(1'b1),
        .order_cmd_cancel(order_cmd_cancel),
        .order_cmd_id(order_cmd_id),
        .order_cmd_stock_locate(order_cmd_stock_locate),
        .order_cmd_side(order_cmd_side),
        .order_cmd_price(order_cmd_price),
        .order_cmd_quantity(order_cmd_quantity),
        .order_cmd_timestamp(order_cmd_timestamp),
        .exchange_event_valid(exchange_event_valid),
        .exchange_event_ready(),
        .exchange_event_type(exchange_event_type),
        .exchange_event_order_id(exchange_event_order_id),
        .exchange_event_price(exchange_event_price),
        .exchange_event_quantity(exchange_event_quantity),
        .s_axi_awaddr(12'd0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(32'd0),
        .s_axi_wstrb(4'd0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(1'b1),
        .s_axi_araddr(12'd0),
        .s_axi_arvalid(1'b0),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(1'b1),
        .position_by_symbol(position_by_symbol),
        .working_order_mask(working_order_mask),
        .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(leaves_quantity_by_symbol),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(accepted_intent_count),
        .busy_intent_count(busy_intent_count),
        .untracked_intent_count(),
        .new_command_count(new_command_count),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(),
        .cancel_command_count(),
        .cancel_ack_count(),
        .lifecycle_fill_count(lifecycle_fill_count),
        .canceled_before_send_count(),
        .protocol_error_count(protocol_error_count),
        .evaluated_quote_count(),
        .generated_intent_count(generated_intent_count),
        .control_suppressed_count(),
        .market_suppressed_count(),
        .risk_suppressed_count(),
        .applied_fill_count(applied_fill_count),
        .untracked_fill_count(),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count(cmac_axis_dropped_beat_count),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy),
        .feed_rebuilding(),
        .feed_gap_count(),
        .feed_timeout_count()
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            status_sample <= '0;
            status <= '0;
        end else begin
            status_sample <= {
                cmac_axis_accepted_packet_count[3:0],
                book_quote_update_count[3:0],
                generated_intent_count[3:0],
                accepted_intent_count[3:0],
                new_command_count[3:0],
                acknowledged_order_count[3:0],
                lifecycle_fill_count[3:0],
                position_by_symbol[3:0]
            };
            status <= {status[30:0], status[31]}
                    ^ status_sample
                    ^ {20'd0, s_axi_awready, s_axi_wready, s_axi_bvalid,
                              s_axi_arready, s_axi_rvalid, order_cmd_valid,
                              exchange_event_valid, feed_healthy,
                              working_order_mask}
                    ^ 32'h7f4a_7c15;
        end
    end

endmodule
`default_nettype wire
