`default_nettype none
// =============================================================================
// Module: market_parser_100g_cmac_ip_impl_harness
// =============================================================================
// U50 implementation shell for routing the generated CMAC IP with the full
// packet-to-book path. The parser uses the CMAC TX user clock, while the wide
// quote, AXI-Lite, and counter interfaces fold into one board status LED.
module market_parser_100g_cmac_ip_impl_harness (
    input  wire logic        cmc_clk_p,
    input  wire logic        cmc_clk_n,
    input  wire logic        pcie_perstn,

    input  wire logic        gt_ref_clk_p,
    input  wire logic        gt_ref_clk_n,
    input  wire logic [3:0]  gt_rxp_in,
    input  wire logic [3:0]  gt_rxn_in,
    output logic [3:0]       gt_txp_out,
    output logic [3:0]       gt_txn_out,

    output logic             status_led,
    output logic             hbm_cattrip
);
    logic        init_clk;
    logic        sys_reset;
    logic        gt_txusrclk2;
    logic        gt_ref_clk_out;
    logic [3:0]  gt_rxrecclkout;
    logic [3:0]  gt_powergoodout;
    logic        gt_rxusrclk2;
    logic        usr_rx_reset;
    logic        usr_tx_reset;
    logic        stat_rx_aligned;
    logic        stat_rx_status;
    logic        stat_rx_local_fault;
    logic        stat_rx_remote_fault;
    logic        stat_rx_received_local_fault;
    logic        tx_axis_tready;
    logic        tx_ovfout;
    logic        tx_unfout;
    logic [15:0] drp_do;
    logic        drp_rdy;

    logic        quote_valid;
    logic [15:0] quote_stock_locate;
    logic [31:0] quote_bid_price;
    logic [31:0] quote_bid_shares;
    logic [31:0] quote_ask_price;
    logic [31:0] quote_ask_shares;
    logic [47:0] quote_timestamp;

    logic        s_axi_awready;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;

    logic [31:0] cmac_axis_accepted_packet_count;
    logic [31:0] cmac_axis_overflow_packet_count;
    logic [31:0] cmac_axis_dropped_beat_count;
    logic [15:0] cmac_axis_fifo_level;
    logic [15:0] cmac_axis_fifo_high_watermark;
    logic [15:0] cmac_axis_buffered_packet_count;

    logic [31:0] cmac_accepted_frame_count;
    logic [31:0] cmac_dropped_frame_count;
    logic [31:0] cmac_header_error_count;
    logic [31:0] cmac_payload_packet_count;
    logic [15:0] cmac_payload_fifo_level;

    logic [31:0] book_accepted_event_count;
    logic [31:0] book_applied_event_count;
    logic [31:0] book_ignored_event_count;
    logic [31:0] book_table_overflow_count;
    logic [31:0] book_quote_update_count;

    (* keep = "true" *) logic [31:0] status_quote_r;
    (* keep = "true" *) logic [31:0] status_axis_r;
    (* keep = "true" *) logic [31:0] status_ingress_r;
    (* keep = "true" *) logic [31:0] status_book_r;
    (* keep = "true" *) logic [31:0] status_cmac_r;
    (* keep = "true" *) logic [31:0] status;

    IBUFDS #(
        .DIFF_TERM ("TRUE"),
        .IOSTANDARD("LVDS")
    ) cmc_clk_ibuf_i (
        .I (cmc_clk_p),
        .IB(cmc_clk_n),
        .O (init_clk)
    );

    assign sys_reset   = ~pcie_perstn;
    assign status_led  = status[0];
    assign hbm_cattrip = 1'b0;

    market_parser_100g_cmac_ip_strategy_top cmac_ip_strategy_top_i (
        .rx_clk                        (gt_txusrclk2),
        .init_clk                      (init_clk),
        .drp_clk                       (1'b0),
        .sys_reset                     (sys_reset),
        .gt_ref_clk_p                  (gt_ref_clk_p),
        .gt_ref_clk_n                  (gt_ref_clk_n),
        .gt_rxp_in                     (gt_rxp_in),
        .gt_rxn_in                     (gt_rxn_in),
        .gt_txp_out                    (gt_txp_out),
        .gt_txn_out                    (gt_txn_out),
        .gt_txusrclk2                  (gt_txusrclk2),
        .gt_ref_clk_out                (gt_ref_clk_out),
        .gt_rxrecclkout                (gt_rxrecclkout),
        .gt_powergoodout               (gt_powergoodout),
        .gt_rxusrclk2                  (gt_rxusrclk2),
        .usr_rx_reset                  (usr_rx_reset),
        .usr_tx_reset                  (usr_tx_reset),
        .stat_rx_aligned               (stat_rx_aligned),
        .stat_rx_status                (stat_rx_status),
        .stat_rx_local_fault           (stat_rx_local_fault),
        .stat_rx_remote_fault          (stat_rx_remote_fault),
        .stat_rx_received_local_fault  (stat_rx_received_local_fault),
        .tx_axis_tready                (tx_axis_tready),
        .tx_ovfout                     (tx_ovfout),
        .tx_unfout                     (tx_unfout),
        .drp_do                        (drp_do),
        .drp_rdy                       (drp_rdy),
        .quote_valid                   (quote_valid),
        .quote_ready                   (1'b1),
        .quote_stock_locate            (quote_stock_locate),
        .quote_bid_price               (quote_bid_price),
        .quote_bid_shares              (quote_bid_shares),
        .quote_ask_price               (quote_ask_price),
        .quote_ask_shares              (quote_ask_shares),
        .quote_timestamp               (quote_timestamp),
        .s_axi_awaddr                  (12'd0),
        .s_axi_awvalid                 (1'b0),
        .s_axi_awready                 (s_axi_awready),
        .s_axi_wdata                   (32'd0),
        .s_axi_wstrb                   (4'd0),
        .s_axi_wvalid                  (1'b0),
        .s_axi_wready                  (s_axi_wready),
        .s_axi_bresp                   (s_axi_bresp),
        .s_axi_bvalid                  (s_axi_bvalid),
        .s_axi_bready                  (1'b1),
        .s_axi_araddr                  (12'd0),
        .s_axi_arvalid                 (1'b0),
        .s_axi_arready                 (s_axi_arready),
        .s_axi_rdata                   (s_axi_rdata),
        .s_axi_rresp                   (s_axi_rresp),
        .s_axi_rvalid                  (s_axi_rvalid),
        .s_axi_rready                  (1'b1),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count  (cmac_axis_dropped_beat_count),
        .cmac_axis_fifo_level          (cmac_axis_fifo_level),
        .cmac_axis_fifo_high_watermark (cmac_axis_fifo_high_watermark),
        .cmac_axis_buffered_packet_count(cmac_axis_buffered_packet_count),
        .cmac_accepted_frame_count     (cmac_accepted_frame_count),
        .cmac_dropped_frame_count      (cmac_dropped_frame_count),
        .cmac_header_error_count       (cmac_header_error_count),
        .cmac_payload_packet_count     (cmac_payload_packet_count),
        .cmac_payload_fifo_level       (cmac_payload_fifo_level),
        .book_accepted_event_count     (book_accepted_event_count),
        .book_applied_event_count      (book_applied_event_count),
        .book_ignored_event_count      (book_ignored_event_count),
        .book_table_overflow_count     (book_table_overflow_count),
        .book_quote_update_count       (book_quote_update_count)
    );

    always_ff @(posedge gt_txusrclk2) begin
        if (sys_reset || usr_rx_reset) begin
            status_quote_r   <= 32'd0;
            status_axis_r    <= 32'd0;
            status_ingress_r <= 32'd0;
            status_book_r    <= 32'd0;
            status_cmac_r    <= 32'd0;
            status           <= 32'd0;
        end else begin
            status_quote_r <= quote_bid_price
                            ^ quote_bid_shares
                            ^ quote_ask_price
                            ^ quote_ask_shares
                            ^ quote_timestamp[31:0]
                            ^ {16'd0, quote_timestamp[47:32]}
                            ^ {16'd0, quote_stock_locate};
            status_axis_r <= cmac_axis_accepted_packet_count
                           ^ cmac_axis_overflow_packet_count
                           ^ cmac_axis_dropped_beat_count
                           ^ {cmac_axis_fifo_level,
                              cmac_axis_buffered_packet_count}
                           ^ {16'd0, cmac_axis_fifo_high_watermark};
            status_ingress_r <= cmac_accepted_frame_count
                              ^ cmac_dropped_frame_count
                              ^ cmac_header_error_count
                              ^ cmac_payload_packet_count
                              ^ {16'd0, cmac_payload_fifo_level};
            status_book_r <= book_accepted_event_count
                           ^ book_applied_event_count
                           ^ book_ignored_event_count
                           ^ book_table_overflow_count
                           ^ book_quote_update_count;
            status_cmac_r <= {28'd0, gt_powergoodout}
                           ^ {16'd0, drp_do}
                           ^ s_axi_rdata
                           ^ {28'd0, s_axi_bresp, s_axi_rresp}
                           ^ {16'd0,
                              usr_tx_reset,
                              stat_rx_aligned,
                              stat_rx_status,
                              stat_rx_local_fault,
                              stat_rx_remote_fault,
                              stat_rx_received_local_fault,
                              tx_axis_tready,
                              tx_ovfout,
                              tx_unfout,
                              drp_rdy,
                              quote_valid,
                              s_axi_awready,
                              s_axi_wready,
                              s_axi_bvalid,
                              s_axi_arready,
                              s_axi_rvalid};
            status <= {status[30:0], status[31]}
                    ^ status_quote_r
                    ^ status_axis_r
                    ^ status_ingress_r
                    ^ status_book_r
                    ^ status_cmac_r
                    ^ 32'h9e37_79b9;
        end
    end

endmodule
`default_nettype wire
