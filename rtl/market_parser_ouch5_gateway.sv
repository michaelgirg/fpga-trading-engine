`default_nettype none
// Command/response gateway for OUCH 5.0 carried in SoupBinTCP logical packets.
// The surrounding transport supplies complete Soup packets over AXI Stream.
module market_parser_ouch5_gateway #(
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
    parameter int WATCHDOG_CYCLES = 1024,
    parameter int CLIENT_HEARTBEAT_CYCLES = 0
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         transport_connected,
    input  wire logic         login_valid,
    output logic              login_ready,
    input  wire logic [47:0]  login_username,
    input  wire logic [79:0]  login_password,
    input  wire logic [79:0]  requested_session,
    input  wire logic [63:0]  requested_sequence,
    input  wire logic         logout_valid,
    output logic              logout_ready,

    input  wire logic         command_valid,
    output logic              command_ready,
    input  wire logic         command_cancel,
    input  wire logic [63:0]  command_id,
    input  wire logic [15:0]  command_stock_locate,
    input  wire logic         command_side,
    input  wire logic [31:0]  command_price,
    input  wire logic [31:0]  command_quantity,

    output logic              exchange_event_valid,
    input  wire logic         exchange_event_ready,
    output logic [1:0]        exchange_event_type,
    output logic [63:0]       exchange_event_order_id,
    output logic [31:0]       exchange_event_price,
    output logic [31:0]       exchange_event_quantity,

    output logic              soup_tx_valid,
    input  wire logic         soup_tx_ready,
    output logic [511:0]      soup_tx_data,
    output logic [63:0]       soup_tx_keep,
    output logic              soup_tx_last,
    input  wire logic         soup_rx_valid,
    output logic              soup_rx_ready,
    input  wire logic [511:0] soup_rx_data,
    input  wire logic [63:0]  soup_rx_keep,
    input  wire logic         soup_rx_last,

    output logic              session_active,
    output logic              session_fault,
    output logic              login_in_progress,
    output logic [79:0]       current_session,
    output logic [63:0]       next_sequence,
    output logic [31:0]       login_request_count,
    output logic [31:0]       logout_request_count,
    output logic [31:0]       client_heartbeat_count,
    output logic [31:0]       encoded_new_count,
    output logic [31:0]       encoded_cancel_count,
    output logic [31:0]       encode_reject_count,
    output logic [31:0]       transport_reject_count,
    output logic [31:0]       decoded_event_count,
    output logic [31:0]       malformed_response_count,
    output logic [31:0]       unsupported_response_count,
    output logic [31:0]       heartbeat_count,
    output logic [31:0]       sequenced_packet_count,
    output logic [31:0]       malformed_soup_count,
    output logic [31:0]       watchdog_timeout_count
);
    localparam logic [1:0] EVENT_REJECT = 2'd1;

    logic codec_command_valid;
    logic codec_command_ready;
    logic codec_tx_valid;
    logic codec_tx_ready;
    logic [511:0] codec_tx_data;
    logic [63:0] codec_tx_keep;
    logic codec_tx_last;
    logic codec_reject_valid;
    logic codec_reject_ready;
    logic [63:0] codec_reject_id;
    logic [1:0] codec_reject_reason;
    logic codec_rx_valid;
    logic codec_rx_ready;
    logic [511:0] codec_rx_data;
    logic [63:0] codec_rx_keep;
    logic codec_rx_last;
    logic codec_event_valid;
    logic codec_event_ready;
    logic [1:0] codec_event_type;
    logic [63:0] codec_event_id;
    logic [31:0] codec_event_price;
    logic [31:0] codec_event_quantity;
    logic transport_reject_valid_r;
    logic [63:0] transport_reject_id_r;
    logic transport_reject_ready_i;
    logic transport_reject_slot_i;

    logic [31:0] login_accepted_count_unused;
    logic [31:0] login_rejected_count_unused;
    logic [31:0] end_session_count_unused;
    logic [31:0] inactive_data_count_unused;
    logic [31:0] unsupported_soup_count_unused;
    logic [31:0] tx_unsequenced_count_unused;
    logic [31:0] tx_malformed_count_unused;
    logic [31:0] sequence_parse_error_count_unused;

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    assign transport_reject_slot_i = !transport_reject_valid_r ||
                                     transport_reject_ready_i;
    assign command_ready = session_active ? codec_command_ready :
                                            transport_reject_slot_i;
    assign codec_command_valid = command_valid && session_active;

    assign exchange_event_valid = transport_reject_valid_r ||
                                  codec_reject_valid || codec_event_valid;
    assign exchange_event_type = transport_reject_valid_r ? EVENT_REJECT :
                                 codec_reject_valid ? EVENT_REJECT :
                                                      codec_event_type;
    assign exchange_event_order_id = transport_reject_valid_r ?
                                     transport_reject_id_r :
                                     codec_reject_valid ? codec_reject_id :
                                                          codec_event_id;
    assign exchange_event_price =
        (transport_reject_valid_r || codec_reject_valid) ? 32'd0 :
                                                          codec_event_price;
    assign exchange_event_quantity =
        (transport_reject_valid_r || codec_reject_valid) ? 32'd0 :
                                                          codec_event_quantity;
    assign transport_reject_ready_i = exchange_event_ready;
    assign codec_reject_ready = exchange_event_ready &&
                                !transport_reject_valid_r;
    assign codec_event_ready = exchange_event_ready &&
                               !transport_reject_valid_r &&
                               !codec_reject_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            transport_reject_valid_r <= 1'b0;
            transport_reject_id_r <= '0;
            transport_reject_count <= '0;
        end else begin
            if (transport_reject_valid_r && transport_reject_ready_i) begin
                transport_reject_valid_r <= 1'b0;
            end
            if (command_valid && command_ready && !session_active) begin
                transport_reject_valid_r <= 1'b1;
                transport_reject_id_r <= command_id;
                transport_reject_count <=
                    increment_saturating(transport_reject_count);
            end
        end
    end

    market_parser_ouch5_codec #(
        .NUM_SYMBOLS(NUM_SYMBOLS),
        .SYMBOL_LOCATES(SYMBOL_LOCATES),
        .OUCH_SYMBOLS(OUCH_SYMBOLS)
    ) codec_i (
        .clk(clk), .rst(rst),
        .command_valid(codec_command_valid),
        .command_ready(codec_command_ready),
        .command_cancel(command_cancel), .command_id(command_id),
        .command_stock_locate(command_stock_locate),
        .command_side(command_side), .command_price(command_price),
        .command_quantity(command_quantity),
        .tx_valid(codec_tx_valid), .tx_ready(codec_tx_ready),
        .tx_data(codec_tx_data), .tx_keep(codec_tx_keep),
        .tx_last(codec_tx_last),
        .local_reject_valid(codec_reject_valid),
        .local_reject_ready(codec_reject_ready),
        .local_reject_order_id(codec_reject_id),
        .local_reject_reason(codec_reject_reason),
        .rx_valid(codec_rx_valid), .rx_ready(codec_rx_ready),
        .rx_data(codec_rx_data), .rx_keep(codec_rx_keep),
        .rx_last(codec_rx_last),
        .exchange_event_valid(codec_event_valid),
        .exchange_event_ready(codec_event_ready),
        .exchange_event_type(codec_event_type),
        .exchange_event_order_id(codec_event_id),
        .exchange_event_price(codec_event_price),
        .exchange_event_quantity(codec_event_quantity),
        .encoded_new_count(encoded_new_count),
        .encoded_cancel_count(encoded_cancel_count),
        .encode_reject_count(encode_reject_count),
        .decoded_event_count(decoded_event_count),
        .malformed_response_count(malformed_response_count),
        .unsupported_response_count(unsupported_response_count)
    );

    market_parser_soupbintcp_client #(
        .WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .CLIENT_HEARTBEAT_CYCLES(CLIENT_HEARTBEAT_CYCLES)
    ) soup_i (
        .clk(clk), .rst(rst),
        .transport_connected(transport_connected),
        .login_valid(login_valid), .login_ready(login_ready),
        .login_username(login_username), .login_password(login_password),
        .requested_session(requested_session),
        .requested_sequence(requested_sequence),
        .logout_valid(logout_valid), .logout_ready(logout_ready),
        .ouch_tx_valid(codec_tx_valid), .ouch_tx_ready(codec_tx_ready),
        .ouch_tx_data(codec_tx_data), .ouch_tx_keep(codec_tx_keep),
        .ouch_tx_last(codec_tx_last),
        .soup_tx_valid(soup_tx_valid), .soup_tx_ready(soup_tx_ready),
        .soup_tx_data(soup_tx_data), .soup_tx_keep(soup_tx_keep),
        .soup_tx_last(soup_tx_last),
        .soup_rx_valid(soup_rx_valid), .soup_rx_ready(soup_rx_ready),
        .soup_rx_data(soup_rx_data), .soup_rx_keep(soup_rx_keep),
        .soup_rx_last(soup_rx_last),
        .ouch_rx_valid(codec_rx_valid), .ouch_rx_ready(codec_rx_ready),
        .ouch_rx_data(codec_rx_data), .ouch_rx_keep(codec_rx_keep),
        .ouch_rx_last(codec_rx_last),
        .session_active(session_active), .session_fault(session_fault),
        .login_in_progress(login_in_progress),
        .current_session(current_session), .next_sequence(next_sequence),
        .login_request_count(login_request_count),
        .login_accepted_count(login_accepted_count_unused),
        .login_rejected_count(login_rejected_count_unused),
        .logout_request_count(logout_request_count),
        .end_session_count(end_session_count_unused),
        .heartbeat_count(heartbeat_count),
        .client_heartbeat_count(client_heartbeat_count),
        .sequenced_packet_count(sequenced_packet_count),
        .inactive_data_count(inactive_data_count_unused),
        .malformed_packet_count(malformed_soup_count),
        .unsupported_packet_count(unsupported_soup_count_unused),
        .watchdog_timeout_count(watchdog_timeout_count),
        .tx_unsequenced_count(tx_unsequenced_count_unused),
        .tx_malformed_count(tx_malformed_count_unused),
        .sequence_parse_error_count(sequence_parse_error_count_unused)
    );
endmodule
`default_nettype wire
