`default_nettype none
// Minimal Nasdaq OUCH 5.0 codec for visible DAY limit orders and full cancels.
// Optional appendages are omitted. Byte zero occupies data[7:0].
module market_parser_ouch5_codec #(
    parameter int NUM_SYMBOLS = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter logic [NUM_SYMBOLS*64-1:0] OUCH_SYMBOLS = {
        64'h4444444420202020,
        64'h4343434320202020,
        64'h4242424220202020,
        64'h4141414120202020
    }
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         command_valid,
    output logic              command_ready,
    input  wire logic         command_cancel,
    input  wire logic [63:0]  command_id,
    input  wire logic [15:0]  command_stock_locate,
    input  wire logic         command_side,
    input  wire logic [31:0]  command_price,
    input  wire logic [31:0]  command_quantity,

    output logic              tx_valid,
    input  wire logic         tx_ready,
    output logic [511:0]      tx_data,
    output logic [63:0]       tx_keep,
    output logic              tx_last,

    output logic              local_reject_valid,
    input  wire logic         local_reject_ready,
    output logic [63:0]       local_reject_order_id,
    output logic [ 1:0]       local_reject_reason,

    input  wire logic         rx_valid,
    output logic              rx_ready,
    input  wire logic [511:0] rx_data,
    input  wire logic [63:0]  rx_keep,
    input  wire logic         rx_last,

    output logic              exchange_event_valid,
    input  wire logic         exchange_event_ready,
    output logic [ 1:0]       exchange_event_type,
    output logic [63:0]       exchange_event_order_id,
    output logic [31:0]       exchange_event_price,
    output logic [31:0]       exchange_event_quantity,

    output logic [31:0]       encoded_new_count,
    output logic [31:0]       encoded_cancel_count,
    output logic [31:0]       encode_reject_count,
    output logic [31:0]       decoded_event_count,
    output logic [31:0]       malformed_response_count,
    output logic [31:0]       unsupported_response_count
);
    localparam logic [1:0] EVENT_ACK        = 2'd0;
    localparam logic [1:0] EVENT_REJECT     = 2'd1;
    localparam logic [1:0] EVENT_FILL       = 2'd2;
    localparam logic [1:0] EVENT_CANCEL_ACK = 2'd3;

    localparam logic [1:0] ENCODE_BAD_ID     = 2'd1;
    localparam logic [1:0] ENCODE_BAD_SYMBOL = 2'd2;

    logic tx_valid_r;
    logic [511:0] tx_data_r;
    logic [63:0] tx_keep_r;
    logic local_reject_valid_r;
    logic [63:0] local_reject_order_id_r;
    logic [1:0] local_reject_reason_r;
    logic event_valid_r;
    logic [1:0] event_type_r;
    logic [63:0] event_order_id_r;
    logic [31:0] event_price_r;
    logic [31:0] event_quantity_r;

    logic symbol_found_i;
    logic [63:0] symbol_i;
    logic encode_valid_i;
    logic [1:0] encode_reject_reason_i;
    logic tx_slot_available_i;
    logic reject_slot_available_i;
    logic event_slot_available_i;
    logic command_fire_i;
    logic rx_fire_i;
    logic response_supported_i;
    logic response_well_formed_i;
    logic [1:0] response_event_type_i;
    logic [63:0] response_order_id_i;
    logic [31:0] response_price_i;
    logic [31:0] response_quantity_i;
    logic [7:0] response_type_i;

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    function automatic logic [7:0] hex_ascii(input logic [3:0] nibble);
        hex_ascii = (nibble < 10) ? (8'h30 + nibble) :
                                    (8'h41 + nibble - 10);
    endfunction

    function automatic logic [31:0] read_u32_be(
        input logic [511:0] data,
        input int offset
    );
        read_u32_be = {data[(offset+0)*8 +: 8],
                       data[(offset+1)*8 +: 8],
                       data[(offset+2)*8 +: 8],
                       data[(offset+3)*8 +: 8]};
    endfunction

    always_comb begin
        symbol_found_i = 1'b0;
        symbol_i = 64'h2020202020202020;
        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            if (command_stock_locate == SYMBOL_LOCATES[i*16 +: 16]) begin
                symbol_found_i = 1'b1;
                symbol_i = OUCH_SYMBOLS[i*64 +: 64];
            end
        end

        encode_reject_reason_i = 2'd0;
        if (command_id == 64'd0 || command_id[63:32] != 32'd0) begin
            encode_reject_reason_i = ENCODE_BAD_ID;
        end else if (!command_cancel && !symbol_found_i) begin
            encode_reject_reason_i = ENCODE_BAD_SYMBOL;
        end
        encode_valid_i = encode_reject_reason_i == 2'd0;
    end

    assign tx_slot_available_i = !tx_valid_r || tx_ready;
    assign reject_slot_available_i = !local_reject_valid_r ||
                                     local_reject_ready;
    assign command_ready = encode_valid_i ? tx_slot_available_i :
                                            reject_slot_available_i;
    assign command_fire_i = command_valid && command_ready;

    assign tx_valid = tx_valid_r;
    assign tx_data = tx_data_r;
    assign tx_keep = tx_keep_r;
    assign tx_last = 1'b1;
    assign local_reject_valid = local_reject_valid_r;
    assign local_reject_order_id = local_reject_order_id_r;
    assign local_reject_reason = local_reject_reason_r;

    always_comb begin
        response_type_i = rx_data[7:0];
        response_supported_i = 1'b1;
        response_well_formed_i = rx_last;
        response_event_type_i = EVENT_ACK;
        response_order_id_i = {32'd0, read_u32_be(rx_data, 9)};
        response_price_i = 32'd0;
        response_quantity_i = 32'd0;

        case (response_type_i)
            8'h41: begin // A: Order Accepted
                response_event_type_i =
                    (rx_data[47*8 +: 8] == 8'h44) ?
                    EVENT_REJECT : EVENT_ACK;
                response_well_formed_i &= rx_keep[63] &&
                    (rx_data[47*8 +: 8] == 8'h4c ||
                     rx_data[47*8 +: 8] == 8'h44);
            end
            8'h4a: begin // J: Rejected
                response_event_type_i = EVENT_REJECT;
                response_well_formed_i &= rx_keep[30];
            end
            8'h45: begin // E: Executed
                response_event_type_i = EVENT_FILL;
                response_well_formed_i &= rx_keep[35] &&
                    rx_data[17*8 +: 32] == 32'd0;
                response_quantity_i = read_u32_be(rx_data, 13);
                response_price_i = read_u32_be(rx_data, 21);
            end
            8'h43: begin // C: Canceled
                response_event_type_i = EVENT_CANCEL_ACK;
                response_well_formed_i &= rx_keep[19];
                response_quantity_i = read_u32_be(rx_data, 13);
            end
            default: begin
                response_supported_i = 1'b0;
                response_well_formed_i = rx_last;
            end
        endcase
    end

    assign event_slot_available_i = !event_valid_r || exchange_event_ready;
    assign rx_ready = (!response_supported_i || !response_well_formed_i) ?
                      1'b1 : event_slot_available_i;
    assign rx_fire_i = rx_valid && rx_ready;

    assign exchange_event_valid = event_valid_r;
    assign exchange_event_type = event_type_r;
    assign exchange_event_order_id = event_order_id_r;
    assign exchange_event_price = event_price_r;
    assign exchange_event_quantity = event_quantity_r;

    always_ff @(posedge clk) begin
        logic [511:0] encoded_data;

        if (rst) begin
            tx_valid_r                  <= 1'b0;
            tx_data_r                   <= '0;
            tx_keep_r                   <= '0;
            local_reject_valid_r        <= 1'b0;
            local_reject_order_id_r     <= '0;
            local_reject_reason_r       <= '0;
            event_valid_r               <= 1'b0;
            event_type_r                <= '0;
            event_order_id_r            <= '0;
            event_price_r               <= '0;
            event_quantity_r            <= '0;
            encoded_new_count           <= '0;
            encoded_cancel_count        <= '0;
            encode_reject_count         <= '0;
            decoded_event_count         <= '0;
            malformed_response_count    <= '0;
            unsupported_response_count  <= '0;
        end else begin
            if (tx_valid_r && tx_ready) tx_valid_r <= 1'b0;
            if (local_reject_valid_r && local_reject_ready) begin
                local_reject_valid_r <= 1'b0;
            end
            if (event_valid_r && exchange_event_ready) event_valid_r <= 1'b0;

            if (command_fire_i) begin
                if (encode_valid_i) begin
                    encoded_data = '0;
                    if (command_cancel) begin
                        encoded_data[0*8 +: 8] = 8'h58;
                        encoded_data[1*8 +: 8] = command_id[31:24];
                        encoded_data[2*8 +: 8] = command_id[23:16];
                        encoded_data[3*8 +: 8] = command_id[15:8];
                        encoded_data[4*8 +: 8] = command_id[7:0];
                        // A zero intended size cancels the entire balance.
                        encoded_data[5*8 +: 32] = 32'd0;
                        encoded_data[9*8 +: 16] = 16'd0;
                        tx_keep_r <= 64'h0000_0000_0000_07ff;
                        encoded_cancel_count <=
                            increment_saturating(encoded_cancel_count);
                    end else begin
                        encoded_data[0*8 +: 8] = 8'h4f;
                        encoded_data[1*8 +: 8] = command_id[31:24];
                        encoded_data[2*8 +: 8] = command_id[23:16];
                        encoded_data[3*8 +: 8] = command_id[15:8];
                        encoded_data[4*8 +: 8] = command_id[7:0];
                        encoded_data[5*8 +: 8] = command_side ? 8'h53 : 8'h42;
                        encoded_data[6*8 +: 8] = command_quantity[31:24];
                        encoded_data[7*8 +: 8] = command_quantity[23:16];
                        encoded_data[8*8 +: 8] = command_quantity[15:8];
                        encoded_data[9*8 +: 8] = command_quantity[7:0];
                        for (int i = 0; i < 8; i++) begin
                            encoded_data[(10+i)*8 +: 8] =
                                symbol_i[(7-i)*8 +: 8];
                        end
                        encoded_data[18*8 +: 32] = 32'd0;
                        encoded_data[22*8 +: 8] = command_price[31:24];
                        encoded_data[23*8 +: 8] = command_price[23:16];
                        encoded_data[24*8 +: 8] = command_price[15:8];
                        encoded_data[25*8 +: 8] = command_price[7:0];
                        encoded_data[26*8 +: 8] = 8'h30;
                        encoded_data[27*8 +: 8] = 8'h59;
                        encoded_data[28*8 +: 8] = 8'h41;
                        encoded_data[29*8 +: 8] = 8'h4e;
                        encoded_data[30*8 +: 8] = 8'h4e;
                        encoded_data[31*8 +: 8] = 8'h46;
                        encoded_data[32*8 +: 8] = 8'h50;
                        encoded_data[33*8 +: 8] = 8'h47;
                        encoded_data[34*8 +: 8] = 8'h41;
                        for (int i = 0; i < 10; i++) begin
                            encoded_data[(35+i)*8 +: 8] =
                                hex_ascii(command_id[(9-i)*4 +: 4]);
                        end
                        encoded_data[45*8 +: 16] = 16'd0;
                        tx_keep_r <= 64'h0000_7fff_ffff_ffff;
                        encoded_new_count <=
                            increment_saturating(encoded_new_count);
                    end
                    tx_data_r  <= encoded_data;
                    tx_valid_r <= 1'b1;
                end else begin
                    local_reject_valid_r    <= 1'b1;
                    local_reject_order_id_r <= command_id;
                    local_reject_reason_r   <= encode_reject_reason_i;
                    encode_reject_count <=
                        increment_saturating(encode_reject_count);
                end
            end

            if (rx_fire_i) begin
                if (!response_supported_i) begin
                    unsupported_response_count <=
                        increment_saturating(unsupported_response_count);
                end else if (!response_well_formed_i) begin
                    malformed_response_count <=
                        increment_saturating(malformed_response_count);
                end else begin
                    event_valid_r    <= 1'b1;
                    event_type_r     <= response_event_type_i;
                    event_order_id_r <= response_order_id_i;
                    event_price_r    <= response_price_i;
                    event_quantity_r <= response_quantity_i;
                    decoded_event_count <=
                        increment_saturating(decoded_event_count);
                end
            end
        end
    end
endmodule
`default_nettype wire
