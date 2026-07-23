`default_nettype none
// Complete source-only market-data-to-OUCH path. The Soup interfaces carry
// logical packets above TCP; Ethernet/TCP transport is intentionally external.
module market_parser_100g_ouch5_top #(
    parameter logic [15:0] FEED_UDP_PORT = 16'd5000,
    parameter int NUM_SYMBOLS = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter logic [NUM_SYMBOLS*64-1:0] OUCH_SYMBOLS = {
        64'h4444444420202020,
        64'h4343434320202020,
        64'h4242424220202020,
        64'h4141414120202020
    },
    parameter int CMAC_RX_FIFO_DEPTH = 64,
    parameter int STRIP_FIFO_DEPTH = 8,
    parameter int PACKET_BEATS_MAX = 32,
    parameter int DESC_FIFO_DEPTH = 32,
    parameter int EXTRACTION_WINDOW_BYTES = 256,
    parameter int EVENT_FIFO_DEPTH = 16,
    parameter int ORDER_TABLE_DEPTH = 16,
    parameter int RATE_WINDOW_CYCLES = 1024,
    parameter int SOUP_WATCHDOG_CYCLES = 322_400_000,
    parameter int SOUP_CLIENT_HEARTBEAT_CYCLES = 322_400_000,
    parameter logic [31:0] BUILD_ID = 32'h4d50_5253,
    parameter logic [31:0] FEED_TIMEOUT_CYCLES_DEFAULT = 32'd322_400_000
) (
    input  wire logic                         clk,
    input  wire logic                         rst,
    input  wire logic                         feed_recover,
    input  wire logic                         feed_activate,
    input  wire logic                         rx_axis_tvalid,
    input  wire logic [511:0]                 rx_axis_tdata,
    input  wire logic [63:0]                  rx_axis_tkeep,
    input  wire logic                         rx_axis_tlast,
    input  wire logic                         rx_axis_tuser,
    input  wire logic                         strategy_enable,
    input  wire logic                         kill_switch,
    input  wire logic                         position_clear,
    input  wire logic [31:0]                  max_spread_ticks,
    input  wire logic [31:0]                  min_top_shares,
    input  wire logic [2:0]                   imbalance_shift,
    input  wire logic [31:0]                  order_quantity,
    input  wire logic [31:0]                  max_abs_position,
    input  wire logic                         egress_risk_enable,
    input  wire logic [31:0]                  max_egress_order_quantity,
    input  wire logic [31:0]                  min_egress_order_price,
    input  wire logic [31:0]                  max_egress_order_price,
    input  wire logic [15:0]                  max_outstanding_orders,
    input  wire logic [15:0]                  max_new_orders_per_window,

    input  wire logic                         transport_connected,
    input  wire logic                         soup_login_valid,
    output logic                              soup_login_ready,
    input  wire logic [47:0]                  soup_login_username,
    input  wire logic [79:0]                  soup_login_password,
    input  wire logic [79:0]                  soup_requested_session,
    input  wire logic [63:0]                  soup_requested_sequence,
    input  wire logic                         soup_logout_valid,
    output logic                              soup_logout_ready,

    output logic                              soup_tx_valid,
    input  wire logic                         soup_tx_ready,
    output logic [511:0]                      soup_tx_data,
    output logic [63:0]                       soup_tx_keep,
    output logic                              soup_tx_last,
    input  wire logic                         soup_rx_valid,
    output logic                              soup_rx_ready,
    input  wire logic [511:0]                 soup_rx_data,
    input  wire logic [63:0]                  soup_rx_keep,
    input  wire logic                         soup_rx_last,

    input  wire logic [11:0]                  s_axi_awaddr,
    input  wire logic                         s_axi_awvalid,
    output logic                              s_axi_awready,
    input  wire logic [31:0]                  s_axi_wdata,
    input  wire logic [3:0]                   s_axi_wstrb,
    input  wire logic                         s_axi_wvalid,
    output logic                              s_axi_wready,
    output logic [1:0]                        s_axi_bresp,
    output logic                              s_axi_bvalid,
    input  wire logic                         s_axi_bready,
    input  wire logic [11:0]                  s_axi_araddr,
    input  wire logic                         s_axi_arvalid,
    output logic                              s_axi_arready,
    output logic [31:0]                       s_axi_rdata,
    output logic [1:0]                        s_axi_rresp,
    output logic                              s_axi_rvalid,
    input  wire logic                         s_axi_rready,

    output logic                              gateway_session_active,
    output logic                              gateway_session_fault,
    output logic                              soup_login_in_progress,
    output logic [79:0]                       soup_current_session,
    output logic [63:0]                       soup_next_sequence,
    output logic [31:0]                       soup_login_request_count,
    output logic [31:0]                       soup_logout_request_count,
    output logic [31:0]                       soup_client_heartbeat_count,
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
    output logic [2:0]                        last_local_reject_reason,
    output logic [31:0]                       ouch_encoded_new_count,
    output logic [31:0]                       ouch_encoded_cancel_count,
    output logic [31:0]                       ouch_encode_reject_count,
    output logic [31:0]                       transport_reject_count,
    output logic [31:0]                       ouch_decoded_event_count,
    output logic [31:0]                       soup_heartbeat_count,
    output logic [31:0]                       soup_sequenced_packet_count,
    output logic [31:0]                       gateway_protocol_error_count
);
    logic order_cmd_valid;
    logic order_cmd_ready;
    logic order_cmd_cancel;
    logic [63:0] order_cmd_id;
    logic [15:0] order_cmd_stock_locate;
    logic order_cmd_side;
    logic [31:0] order_cmd_price;
    logic [31:0] order_cmd_quantity;
    logic [47:0] order_cmd_timestamp;
    logic exchange_event_valid;
    logic exchange_event_ready;
    logic [1:0] exchange_event_type;
    logic [63:0] exchange_event_order_id;
    logic [31:0] exchange_event_price;
    logic [31:0] exchange_event_quantity;
    logic [31:0] malformed_ouch_count;
    logic [31:0] unsupported_ouch_count;
    logic [31:0] malformed_soup_count;
    logic [31:0] watchdog_timeout_count;
    logic gateway_command_valid;
    logic gateway_command_ready;
    logic gateway_command_cancel;
    logic [63:0] gateway_command_id;
    logic [15:0] gateway_command_stock_locate;
    logic gateway_command_side;
    logic [31:0] gateway_command_price;
    logic [31:0] gateway_command_quantity;
    logic [1:0] command_fifo_occupancy;

    always_ff @(posedge clk) begin
        if (rst) begin
            gateway_protocol_error_count <= '0;
        end else begin
            gateway_protocol_error_count <= malformed_ouch_count +
                unsupported_ouch_count + malformed_soup_count +
                watchdog_timeout_count;
        end
    end

    market_parser_100g_cmac_axis_egress_top #(
        .FEED_UDP_PORT(FEED_UDP_PORT), .NUM_SYMBOLS(NUM_SYMBOLS),
        .SYMBOL_LOCATES(SYMBOL_LOCATES),
        .CMAC_RX_FIFO_DEPTH(CMAC_RX_FIFO_DEPTH),
        .STRIP_FIFO_DEPTH(STRIP_FIFO_DEPTH),
        .PACKET_BEATS_MAX(PACKET_BEATS_MAX),
        .DESC_FIFO_DEPTH(DESC_FIFO_DEPTH),
        .EXTRACTION_WINDOW_BYTES(EXTRACTION_WINDOW_BYTES),
        .EVENT_FIFO_DEPTH(EVENT_FIFO_DEPTH),
        .ORDER_TABLE_DEPTH(ORDER_TABLE_DEPTH),
        .RATE_WINDOW_CYCLES(RATE_WINDOW_CYCLES), .BUILD_ID(BUILD_ID),
        .FEED_TIMEOUT_CYCLES_DEFAULT(FEED_TIMEOUT_CYCLES_DEFAULT)
    ) egress_i (
        .clk(clk), .rst(rst), .feed_recover(feed_recover),
        .feed_activate(feed_activate), .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tdata(rx_axis_tdata), .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tlast(rx_axis_tlast), .rx_axis_tuser(rx_axis_tuser),
        .strategy_enable(strategy_enable), .kill_switch(kill_switch),
        .position_clear(position_clear), .max_spread_ticks(max_spread_ticks),
        .min_top_shares(min_top_shares), .imbalance_shift(imbalance_shift),
        .order_quantity(order_quantity), .max_abs_position(max_abs_position),
        .egress_risk_enable(egress_risk_enable),
        .gateway_session_active(gateway_session_active),
        .max_egress_order_quantity(max_egress_order_quantity),
        .min_egress_order_price(min_egress_order_price),
        .max_egress_order_price(max_egress_order_price),
        .max_outstanding_orders(max_outstanding_orders),
        .max_new_orders_per_window(max_new_orders_per_window),
        .order_cmd_valid(order_cmd_valid), .order_cmd_ready(order_cmd_ready),
        .order_cmd_cancel(order_cmd_cancel), .order_cmd_id(order_cmd_id),
        .order_cmd_stock_locate(order_cmd_stock_locate),
        .order_cmd_side(order_cmd_side), .order_cmd_price(order_cmd_price),
        .order_cmd_quantity(order_cmd_quantity),
        .order_cmd_timestamp(order_cmd_timestamp),
        .exchange_event_valid(exchange_event_valid),
        .exchange_event_ready(exchange_event_ready),
        .exchange_event_type(exchange_event_type),
        .exchange_event_order_id(exchange_event_order_id),
        .exchange_event_price(exchange_event_price),
        .exchange_event_quantity(exchange_event_quantity),
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
        .working_order_mask(working_order_mask), .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(leaves_quantity_by_symbol),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(accepted_intent_count),
        .busy_intent_count(busy_intent_count),
        .new_command_count(new_command_count),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(rejected_order_count),
        .cancel_command_count(cancel_command_count),
        .cancel_ack_count(cancel_ack_count),
        .lifecycle_fill_count(lifecycle_fill_count),
        .protocol_error_count(protocol_error_count),
        .generated_intent_count(generated_intent_count),
        .applied_fill_count(applied_fill_count),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(cmac_axis_overflow_packet_count),
        .cmac_axis_dropped_beat_count(cmac_axis_dropped_beat_count),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy), .passed_new_count(passed_new_count),
        .passed_cancel_count(passed_cancel_count),
        .control_reject_count(control_reject_count),
        .quantity_reject_count(quantity_reject_count),
        .price_reject_count(price_reject_count),
        .outstanding_reject_count(outstanding_reject_count),
        .rate_reject_count(rate_reject_count),
        .last_local_reject_reason(last_local_reject_reason)
    );

    market_parser_order_command_fifo command_fifo_i (
        .clk(clk), .rst(rst),
        .input_valid(order_cmd_valid), .input_ready(order_cmd_ready),
        .input_cancel(order_cmd_cancel), .input_id(order_cmd_id),
        .input_stock_locate(order_cmd_stock_locate),
        .input_side(order_cmd_side), .input_price(order_cmd_price),
        .input_quantity(order_cmd_quantity),
        .output_valid(gateway_command_valid),
        .output_ready(gateway_command_ready),
        .output_cancel(gateway_command_cancel),
        .output_id(gateway_command_id),
        .output_stock_locate(gateway_command_stock_locate),
        .output_side(gateway_command_side),
        .output_price(gateway_command_price),
        .output_quantity(gateway_command_quantity),
        .occupancy(command_fifo_occupancy)
    );

    market_parser_ouch5_gateway #(
        .NUM_SYMBOLS(NUM_SYMBOLS), .SYMBOL_LOCATES(SYMBOL_LOCATES),
        .OUCH_SYMBOLS(OUCH_SYMBOLS), .WATCHDOG_CYCLES(SOUP_WATCHDOG_CYCLES),
        .CLIENT_HEARTBEAT_CYCLES(SOUP_CLIENT_HEARTBEAT_CYCLES)
    ) gateway_i (
        .clk(clk), .rst(rst),
        .transport_connected(transport_connected),
        .login_valid(soup_login_valid), .login_ready(soup_login_ready),
        .login_username(soup_login_username),
        .login_password(soup_login_password),
        .requested_session(soup_requested_session),
        .requested_sequence(soup_requested_sequence),
        .logout_valid(soup_logout_valid), .logout_ready(soup_logout_ready),
        .command_valid(gateway_command_valid),
        .command_ready(gateway_command_ready),
        .command_cancel(gateway_command_cancel),
        .command_id(gateway_command_id),
        .command_stock_locate(gateway_command_stock_locate),
        .command_side(gateway_command_side),
        .command_price(gateway_command_price),
        .command_quantity(gateway_command_quantity),
        .exchange_event_valid(exchange_event_valid),
        .exchange_event_ready(exchange_event_ready),
        .exchange_event_type(exchange_event_type),
        .exchange_event_order_id(exchange_event_order_id),
        .exchange_event_price(exchange_event_price),
        .exchange_event_quantity(exchange_event_quantity),
        .soup_tx_valid(soup_tx_valid), .soup_tx_ready(soup_tx_ready),
        .soup_tx_data(soup_tx_data), .soup_tx_keep(soup_tx_keep),
        .soup_tx_last(soup_tx_last), .soup_rx_valid(soup_rx_valid),
        .soup_rx_ready(soup_rx_ready), .soup_rx_data(soup_rx_data),
        .soup_rx_keep(soup_rx_keep), .soup_rx_last(soup_rx_last),
        .session_active(gateway_session_active),
        .session_fault(gateway_session_fault),
        .login_in_progress(soup_login_in_progress),
        .current_session(soup_current_session),
        .next_sequence(soup_next_sequence),
        .login_request_count(soup_login_request_count),
        .logout_request_count(soup_logout_request_count),
        .client_heartbeat_count(soup_client_heartbeat_count),
        .encoded_new_count(ouch_encoded_new_count),
        .encoded_cancel_count(ouch_encoded_cancel_count),
        .encode_reject_count(ouch_encode_reject_count),
        .transport_reject_count(transport_reject_count),
        .decoded_event_count(ouch_decoded_event_count),
        .malformed_response_count(malformed_ouch_count),
        .unsupported_response_count(unsupported_ouch_count),
        .heartbeat_count(soup_heartbeat_count),
        .sequenced_packet_count(soup_sequenced_packet_count),
        .malformed_soup_count(malformed_soup_count),
        .watchdog_timeout_count(watchdog_timeout_count)
    );
endmodule
`default_nettype wire
