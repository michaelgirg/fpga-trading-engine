`default_nettype none
// Compact implementation wrapper for routed timing checks of the complete
// source-only packet-to-intent path. Accepted intents are replayed as fills so
// the position and risk feedback logic remains active in the routed design.
module market_parser_100g_cmac_axis_decision_impl_harness (
    input  wire logic   clk,
    input  wire logic   rst,
    output logic [31:0] status
);
    localparam logic [3:0] LAST_BEAT_INDEX = 4'd8;

    logic         rx_axis_tvalid;
    logic [511:0] rx_axis_tdata;
    logic [ 63:0] rx_axis_tkeep;
    logic         rx_axis_tlast;
    logic         rx_axis_tuser;

    (* keep = "true" *) logic         intent_valid;
    (* keep = "true" *) logic [15:0]  intent_stock_locate;
    (* keep = "true" *) logic         intent_side;
    (* keep = "true" *) logic [31:0]  intent_price;
    (* keep = "true" *) logic [31:0]  intent_quantity;
    (* keep = "true" *) logic [47:0]  intent_timestamp;
    (* keep = "true" *) logic [127:0] position_by_symbol;

    (* keep = "true" *) logic         fill_valid;
    (* keep = "true" *) logic [15:0]  fill_stock_locate;
    (* keep = "true" *) logic         fill_side;
    (* keep = "true" *) logic [31:0]  fill_quantity;

    logic        s_axi_awready;
    logic        s_axi_wready;
    logic [ 1:0] s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [ 1:0] s_axi_rresp;
    logic        s_axi_rvalid;

    (* keep = "true" *) logic [31:0] cmac_axis_accepted_packet_count;
    (* keep = "true" *) logic [31:0] cmac_axis_overflow_packet_count;
    (* keep = "true" *) logic [31:0] cmac_axis_dropped_beat_count;
    (* keep = "true" *) logic [15:0] cmac_axis_fifo_level;
    (* keep = "true" *) logic [15:0] cmac_axis_fifo_high_watermark;
    (* keep = "true" *) logic [15:0] cmac_axis_buffered_packet_count;

    (* keep = "true" *) logic [31:0] book_accepted_event_count;
    (* keep = "true" *) logic [31:0] book_applied_event_count;
    (* keep = "true" *) logic [31:0] book_ignored_event_count;
    (* keep = "true" *) logic [31:0] book_untracked_event_count;
    (* keep = "true" *) logic [31:0] book_table_overflow_count;
    (* keep = "true" *) logic [31:0] book_quote_update_count;

    (* keep = "true" *) logic [31:0] evaluated_quote_count;
    (* keep = "true" *) logic [31:0] generated_intent_count;
    (* keep = "true" *) logic [31:0] control_suppressed_count;
    (* keep = "true" *) logic [31:0] market_suppressed_count;
    (* keep = "true" *) logic [31:0] risk_suppressed_count;
    (* keep = "true" *) logic [31:0] applied_fill_count;
    (* keep = "true" *) logic [31:0] untracked_fill_count;

    (* keep = "true" *) logic        feed_healthy;
    (* keep = "true" *) logic        feed_rebuilding;
    (* keep = "true" *) logic        feed_rebuild_ready;
    (* keep = "true" *) logic [31:0] feed_gap_count;
    (* keep = "true" *) logic [31:0] feed_suppressed_event_count;
    (* keep = "true" *) logic [31:0] feed_idle_cycles;
    (* keep = "true" *) logic [31:0] feed_timeout_count;
    (* keep = "true" *) logic [31:0] feed_activation_reject_count;
    (* keep = "true" *) logic [31:0] feed_session_change_count;
    (* keep = "true" *) logic [31:0] feed_end_of_session_count;

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
            rx_axis_tlast  <= (beat_index == LAST_BEAT_INDEX);
            rx_axis_tuser  <= 1'b0;

            if (beat_index == LAST_BEAT_INDEX) begin
                beat_index <= '0;
                gap_count  <= 6'd32;
            end else begin
                beat_index <= beat_index + 4'd1;
            end
        end
    end

    // Model a deterministic one-cycle-later exchange fill acknowledgement.
    always_ff @(posedge clk) begin
        if (rst) begin
            fill_valid        <= 1'b0;
            fill_stock_locate <= '0;
            fill_side         <= 1'b0;
            fill_quantity     <= '0;
        end else begin
            fill_valid <= intent_valid;
            if (intent_valid) begin
                fill_stock_locate <= intent_stock_locate;
                fill_side         <= intent_side;
                fill_quantity     <= intent_quantity;
            end
        end
    end

    (* keep_hierarchy = "yes", dont_touch = "yes" *)
    market_parser_100g_cmac_axis_decision_top #(
        .FEED_UDP_PORT     (16'd5000),
        .NUM_SYMBOLS       (4),
        .SYMBOL_LOCATES    ({16'h4444, 16'h3333, 16'h2222, 16'h1234}),
        .CMAC_RX_FIFO_DEPTH(64),
        .ORDER_TABLE_DEPTH (8)
    ) decision_top_i (
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
        .fill_valid(fill_valid),
        .fill_stock_locate(fill_stock_locate),
        .fill_side(fill_side),
        .fill_quantity(fill_quantity),
        .intent_valid(intent_valid),
        .intent_ready(1'b1),
        .intent_stock_locate(intent_stock_locate),
        .intent_side(intent_side),
        .intent_price(intent_price),
        .intent_quantity(intent_quantity),
        .intent_timestamp(intent_timestamp),
        .position_by_symbol(position_by_symbol),
        .evaluated_quote_count(evaluated_quote_count),
        .generated_intent_count(generated_intent_count),
        .control_suppressed_count(control_suppressed_count),
        .market_suppressed_count(market_suppressed_count),
        .risk_suppressed_count(risk_suppressed_count),
        .applied_fill_count(applied_fill_count),
        .untracked_fill_count(untracked_fill_count),
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
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count(cmac_axis_dropped_beat_count),
        .cmac_axis_fifo_level(cmac_axis_fifo_level),
        .cmac_axis_fifo_high_watermark(cmac_axis_fifo_high_watermark),
        .cmac_axis_buffered_packet_count(cmac_axis_buffered_packet_count),
        .book_accepted_event_count(book_accepted_event_count),
        .book_applied_event_count(book_applied_event_count),
        .book_ignored_event_count(book_ignored_event_count),
        .book_untracked_event_count(book_untracked_event_count),
        .book_table_overflow_count(book_table_overflow_count),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy),
        .feed_rebuilding(feed_rebuilding),
        .feed_rebuild_ready(feed_rebuild_ready),
        .feed_gap_count(feed_gap_count),
        .feed_suppressed_event_count(feed_suppressed_event_count),
        .feed_idle_cycles(feed_idle_cycles),
        .feed_timeout_count(feed_timeout_count),
        .feed_activation_reject_count(feed_activation_reject_count),
        .feed_session_change_count(feed_session_change_count),
        .feed_end_of_session_count(feed_end_of_session_count)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            status_sample <= 32'd0;
            status        <= 32'd0;
        end else begin
            status_sample <= {
                cmac_axis_accepted_packet_count[3:0],
                cmac_axis_fifo_high_watermark[3:0],
                book_quote_update_count[3:0],
                evaluated_quote_count[3:0],
                generated_intent_count[3:0],
                applied_fill_count[3:0],
                position_by_symbol[3:0],
                intent_price[3:0]
            };
            status <= {status[30:0], status[31]}
                    ^ status_sample
                    ^ {19'd0, s_axi_awready, s_axi_wready, s_axi_bvalid,
                              s_axi_arready, s_axi_rvalid, intent_valid,
                              fill_valid, rx_axis_tvalid, rx_axis_tlast,
                              cmac_axis_overflow_packet_count[0],
                              cmac_axis_dropped_beat_count[0], feed_rebuilding,
                              feed_healthy}
                    ^ 32'h9e37_79b9;
        end
    end

endmodule
`default_nettype wire
