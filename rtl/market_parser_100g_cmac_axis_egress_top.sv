`default_nettype none
// Complete source-only packet-to-order path with an independent final egress
// risk boundary. Local risk rejects are reconciled like venue rejects.
module market_parser_100g_cmac_axis_egress_top #(
    parameter logic [15:0] FEED_UDP_PORT = 16'd5000,
    parameter int NUM_SYMBOLS = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter int CMAC_RX_FIFO_DEPTH = 64,
    parameter int STRIP_FIFO_DEPTH = 8,
    parameter int PACKET_BEATS_MAX = 32,
    parameter int DESC_FIFO_DEPTH = 32,
    parameter int EXTRACTION_WINDOW_BYTES = 256,
    parameter int EVENT_FIFO_DEPTH = 16,
    parameter int ORDER_TABLE_DEPTH = 16,
    parameter int RATE_WINDOW_CYCLES = 1024,
    parameter logic [31:0] BUILD_ID = 32'h4d50_5253,
    parameter logic [31:0] FEED_TIMEOUT_CYCLES_DEFAULT = 32'd322_400_000
) (
    input  wire logic                         clk,
    input  wire logic                         rst,
    input  wire logic                         feed_recover,
    input  wire logic                         feed_activate,
    input  wire logic                         rx_axis_tvalid,
    input  wire logic [511:0]                 rx_axis_tdata,
    input  wire logic [ 63:0]                 rx_axis_tkeep,
    input  wire logic                         rx_axis_tlast,
    input  wire logic                         rx_axis_tuser,
    input  wire logic                         strategy_enable,
    input  wire logic                         kill_switch,
    input  wire logic                         position_clear,
    input  wire logic [31:0]                  max_spread_ticks,
    input  wire logic [31:0]                  min_top_shares,
    input  wire logic [ 2:0]                  imbalance_shift,
    input  wire logic [31:0]                  order_quantity,
    input  wire logic [31:0]                  max_abs_position,

    input  wire logic                         egress_risk_enable,
    input  wire logic                         gateway_session_active,
    input  wire logic [31:0]                  max_egress_order_quantity,
    input  wire logic [31:0]                  min_egress_order_price,
    input  wire logic [31:0]                  max_egress_order_price,
    input  wire logic [15:0]                  max_outstanding_orders,
    input  wire logic [15:0]                  max_new_orders_per_window,

    output logic                              order_cmd_valid,
    input  wire logic                         order_cmd_ready,
    output logic                              order_cmd_cancel,
    output logic [63:0]                       order_cmd_id,
    output logic [15:0]                       order_cmd_stock_locate,
    output logic                              order_cmd_side,
    output logic [31:0]                       order_cmd_price,
    output logic [31:0]                       order_cmd_quantity,
    output logic [47:0]                       order_cmd_timestamp,

    input  wire logic                         exchange_event_valid,
    output logic                              exchange_event_ready,
    input  wire logic [ 1:0]                  exchange_event_type,
    input  wire logic [63:0]                  exchange_event_order_id,
    input  wire logic [31:0]                  exchange_event_price,
    input  wire logic [31:0]                  exchange_event_quantity,

    input  wire logic [11:0]                  s_axi_awaddr,
    input  wire logic                         s_axi_awvalid,
    output logic                              s_axi_awready,
    input  wire logic [31:0]                  s_axi_wdata,
    input  wire logic [ 3:0]                  s_axi_wstrb,
    input  wire logic                         s_axi_wvalid,
    output logic                              s_axi_wready,
    output logic [ 1:0]                       s_axi_bresp,
    output logic                              s_axi_bvalid,
    input  wire logic                         s_axi_bready,
    input  wire logic [11:0]                  s_axi_araddr,
    input  wire logic                         s_axi_arvalid,
    output logic                              s_axi_arready,
    output logic [31:0]                       s_axi_rdata,
    output logic [ 1:0]                       s_axi_rresp,
    output logic                              s_axi_rvalid,
    input  wire logic                         s_axi_rready,

    output logic [NUM_SYMBOLS*32-1:0]         position_by_symbol,
    output logic [NUM_SYMBOLS-1:0]            working_order_mask,
    output logic [NUM_SYMBOLS-1:0]            live_order_mask,
    output logic [NUM_SYMBOLS*32-1:0]         leaves_quantity_by_symbol,
    output logic [15:0]                       outstanding_order_count,
    output logic [31:0]                       accepted_intent_count,
    output logic [31:0]                       busy_intent_count,
    output logic [31:0]                       new_command_count,
    output logic [31:0]                       acknowledged_order_count,
    output logic [31:0]                       rejected_order_count,
    output logic [31:0]                       cancel_command_count,
    output logic [31:0]                       cancel_ack_count,
    output logic [31:0]                       lifecycle_fill_count,
    output logic [31:0]                       protocol_error_count,
    output logic [31:0]                       generated_intent_count,
    output logic [31:0]                       applied_fill_count,
    output logic [31:0]                       cmac_axis_accepted_packet_count,
    output logic [31:0]                       cmac_axis_overflow_packet_count,
    output logic [31:0]                       cmac_axis_dropped_beat_count,
    output logic [31:0]                       book_quote_update_count,
    output logic                              feed_healthy,
    output logic [31:0]                       passed_new_count,
    output logic [31:0]                       passed_cancel_count,
    output logic [31:0]                       control_reject_count,
    output logic [31:0]                       quantity_reject_count,
    output logic [31:0]                       price_reject_count,
    output logic [31:0]                       outstanding_reject_count,
    output logic [31:0]                       rate_reject_count,
    output logic [ 2:0]                       last_local_reject_reason
);
    localparam logic [1:0] EVENT_REJECT = 2'd1;

    logic lifecycle_cmd_valid;
    logic lifecycle_cmd_ready;
    logic lifecycle_cmd_cancel;
    logic [63:0] lifecycle_cmd_id;
    logic [15:0] lifecycle_cmd_stock_locate;
    logic lifecycle_cmd_side;
    logic [31:0] lifecycle_cmd_price;
    logic [31:0] lifecycle_cmd_quantity;
    logic [47:0] lifecycle_cmd_timestamp;

    logic local_reject_valid;
    logic local_reject_ready;
    logic [63:0] local_reject_order_id;
    logic [2:0] local_reject_reason;
    logic manager_event_valid;
    logic manager_event_ready;
    logic [1:0] manager_event_type;
    logic [63:0] manager_event_order_id;
    logic [31:0] manager_event_price;
    logic [31:0] manager_event_quantity;
    logic effective_kill_switch;

    assign effective_kill_switch = kill_switch || !gateway_session_active;
    assign manager_event_valid = local_reject_valid || exchange_event_valid;
    assign manager_event_type = local_reject_valid ? EVENT_REJECT :
                                                      exchange_event_type;
    assign manager_event_order_id = local_reject_valid ?
                                    local_reject_order_id :
                                    exchange_event_order_id;
    assign manager_event_price = local_reject_valid ? 32'd0 :
                                                      exchange_event_price;
    assign manager_event_quantity = local_reject_valid ? 32'd0 :
                                                         exchange_event_quantity;
    assign local_reject_ready = manager_event_ready;
    assign exchange_event_ready = manager_event_ready && !local_reject_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            last_local_reject_reason <= '0;
        end else if (local_reject_valid && local_reject_ready) begin
            last_local_reject_reason <= local_reject_reason;
        end
    end

    market_parser_100g_cmac_axis_order_top #(
        .FEED_UDP_PORT(FEED_UDP_PORT),
        .NUM_SYMBOLS(NUM_SYMBOLS),
        .SYMBOL_LOCATES(SYMBOL_LOCATES),
        .CMAC_RX_FIFO_DEPTH(CMAC_RX_FIFO_DEPTH),
        .STRIP_FIFO_DEPTH(STRIP_FIFO_DEPTH),
        .PACKET_BEATS_MAX(PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH(DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES(EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH(EVENT_FIFO_DEPTH),
        .ORDER_TABLE_DEPTH(ORDER_TABLE_DEPTH),
        .BUILD_ID(BUILD_ID),
        .FEED_TIMEOUT_CYCLES_DEFAULT(FEED_TIMEOUT_CYCLES_DEFAULT)
    ) order_top_i (
        .clk(clk), .rst(rst), .feed_recover(feed_recover),
        .feed_activate(feed_activate), .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tdata(rx_axis_tdata), .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tlast(rx_axis_tlast), .rx_axis_tuser(rx_axis_tuser),
        .strategy_enable(strategy_enable),
        .kill_switch(effective_kill_switch),
        .position_clear(position_clear), .max_spread_ticks(max_spread_ticks),
        .min_top_shares(min_top_shares), .imbalance_shift(imbalance_shift),
        .order_quantity(order_quantity), .max_abs_position(max_abs_position),
        .order_cmd_valid(lifecycle_cmd_valid),
        .order_cmd_ready(lifecycle_cmd_ready),
        .order_cmd_cancel(lifecycle_cmd_cancel),
        .order_cmd_id(lifecycle_cmd_id),
        .order_cmd_stock_locate(lifecycle_cmd_stock_locate),
        .order_cmd_side(lifecycle_cmd_side),
        .order_cmd_price(lifecycle_cmd_price),
        .order_cmd_quantity(lifecycle_cmd_quantity),
        .order_cmd_timestamp(lifecycle_cmd_timestamp),
        .exchange_event_valid(manager_event_valid),
        .exchange_event_ready(manager_event_ready),
        .exchange_event_type(manager_event_type),
        .exchange_event_order_id(manager_event_order_id),
        .exchange_event_price(manager_event_price),
        .exchange_event_quantity(manager_event_quantity),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .position_by_symbol(position_by_symbol),
        .working_order_mask(working_order_mask),
        .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(leaves_quantity_by_symbol),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(accepted_intent_count),
        .busy_intent_count(busy_intent_count), .untracked_intent_count(),
        .new_command_count(new_command_count),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(rejected_order_count),
        .cancel_command_count(cancel_command_count),
        .cancel_ack_count(cancel_ack_count),
        .lifecycle_fill_count(lifecycle_fill_count),
        .canceled_before_send_count(),
        .protocol_error_count(protocol_error_count),
        .evaluated_quote_count(),
        .generated_intent_count(generated_intent_count),
        .control_suppressed_count(), .market_suppressed_count(),
        .risk_suppressed_count(), .applied_fill_count(applied_fill_count),
        .untracked_fill_count(),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count(cmac_axis_dropped_beat_count),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy), .feed_rebuilding(), .feed_gap_count(),
        .feed_timeout_count()
    );

    market_parser_order_risk_guard #(
        .RATE_WINDOW_CYCLES(RATE_WINDOW_CYCLES)
    ) risk_guard_i (
        .clk(clk), .rst(rst), .risk_enable(egress_risk_enable),
        .session_active(gateway_session_active), .kill_switch(kill_switch),
        .max_order_quantity(max_egress_order_quantity),
        .min_order_price(min_egress_order_price),
        .max_order_price(max_egress_order_price),
        .max_outstanding_orders(max_outstanding_orders),
        .max_new_orders_per_window(max_new_orders_per_window),
        .outstanding_order_count(outstanding_order_count),
        .command_valid(lifecycle_cmd_valid),
        .command_ready(lifecycle_cmd_ready),
        .command_cancel(lifecycle_cmd_cancel), .command_id(lifecycle_cmd_id),
        .command_stock_locate(lifecycle_cmd_stock_locate),
        .command_side(lifecycle_cmd_side), .command_price(lifecycle_cmd_price),
        .command_quantity(lifecycle_cmd_quantity),
        .command_timestamp(lifecycle_cmd_timestamp),
        .guarded_command_valid(order_cmd_valid),
        .guarded_command_ready(order_cmd_ready),
        .guarded_command_cancel(order_cmd_cancel),
        .guarded_command_id(order_cmd_id),
        .guarded_command_stock_locate(order_cmd_stock_locate),
        .guarded_command_side(order_cmd_side),
        .guarded_command_price(order_cmd_price),
        .guarded_command_quantity(order_cmd_quantity),
        .guarded_command_timestamp(order_cmd_timestamp),
        .local_reject_valid(local_reject_valid),
        .local_reject_ready(local_reject_ready),
        .local_reject_order_id(local_reject_order_id),
        .local_reject_reason(local_reject_reason),
        .passed_new_count(passed_new_count),
        .passed_cancel_count(passed_cancel_count),
        .control_reject_count(control_reject_count),
        .quantity_reject_count(quantity_reject_count),
        .price_reject_count(price_reject_count),
        .outstanding_reject_count(outstanding_reject_count),
        .rate_reject_count(rate_reject_count)
    );
endmodule
`default_nettype wire
