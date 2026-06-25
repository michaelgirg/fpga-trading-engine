`default_nettype none
// =============================================================================
// Package: market_parser_pkg
// =============================================================================
package market_parser_pkg;
    localparam int MOLDUDP64_SESSION_BYTES = 10;
    localparam int MOLDUDP64_HEADER_BYTES  = 20;
    localparam int EVENT_W                 = 256;

    localparam logic [7:0] ITCH_SYSTEM_EVENT = 8'h53;  // S
    localparam logic [7:0] ITCH_STOCK_DIR    = 8'h52;  // R
    localparam logic [7:0] ITCH_ADD_ORDER    = 8'h41;  // A
    localparam logic [7:0] ITCH_ADD_ORDER_MP = 8'h46;  // F
    localparam logic [7:0] ITCH_EXECUTED     = 8'h45;  // E
    localparam logic [7:0] ITCH_EXEC_PRICE   = 8'h43;  // C
    localparam logic [7:0] ITCH_CANCEL       = 8'h58;  // X
    localparam logic [7:0] ITCH_DELETE       = 8'h44;  // D
    localparam logic [7:0] ITCH_REPLACE      = 8'h55;  // U
    localparam logic [7:0] ITCH_TRADE        = 8'h50;  // P
    localparam logic [7:0] ITCH_CROSS_TRADE  = 8'h51;  // Q

    localparam logic [7:0] EVENT_UNKNOWN   = 8'd0;
    localparam logic [7:0] EVENT_SYSTEM    = 8'd1;
    localparam logic [7:0] EVENT_DIRECTORY = 8'd2;
    localparam logic [7:0] EVENT_ADD       = 8'd3;
    localparam logic [7:0] EVENT_EXECUTE   = 8'd4;
    localparam logic [7:0] EVENT_CANCEL    = 8'd5;
    localparam logic [7:0] EVENT_DELETE    = 8'd6;
    localparam logic [7:0] EVENT_REPLACE   = 8'd7;
    localparam logic [7:0] EVENT_TRADE     = 8'd8;

    localparam logic [7:0] FLAG_GAP       = 8'h01;
    localparam logic [7:0] FLAG_MALFORMED = 8'h02;
    localparam logic [7:0] FLAG_UNKNOWN   = 8'h04;

    function automatic logic [7:0] classify_msg(input logic [7:0] msg_type);
        case (msg_type)
            ITCH_SYSTEM_EVENT: classify_msg = EVENT_SYSTEM;
            ITCH_STOCK_DIR:    classify_msg = EVENT_DIRECTORY;
            ITCH_ADD_ORDER:    classify_msg = EVENT_ADD;
            ITCH_ADD_ORDER_MP: classify_msg = EVENT_ADD;
            ITCH_EXECUTED:     classify_msg = EVENT_EXECUTE;
            ITCH_EXEC_PRICE:   classify_msg = EVENT_EXECUTE;
            ITCH_CANCEL:       classify_msg = EVENT_CANCEL;
            ITCH_DELETE:       classify_msg = EVENT_DELETE;
            ITCH_REPLACE:      classify_msg = EVENT_REPLACE;
            ITCH_TRADE:        classify_msg = EVENT_TRADE;
            ITCH_CROSS_TRADE:  classify_msg = EVENT_TRADE;
            default:           classify_msg = EVENT_UNKNOWN;
        endcase
    endfunction

    function automatic logic is_supported_msg(input logic [7:0] msg_type);
        is_supported_msg = (classify_msg(msg_type) != EVENT_UNKNOWN);
    endfunction

    function automatic logic has_order_ref(input logic [7:0] msg_type);
        case (msg_type)
            ITCH_ADD_ORDER:    has_order_ref = 1'b1;
            ITCH_ADD_ORDER_MP: has_order_ref = 1'b1;
            ITCH_EXECUTED:     has_order_ref = 1'b1;
            ITCH_EXEC_PRICE:   has_order_ref = 1'b1;
            ITCH_CANCEL:       has_order_ref = 1'b1;
            ITCH_DELETE:       has_order_ref = 1'b1;
            ITCH_REPLACE:      has_order_ref = 1'b1;
            ITCH_TRADE:        has_order_ref = 1'b1;
            default:           has_order_ref = 1'b0;
        endcase
    endfunction

    function automatic logic [EVENT_W-1:0] pack_event(
        input logic [ 7:0] event_kind,
        input logic [ 7:0] msg_type,
        input logic [15:0] stock_locate,
        input logic [15:0] tracking_number,
        input logic [47:0] timestamp,
        input logic [63:0] order_ref,
        input logic [31:0] shares,
        input logic [31:0] price,
        input logic [ 7:0] side,
        input logic [ 7:0] flags
    );
        pack_event              = '0;
        pack_event[7:0]         = event_kind;
        pack_event[15:8]        = msg_type;
        pack_event[31:16]       = stock_locate;
        pack_event[47:32]       = tracking_number;
        pack_event[95:48]       = timestamp;
        pack_event[159:96]      = order_ref;
        pack_event[191:160]     = shares;
        pack_event[223:192]     = price;
        pack_event[231:224]     = side;
        pack_event[239:232]     = flags;
    endfunction
endpackage
`default_nettype wire
