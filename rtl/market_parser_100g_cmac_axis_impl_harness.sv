`default_nettype none
// =============================================================================
// Module: market_parser_100g_cmac_axis_impl_harness
// =============================================================================
// Implementation-only wrapper for routed timing checks of the CMAC AXIS
// multi-symbol strategy boundary. It keeps the source-only CMAC AXIS receive
// interface, packet bridge, guarded parser, and book bank internal, then
// exposes only clk, rst, and a compact status hash.
module market_parser_100g_cmac_axis_impl_harness (
    input  wire logic   clk,
    input  wire logic   rst,
    output logic [31:0] status
);
    localparam int REPLAY_BEATS = 9;
    localparam logic [3:0] LAST_BEAT_INDEX = 4'd8;

    logic         rx_axis_tvalid;
    logic [511:0] rx_axis_tdata;
    logic [ 63:0] rx_axis_tkeep;
    logic         rx_axis_tlast;
    logic         rx_axis_tuser;

    (* keep = "true" *) logic         quote_valid;
    (* keep = "true" *) logic [15:0]  quote_stock_locate;
    (* keep = "true" *) logic [31:0]  quote_bid_price;
    (* keep = "true" *) logic [31:0]  quote_bid_shares;
    (* keep = "true" *) logic [31:0]  quote_ask_price;
    (* keep = "true" *) logic [31:0]  quote_ask_shares;
    (* keep = "true" *) logic [47:0]  quote_timestamp;

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

    (* keep = "true" *) logic [31:0] cmac_accepted_frame_count;
    (* keep = "true" *) logic [31:0] cmac_dropped_frame_count;
    (* keep = "true" *) logic [31:0] cmac_header_error_count;
    (* keep = "true" *) logic [31:0] cmac_payload_packet_count;
    (* keep = "true" *) logic [15:0] cmac_payload_fifo_level;

    (* keep = "true" *) logic [31:0] book_accepted_event_count;
    (* keep = "true" *) logic [31:0] book_applied_event_count;
    (* keep = "true" *) logic [31:0] book_ignored_event_count;
    (* keep = "true" *) logic [31:0] book_untracked_event_count;
    (* keep = "true" *) logic [31:0] book_table_overflow_count;
    (* keep = "true" *) logic [31:0] book_quote_update_count;
    (* keep = "true" *) logic        feed_healthy;
    (* keep = "true" *) logic [31:0] feed_gap_count;
    (* keep = "true" *) logic [31:0] feed_suppressed_event_count;
    (* keep = "true" *) logic [31:0] feed_idle_cycles;
    (* keep = "true" *) logic [31:0] feed_timeout_count;

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
        if (index == 4'd8) begin
            replay_keep = 64'h00000001ffffffff;
        end else begin
            replay_keep = 64'hffffffffffffffff;
        end
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
        end else begin
            if (gap_count != 6'd0) begin
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
    end

    (* keep_hierarchy = "yes", dont_touch = "yes" *)
    market_parser_100g_cmac_axis_multi_strategy_top #(
        .FEED_UDP_PORT     (16'd5000),
        .NUM_SYMBOLS       (4),
        .SYMBOL_LOCATES    ({16'h4444, 16'h3333, 16'h2222, 16'h1234}),
        .CMAC_RX_FIFO_DEPTH(16),
        .ORDER_TABLE_DEPTH (8)
    ) cmac_axis_multi_strategy_top_i (
        .clk                            (clk),
        .rst                            (rst),
        .feed_recover                   (1'b0),
        .rx_axis_tvalid                 (rx_axis_tvalid),
        .rx_axis_tdata                  (rx_axis_tdata),
        .rx_axis_tkeep                  (rx_axis_tkeep),
        .rx_axis_tlast                  (rx_axis_tlast),
        .rx_axis_tuser                  (rx_axis_tuser),
        .quote_valid                    (quote_valid),
        .quote_ready                    (1'b1),
        .quote_stock_locate             (quote_stock_locate),
        .quote_bid_price                (quote_bid_price),
        .quote_bid_shares               (quote_bid_shares),
        .quote_ask_price                (quote_ask_price),
        .quote_ask_shares               (quote_ask_shares),
        .quote_timestamp                (quote_timestamp),
        .s_axi_awaddr                   (12'd0),
        .s_axi_awvalid                  (1'b0),
        .s_axi_awready                  (s_axi_awready),
        .s_axi_wdata                    (32'd0),
        .s_axi_wstrb                    (4'd0),
        .s_axi_wvalid                   (1'b0),
        .s_axi_wready                   (s_axi_wready),
        .s_axi_bresp                    (s_axi_bresp),
        .s_axi_bvalid                   (s_axi_bvalid),
        .s_axi_bready                   (1'b1),
        .s_axi_araddr                   (12'd0),
        .s_axi_arvalid                  (1'b0),
        .s_axi_arready                  (s_axi_arready),
        .s_axi_rdata                    (s_axi_rdata),
        .s_axi_rresp                    (s_axi_rresp),
        .s_axi_rvalid                   (s_axi_rvalid),
        .s_axi_rready                   (1'b1),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count   (cmac_axis_dropped_beat_count),
        .cmac_axis_fifo_level           (cmac_axis_fifo_level),
        .cmac_axis_fifo_high_watermark  (cmac_axis_fifo_high_watermark),
        .cmac_axis_buffered_packet_count(cmac_axis_buffered_packet_count),
        .cmac_accepted_frame_count      (cmac_accepted_frame_count),
        .cmac_dropped_frame_count       (cmac_dropped_frame_count),
        .cmac_header_error_count        (cmac_header_error_count),
        .cmac_payload_packet_count      (cmac_payload_packet_count),
        .cmac_payload_fifo_level        (cmac_payload_fifo_level),
        .book_accepted_event_count      (book_accepted_event_count),
        .book_applied_event_count       (book_applied_event_count),
        .book_ignored_event_count       (book_ignored_event_count),
        .book_untracked_event_count     (book_untracked_event_count),
        .book_table_overflow_count      (book_table_overflow_count),
        .book_quote_update_count        (book_quote_update_count),
        .feed_healthy                   (feed_healthy),
        .feed_gap_count                 (feed_gap_count),
        .feed_suppressed_event_count    (feed_suppressed_event_count),
        .feed_idle_cycles               (feed_idle_cycles),
        .feed_timeout_count             (feed_timeout_count)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            status_sample <= 32'd0;
            status        <= 32'd0;
        end else begin
            status_sample <= {
                cmac_axis_accepted_packet_count[3:0],
                cmac_axis_fifo_level[3:0] ^ cmac_axis_fifo_high_watermark[3:0],
                cmac_accepted_frame_count[3:0],
                cmac_payload_packet_count[3:0],
                feed_gap_count[3:0] ^ feed_timeout_count[3:0],
                feed_suppressed_event_count[3:0] ^ feed_idle_cycles[3:0],
                quote_bid_price[3:0],
                quote_ask_price[3:0]
            };
            status <= {status[30:0], status[31]}
                    ^ status_sample
                    ^ {20'd0, s_axi_awready, s_axi_wready, s_axi_bvalid,
                              s_axi_arready, s_axi_rvalid, quote_valid,
                              rx_axis_tvalid, rx_axis_tlast,
                              cmac_axis_overflow_packet_count[1:0],
                              cmac_axis_dropped_beat_count[0], feed_healthy}
                    ^ 32'h85eb_ca6b;
        end
    end

endmodule
`default_nettype wire
