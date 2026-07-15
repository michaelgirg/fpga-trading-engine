`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_512_event_extract
// =============================================================================
// Parallel ITCH field extractor for the 512-bit descriptor frontend.
//
// The extractor consumes one message descriptor plus a packet-local extraction
// window and emits the same normalized 256-bit event format as the byte-serial
// parser.
module market_parser_512_event_extract #(
    parameter int WINDOW_BYTES = 256
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
    output logic [                  63:0]     event_new_order_ref,
    output logic [                  31:0]     extract_error_flags
);
    localparam logic [7:0] DESC_FLAG_MALFORMED = 8'h02;
    localparam logic [7:0] DESC_FLAG_BAD_FRAME = 8'h04;
    localparam logic [7:0] DESC_FLAG_TRUNCATED = 8'h08;
    localparam logic [7:0] DESC_FLAG_GAP       = 8'h10;

    localparam logic [31:0] EXTRACT_ERR_INCOMPLETE = 32'h0000_0001;
    localparam logic [31:0] EXTRACT_ERR_MALFORMED  = 32'h0000_0002;
    localparam logic [31:0] EXTRACT_ERR_BAD_FRAME  = 32'h0000_0004;
    localparam logic [31:0] EXTRACT_ERR_UNKNOWN    = 32'h0000_0008;

    localparam int FIELD_PREFIX_BYTES = (WINDOW_BYTES < 128) ? WINDOW_BYTES : 128;

    function automatic logic field_lane_valid(input int lane);
        field_lane_valid = (lane >= 0 && lane < FIELD_PREFIX_BYTES && window_keep[lane]);
    endfunction

    function automatic logic [7:0] field_byte_at_lane(input int lane);
        if (lane >= 0 && lane < FIELD_PREFIX_BYTES) begin
            field_byte_at_lane = window_data[lane*8 +: 8];
        end else begin
            field_byte_at_lane = 8'h00;
        end
    endfunction

    function automatic logic range_valid(input int first_lane, input int message_length);
        logic valid;
        int last_lane;
        last_lane = first_lane + message_length - 1;
        valid = (message_length > 0) &&
                (first_lane >= 0) &&
                (last_lane < WINDOW_BYTES);
        if (valid) begin
            valid = window_keep[first_lane] && window_keep[last_lane];
        end
        range_valid = valid;
    endfunction

    always_comb begin
        int msg_start;
        int msg_len;
        logic [ 7:0] msg_type;
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref;
        logic [63:0] new_order_ref;
        logic [31:0] shares;
        logic [31:0] price;
        logic [ 7:0] side;
        logic [ 7:0] event_flags;

        msg_start = int'(desc_message_start_byte[5:0]);
        msg_len   = int'(desc_message_length);

        msg_type        = 8'h00;
        stock_locate    = '0;
        tracking_number = '0;
        timestamp       = '0;
        order_ref       = '0;
        new_order_ref   = '0;
        shares          = '0;
        price           = '0;
        side            = '0;
        event_flags     = '0;

        event_valid         = desc_valid;
        event_complete      = desc_valid && desc_message_length != 16'd0 && range_valid(msg_start, msg_len);
        event_supported     = 1'b0;
        extract_error_flags = '0;

        if ((desc_flags & (DESC_FLAG_MALFORMED | DESC_FLAG_TRUNCATED)) != 8'h00) begin
            event_flags = event_flags | FLAG_MALFORMED;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_MALFORMED;
        end
        if ((desc_flags & DESC_FLAG_GAP) != 8'h00) begin
            event_flags = event_flags | FLAG_GAP;
        end
        if ((desc_flags & DESC_FLAG_BAD_FRAME) != 8'h00) begin
            event_flags = event_flags | FLAG_MALFORMED;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_BAD_FRAME;
        end
        if (!event_complete) begin
            event_flags = event_flags | FLAG_MALFORMED;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_INCOMPLETE;
        end

        if (desc_valid && field_lane_valid(msg_start)) begin
            msg_type = field_byte_at_lane(msg_start);
        end

        event_supported = is_supported_msg(msg_type);
        if (!event_supported) begin
            event_flags = event_flags | FLAG_UNKNOWN;
            extract_error_flags = extract_error_flags | EXTRACT_ERR_UNKNOWN;
        end

        if (desc_valid) begin
            stock_locate = {field_byte_at_lane(msg_start + 1), field_byte_at_lane(msg_start + 2)};
            tracking_number = {field_byte_at_lane(msg_start + 3), field_byte_at_lane(msg_start + 4)};
            timestamp = {
                field_byte_at_lane(msg_start + 5), field_byte_at_lane(msg_start + 6),
                field_byte_at_lane(msg_start + 7), field_byte_at_lane(msg_start + 8),
                field_byte_at_lane(msg_start + 9), field_byte_at_lane(msg_start + 10)
            };
        end

        if (has_order_ref(msg_type)) begin
            order_ref = {
                field_byte_at_lane(msg_start + 11), field_byte_at_lane(msg_start + 12),
                field_byte_at_lane(msg_start + 13), field_byte_at_lane(msg_start + 14),
                field_byte_at_lane(msg_start + 15), field_byte_at_lane(msg_start + 16),
                field_byte_at_lane(msg_start + 17), field_byte_at_lane(msg_start + 18)
            };
        end

        if (msg_type == ITCH_ADD_ORDER || msg_type == ITCH_ADD_ORDER_MP ||
            msg_type == ITCH_TRADE) begin
            side   = field_byte_at_lane(msg_start + 19);
            shares = {
                field_byte_at_lane(msg_start + 20), field_byte_at_lane(msg_start + 21),
                field_byte_at_lane(msg_start + 22), field_byte_at_lane(msg_start + 23)
            };
            price = {
                field_byte_at_lane(msg_start + 32), field_byte_at_lane(msg_start + 33),
                field_byte_at_lane(msg_start + 34), field_byte_at_lane(msg_start + 35)
            };
        end else if (msg_type == ITCH_EXECUTED || msg_type == ITCH_EXEC_PRICE ||
                     msg_type == ITCH_CANCEL) begin
            shares = {
                field_byte_at_lane(msg_start + 19), field_byte_at_lane(msg_start + 20),
                field_byte_at_lane(msg_start + 21), field_byte_at_lane(msg_start + 22)
            };
            if (msg_type == ITCH_EXEC_PRICE) begin
                price = {
                    field_byte_at_lane(msg_start + 32), field_byte_at_lane(msg_start + 33),
                    field_byte_at_lane(msg_start + 34), field_byte_at_lane(msg_start + 35)
                };
            end
        end else if (msg_type == ITCH_REPLACE) begin
            new_order_ref = {
                field_byte_at_lane(msg_start + 19), field_byte_at_lane(msg_start + 20),
                field_byte_at_lane(msg_start + 21), field_byte_at_lane(msg_start + 22),
                field_byte_at_lane(msg_start + 23), field_byte_at_lane(msg_start + 24),
                field_byte_at_lane(msg_start + 25), field_byte_at_lane(msg_start + 26)
            };
            shares = {
                field_byte_at_lane(msg_start + 27), field_byte_at_lane(msg_start + 28),
                field_byte_at_lane(msg_start + 29), field_byte_at_lane(msg_start + 30)
            };
            price = {
                field_byte_at_lane(msg_start + 31), field_byte_at_lane(msg_start + 32),
                field_byte_at_lane(msg_start + 33), field_byte_at_lane(msg_start + 34)
            };
        end else if (msg_type == ITCH_CROSS_TRADE) begin
            price = {
                field_byte_at_lane(msg_start + 32), field_byte_at_lane(msg_start + 33),
                field_byte_at_lane(msg_start + 34), field_byte_at_lane(msg_start + 35)
            };
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
        event_new_order_ref = new_order_ref;
    end

endmodule
`default_nettype wire
