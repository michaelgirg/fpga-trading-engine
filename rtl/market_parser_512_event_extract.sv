`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_512_event_extract
// =============================================================================
// Parallel ITCH field extractor for the 512-bit descriptor frontend.
//
// The extractor consumes one message descriptor plus a two-beat packet window
// and emits the same normalized 256-bit event format as the byte-serial parser.
module market_parser_512_event_extract #(
    parameter int WINDOW_BYTES = 128
) (
    input  wire logic                         desc_valid,
    input  wire logic [                  15:0] window_base_byte,
    input  wire logic [    WINDOW_BYTES*8-1:0] window_data,
    input  wire logic [      WINDOW_BYTES-1:0] window_keep,
    input  wire logic [                  15:0] desc_message_length,
    input  wire logic [                  15:0] desc_message_start_byte,
    input  wire logic [                  15:0] desc_message_end_byte,
    input  wire logic [                   7:0] desc_flags,

    output logic                              event_valid,
    output logic                              event_complete,
    output logic                              event_supported,
    output logic [                 255:0]     event_data,
    output logic [                  31:0]     extract_error_flags
);
    localparam logic [7:0] DESC_FLAG_MALFORMED = 8'h02;
    localparam logic [7:0] DESC_FLAG_BAD_FRAME = 8'h04;
    localparam logic [7:0] DESC_FLAG_TRUNCATED = 8'h08;

    localparam logic [31:0] EXTRACT_ERR_INCOMPLETE = 32'h0000_0001;
    localparam logic [31:0] EXTRACT_ERR_MALFORMED  = 32'h0000_0002;
    localparam logic [31:0] EXTRACT_ERR_BAD_FRAME  = 32'h0000_0004;
    localparam logic [31:0] EXTRACT_ERR_UNKNOWN    = 32'h0000_0008;

    function automatic logic offset_valid(input int abs_offset);
        int window_lane;
        window_lane = abs_offset - int'(window_base_byte);
        offset_valid = (window_lane >= 0 && window_lane < WINDOW_BYTES && window_keep[window_lane]);
    endfunction

    function automatic logic [7:0] byte_at(input int abs_offset);
        int window_lane;
        window_lane = abs_offset - int'(window_base_byte);
        if (window_lane >= 0 && window_lane < WINDOW_BYTES) begin
            byte_at = window_data[window_lane*8 +: 8];
        end else begin
            byte_at = 8'h00;
        end
    endfunction

    function automatic logic range_valid(input int first_abs_offset, input int last_abs_offset);
        logic valid;
        valid = 1'b1;
        for (int i = first_abs_offset; i <= last_abs_offset; i++) begin
            if (!offset_valid(i)) valid = 1'b0;
        end
        range_valid = valid;
    endfunction

    always_comb begin
        int msg_start;
        int msg_end;
        logic [ 7:0] msg_type;
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref;
        logic [31:0] shares;
        logic [31:0] price;
        logic [ 7:0] side;
        logic [ 7:0] event_flags;

        msg_start = int'(desc_message_start_byte);
        msg_end   = int'(desc_message_end_byte);

        msg_type        = 8'h00;
        stock_locate    = '0;
        tracking_number = '0;
        timestamp       = '0;
        order_ref       = '0;
        shares          = '0;
        price           = '0;
        side            = '0;
        event_flags     = '0;

        event_valid         = desc_valid;
        event_complete      = desc_valid && desc_message_length != 16'd0 && range_valid(msg_start, msg_end);
        event_supported     = 1'b0;
        extract_error_flags = '0;

        if ((desc_flags & (DESC_FLAG_MALFORMED | DESC_FLAG_TRUNCATED)) != 8'h00) begin
            event_flags = event_flags | FLAG_MALFORMED;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_MALFORMED;
        end
        if ((desc_flags & DESC_FLAG_BAD_FRAME) != 8'h00) begin
            event_flags = event_flags | FLAG_MALFORMED;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_BAD_FRAME;
        end
        if (!event_complete) begin
            event_flags = event_flags | FLAG_MALFORMED;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_INCOMPLETE;
        end

        if (desc_valid && offset_valid(msg_start)) begin
            msg_type = byte_at(msg_start);
        end

        event_supported = is_supported_msg(msg_type);
        if (!event_supported) begin
            event_flags = event_flags | FLAG_UNKNOWN;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_UNKNOWN;
        end

        if (event_complete) begin
            if (desc_message_length >= 16'd3) begin
                stock_locate = {byte_at(msg_start + 1), byte_at(msg_start + 2)};
            end
            if (desc_message_length >= 16'd5) begin
                tracking_number = {byte_at(msg_start + 3), byte_at(msg_start + 4)};
            end
            if (desc_message_length >= 16'd11) begin
                timestamp = {
                    byte_at(msg_start + 5), byte_at(msg_start + 6),
                    byte_at(msg_start + 7), byte_at(msg_start + 8),
                    byte_at(msg_start + 9), byte_at(msg_start + 10)
                };
            end
            if (desc_message_length >= 16'd19 && has_order_ref(msg_type)) begin
                order_ref = {
                    byte_at(msg_start + 11), byte_at(msg_start + 12),
                    byte_at(msg_start + 13), byte_at(msg_start + 14),
                    byte_at(msg_start + 15), byte_at(msg_start + 16),
                    byte_at(msg_start + 17), byte_at(msg_start + 18)
                };
            end

            if ((msg_type == ITCH_ADD_ORDER || msg_type == ITCH_ADD_ORDER_MP ||
                 msg_type == ITCH_TRADE) && desc_message_length >= 16'd36) begin
                side   = byte_at(msg_start + 19);
                shares = {
                    byte_at(msg_start + 20), byte_at(msg_start + 21),
                    byte_at(msg_start + 22), byte_at(msg_start + 23)
                };
                price = {
                    byte_at(msg_start + 32), byte_at(msg_start + 33),
                    byte_at(msg_start + 34), byte_at(msg_start + 35)
                };
            end else if ((msg_type == ITCH_EXECUTED || msg_type == ITCH_EXEC_PRICE ||
                          msg_type == ITCH_CANCEL) && desc_message_length >= 16'd23) begin
                shares = {
                    byte_at(msg_start + 19), byte_at(msg_start + 20),
                    byte_at(msg_start + 21), byte_at(msg_start + 22)
                };
                if (msg_type == ITCH_EXEC_PRICE && desc_message_length >= 16'd36) begin
                    price = {
                        byte_at(msg_start + 32), byte_at(msg_start + 33),
                        byte_at(msg_start + 34), byte_at(msg_start + 35)
                    };
                end
            end else if (msg_type == ITCH_REPLACE && desc_message_length >= 16'd35) begin
                shares = {
                    byte_at(msg_start + 27), byte_at(msg_start + 28),
                    byte_at(msg_start + 29), byte_at(msg_start + 30)
                };
                price = {
                    byte_at(msg_start + 31), byte_at(msg_start + 32),
                    byte_at(msg_start + 33), byte_at(msg_start + 34)
                };
            end else if (msg_type == ITCH_CROSS_TRADE && desc_message_length >= 16'd36) begin
                price = {
                    byte_at(msg_start + 32), byte_at(msg_start + 33),
                    byte_at(msg_start + 34), byte_at(msg_start + 35)
                };
            end
        end

        event_data = pack_event(
            classify_msg(msg_type),
            msg_type,
            stock_locate,
            tracking_number,
            timestamp,
            order_ref,
            shares,
            price,
            side,
            event_flags
        );
    end

endmodule
`default_nettype wire
