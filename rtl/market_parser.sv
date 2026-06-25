`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser
// =============================================================================
// V1 production-shaped feed-handler core.
//
// The input stream is one MoldUDP64 packet per AXI-style frame. For the first
// implementation the bus is intentionally byte-wide to keep the parser easy to
// inspect and verify. A 64-bit packing wrapper can be added later without
// changing the event format.
module market_parser #(
    parameter int INPUT_BUS_WIDTH  = 8,
    parameter int OUTPUT_BUS_WIDTH = 256
) (
    input  wire logic                       clk,
    input  wire logic                       rst,

    input  wire logic                       data_in_valid,
    output logic                            data_in_ready,
    input  wire logic [   INPUT_BUS_WIDTH-1:0] data_in_data,
    input  wire logic [ INPUT_BUS_WIDTH/8-1:0] data_in_keep,
    input  wire logic                       data_in_last,

    output logic                            data_out_valid,
    input  wire logic                       data_out_ready,
    output logic [  OUTPUT_BUS_WIDTH-1:0]   data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0]   data_out_keep,
    output logic                            data_out_last,

    output logic                            gap_error,
    output logic                            malformed_error,
    output logic                            unknown_msg_type,
    output logic [                  63:0]   expected_sequence,
    output logic [                  63:0]   packet_sequence,
    output logic [                  31:0]   packet_count,
    output logic [                  31:0]   message_count,
    output logic [                  31:0]   event_count,
    output logic [                  31:0]   error_count
);
    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam int INPUT_KEEP_W  = INPUT_BUS_WIDTH / 8;
    localparam int OUTPUT_KEEP_W = OUTPUT_BUS_WIDTH / 8;

    initial begin
        if (INPUT_BUS_WIDTH != 8) $fatal(1, "market_parser V1 requires INPUT_BUS_WIDTH=8");
        if (OUTPUT_BUS_WIDTH != 256) $fatal(1, "market_parser V1 requires OUTPUT_BUS_WIDTH=256");
        if (INPUT_KEEP_W != 1) $fatal(1, "market_parser V1 expects one input keep bit");
    end

    typedef enum logic [2:0] {
        ST_HEADER,
        ST_MSG_LEN_0,
        ST_MSG_LEN_1,
        ST_MSG_PAYLOAD,
        ST_EMIT,
        ST_WAIT_OUT,
        ST_DROP_PACKET
    } state_t;

    state_t state_r;

    // =========================================================================
    // Packet and message tracking
    // =========================================================================
    logic [ 4:0] header_idx_r;
    logic [63:0] packet_sequence_build_r;
    logic [15:0] packet_msg_count_build_r;
    logic [15:0] packet_msg_count_r;
    logic [15:0] packet_msg_idx_r;
    logic [63:0] expected_sequence_r;
    logic        expected_sequence_valid_r;
    logic        packet_gap_r;
    logic        packet_done_pending_r;

    logic [15:0] msg_len_r;
    logic [15:0] msg_bytes_left_r;
    logic [15:0] payload_idx_r;

    // =========================================================================
    // Normalized event fields
    // =========================================================================
    logic [ 7:0] event_kind_r;
    logic [ 7:0] msg_type_r;
    logic [15:0] stock_locate_r;
    logic [15:0] tracking_number_r;
    logic [47:0] timestamp_r;
    logic [63:0] order_ref_r;
    logic [31:0] shares_r;
    logic [31:0] price_r;
    logic [ 7:0] side_r;
    logic [ 7:0] event_flags_r;
    logic [255:0] data_out_data_r;
    logic         data_out_valid_r;

    logic [31:0] packet_count_r;
    logic [31:0] message_count_r;
    logic [31:0] event_count_r;
    logic [31:0] error_count_r;
    logic        gap_error_r;
    logic        malformed_error_r;
    logic        unknown_msg_type_r;

    logic [7:0] input_byte;
    logic       input_fire;
    logic [15:0] header_msg_count_next;

    assign input_byte = data_in_data[7:0];
    assign input_fire = data_in_valid && data_in_ready && data_in_keep[0];
    assign header_msg_count_next = {packet_msg_count_build_r[15:8], input_byte};

    assign data_in_ready = !data_out_valid_r && (state_r != ST_EMIT);

    assign data_out_valid = data_out_valid_r;
    assign data_out_data  = data_out_data_r;
    assign data_out_keep  = data_out_valid_r ? {OUTPUT_KEEP_W{1'b1}} : '0;
    assign data_out_last  = data_out_valid_r;

    assign gap_error         = gap_error_r;
    assign malformed_error   = malformed_error_r;
    assign unknown_msg_type  = unknown_msg_type_r;
    assign expected_sequence = expected_sequence_r;
    assign packet_sequence   = packet_sequence_build_r;
    assign packet_count      = packet_count_r;
    assign message_count     = message_count_r;
    assign event_count       = event_count_r;
    assign error_count       = error_count_r;

    // =========================================================================
    // Parser FSM
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state_r                    <= ST_HEADER;
            header_idx_r               <= '0;
            packet_sequence_build_r    <= '0;
            packet_msg_count_build_r   <= '0;
            packet_msg_count_r         <= '0;
            packet_msg_idx_r           <= '0;
            expected_sequence_r        <= '0;
            expected_sequence_valid_r  <= 1'b0;
            packet_gap_r               <= 1'b0;
            packet_done_pending_r      <= 1'b0;
            msg_len_r                  <= '0;
            msg_bytes_left_r           <= '0;
            payload_idx_r              <= '0;
            event_kind_r               <= EVENT_UNKNOWN;
            msg_type_r                 <= '0;
            stock_locate_r             <= '0;
            tracking_number_r          <= '0;
            timestamp_r                <= '0;
            order_ref_r                <= '0;
            shares_r                   <= '0;
            price_r                    <= '0;
            side_r                     <= '0;
            event_flags_r              <= '0;
            data_out_data_r            <= '0;
            data_out_valid_r           <= 1'b0;
            packet_count_r             <= '0;
            message_count_r            <= '0;
            event_count_r              <= '0;
            error_count_r              <= '0;
            gap_error_r                <= 1'b0;
            malformed_error_r          <= 1'b0;
            unknown_msg_type_r         <= 1'b0;
        end else begin
            if (data_out_valid_r && data_out_ready) begin
                data_out_valid_r <= 1'b0;
            end

            case (state_r)
                ST_HEADER: begin
                    if (input_fire) begin
                        if (header_idx_r >= 5'd10 && header_idx_r <= 5'd17) begin
                            packet_sequence_build_r <= {packet_sequence_build_r[55:0], input_byte};
                        end
                        if (header_idx_r == 5'd18) begin
                            packet_msg_count_build_r[15:8] <= input_byte;
                        end
                        if (header_idx_r == 5'd19) begin
                            packet_msg_count_r    <= header_msg_count_next;
                            packet_msg_idx_r      <= '0;
                            packet_count_r        <= packet_count_r + 1;
                            packet_done_pending_r <= data_in_last;
                            header_idx_r          <= '0;

                            if (header_msg_count_next == 16'd0 || header_msg_count_next == 16'hFFFF) begin
                                if (header_msg_count_next == 16'd0) expected_sequence_r <= packet_sequence_build_r;
                                state_r <= data_in_last ? ST_HEADER : ST_DROP_PACKET;
                            end else begin
                                if (expected_sequence_valid_r &&
                                    packet_sequence_build_r != expected_sequence_r) begin
                                    packet_gap_r      <= 1'b1;
                                    gap_error_r       <= 1'b1;
                                    error_count_r     <= error_count_r + 1;
                                end else begin
                                    packet_gap_r <= 1'b0;
                                end
                                expected_sequence_r       <= packet_sequence_build_r + header_msg_count_next;
                                expected_sequence_valid_r <= 1'b1;
                                state_r                   <= ST_MSG_LEN_0;
                            end
                        end else begin
                            header_idx_r <= header_idx_r + 1'b1;
                            if (data_in_last) begin
                                malformed_error_r <= 1'b1;
                                error_count_r     <= error_count_r + 1;
                                header_idx_r      <= '0;
                                state_r           <= ST_HEADER;
                            end
                        end
                    end
                end

                ST_MSG_LEN_0: begin
                    if (input_fire) begin
                        msg_len_r[15:8] <= input_byte;
                        if (data_in_last) begin
                            malformed_error_r <= 1'b1;
                            error_count_r     <= error_count_r + 1;
                            state_r           <= ST_HEADER;
                        end else begin
                            state_r <= ST_MSG_LEN_1;
                        end
                    end
                end

                ST_MSG_LEN_1: begin
                    if (input_fire) begin
                        msg_len_r[7:0] <= input_byte;
                        if ({msg_len_r[15:8], input_byte} == 16'd0) begin
                            malformed_error_r <= 1'b1;
                            error_count_r     <= error_count_r + 1;
                            state_r           <= data_in_last ? ST_HEADER : ST_DROP_PACKET;
                        end else if (data_in_last) begin
                            malformed_error_r <= 1'b1;
                            error_count_r     <= error_count_r + 1;
                            state_r           <= ST_HEADER;
                        end else begin
                            msg_bytes_left_r      <= {msg_len_r[15:8], input_byte};
                            payload_idx_r         <= '0;
                            msg_type_r            <= '0;
                            stock_locate_r        <= '0;
                            tracking_number_r     <= '0;
                            timestamp_r           <= '0;
                            order_ref_r           <= '0;
                            shares_r              <= '0;
                            price_r               <= '0;
                            side_r                <= '0;
                            event_flags_r         <= packet_gap_r ? FLAG_GAP : 8'h00;
                            packet_done_pending_r <= 1'b0;
                            state_r               <= ST_MSG_PAYLOAD;
                        end
                    end
                end

                ST_MSG_PAYLOAD: begin
                    if (input_fire) begin
                        case (payload_idx_r)
                            16'd0:  msg_type_r <= input_byte;
                            16'd1:  stock_locate_r[15:8] <= input_byte;
                            16'd2:  stock_locate_r[7:0] <= input_byte;
                            16'd3:  tracking_number_r[15:8] <= input_byte;
                            16'd4:  tracking_number_r[7:0] <= input_byte;
                            16'd5:  timestamp_r[47:40] <= input_byte;
                            16'd6:  timestamp_r[39:32] <= input_byte;
                            16'd7:  timestamp_r[31:24] <= input_byte;
                            16'd8:  timestamp_r[23:16] <= input_byte;
                            16'd9:  timestamp_r[15:8] <= input_byte;
                            16'd10: timestamp_r[7:0] <= input_byte;
                            16'd11: if (has_order_ref(msg_type_r)) order_ref_r[63:56] <= input_byte;
                            16'd12: if (has_order_ref(msg_type_r)) order_ref_r[55:48] <= input_byte;
                            16'd13: if (has_order_ref(msg_type_r)) order_ref_r[47:40] <= input_byte;
                            16'd14: if (has_order_ref(msg_type_r)) order_ref_r[39:32] <= input_byte;
                            16'd15: if (has_order_ref(msg_type_r)) order_ref_r[31:24] <= input_byte;
                            16'd16: if (has_order_ref(msg_type_r)) order_ref_r[23:16] <= input_byte;
                            16'd17: if (has_order_ref(msg_type_r)) order_ref_r[15:8] <= input_byte;
                            16'd18: if (has_order_ref(msg_type_r)) order_ref_r[7:0] <= input_byte;
                            16'd19: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE) begin
                                    side_r <= input_byte;
                                end else if (msg_type_r == ITCH_EXECUTED || msg_type_r == ITCH_EXEC_PRICE ||
                                             msg_type_r == ITCH_CANCEL) begin
                                    shares_r[31:24] <= input_byte;
                                end
                            end
                            16'd20: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE) shares_r[31:24] <= input_byte;
                                else if (msg_type_r == ITCH_EXECUTED || msg_type_r == ITCH_EXEC_PRICE ||
                                         msg_type_r == ITCH_CANCEL) shares_r[23:16] <= input_byte;
                            end
                            16'd21: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE) shares_r[23:16] <= input_byte;
                                else if (msg_type_r == ITCH_EXECUTED || msg_type_r == ITCH_EXEC_PRICE ||
                                         msg_type_r == ITCH_CANCEL) shares_r[15:8] <= input_byte;
                            end
                            16'd22: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE) shares_r[15:8] <= input_byte;
                                else if (msg_type_r == ITCH_EXECUTED || msg_type_r == ITCH_EXEC_PRICE ||
                                         msg_type_r == ITCH_CANCEL) shares_r[7:0] <= input_byte;
                            end
                            16'd23: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE) shares_r[7:0] <= input_byte;
                            end
                            16'd27: if (msg_type_r == ITCH_REPLACE) shares_r[31:24] <= input_byte;
                            16'd28: if (msg_type_r == ITCH_REPLACE) shares_r[23:16] <= input_byte;
                            16'd29: if (msg_type_r == ITCH_REPLACE) shares_r[15:8] <= input_byte;
                            16'd30: if (msg_type_r == ITCH_REPLACE) shares_r[7:0] <= input_byte;
                            16'd31: if (msg_type_r == ITCH_REPLACE) price_r[31:24] <= input_byte;
                            16'd32: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE || msg_type_r == ITCH_EXEC_PRICE ||
                                    msg_type_r == ITCH_CROSS_TRADE) price_r[31:24] <= input_byte;
                                else if (msg_type_r == ITCH_REPLACE) price_r[23:16] <= input_byte;
                            end
                            16'd33: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE || msg_type_r == ITCH_EXEC_PRICE ||
                                    msg_type_r == ITCH_CROSS_TRADE) price_r[23:16] <= input_byte;
                                else if (msg_type_r == ITCH_REPLACE) price_r[15:8] <= input_byte;
                            end
                            16'd34: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE || msg_type_r == ITCH_EXEC_PRICE ||
                                    msg_type_r == ITCH_CROSS_TRADE) price_r[15:8] <= input_byte;
                                else if (msg_type_r == ITCH_REPLACE) price_r[7:0] <= input_byte;
                            end
                            16'd35: begin
                                if (msg_type_r == ITCH_ADD_ORDER || msg_type_r == ITCH_ADD_ORDER_MP ||
                                    msg_type_r == ITCH_TRADE || msg_type_r == ITCH_EXEC_PRICE ||
                                    msg_type_r == ITCH_CROSS_TRADE) price_r[7:0] <= input_byte;
                            end
                            default: begin
                            end
                        endcase

                        if (msg_bytes_left_r == 16'd1) begin
                            packet_done_pending_r <= data_in_last;
                            state_r               <= ST_EMIT;
                        end else begin
                            msg_bytes_left_r <= msg_bytes_left_r - 1'b1;
                            payload_idx_r    <= payload_idx_r + 1'b1;
                            if (data_in_last) begin
                                malformed_error_r <= 1'b1;
                                error_count_r     <= error_count_r + 1;
                                state_r           <= ST_HEADER;
                            end
                        end
                    end
                end

                ST_EMIT: begin
                    event_kind_r <= classify_msg(msg_type_r);
                    if (!is_supported_msg(msg_type_r)) begin
                        unknown_msg_type_r <= 1'b1;
                        event_flags_r      <= event_flags_r | FLAG_UNKNOWN;
                        error_count_r      <= error_count_r + 1;
                    end

                    data_out_data_r <= pack_event(
                        classify_msg(msg_type_r),
                        msg_type_r,
                        stock_locate_r,
                        tracking_number_r,
                        timestamp_r,
                        order_ref_r,
                        shares_r,
                        price_r,
                        side_r,
                        !is_supported_msg(msg_type_r) ? (event_flags_r | FLAG_UNKNOWN) : event_flags_r
                    );
                    data_out_valid_r <= 1'b1;
                    message_count_r  <= message_count_r + 1;
                    event_count_r    <= event_count_r + 1;
                    state_r          <= ST_WAIT_OUT;
                end

                ST_WAIT_OUT: begin
                    if (data_out_valid_r && data_out_ready) begin
                        if (packet_msg_idx_r + 1'b1 >= packet_msg_count_r) begin
                            packet_msg_idx_r <= '0;
                            state_r <= packet_done_pending_r ? ST_HEADER : ST_DROP_PACKET;
                        end else begin
                            packet_msg_idx_r <= packet_msg_idx_r + 1'b1;
                            state_r          <= ST_MSG_LEN_0;
                        end
                    end
                end

                ST_DROP_PACKET: begin
                    if (input_fire && data_in_last) begin
                        state_r      <= ST_HEADER;
                        header_idx_r <= '0;
                    end
                end

                default: begin
                    state_r      <= ST_HEADER;
                    header_idx_r <= '0;
                end
            endcase
        end
    end

endmodule
`default_nettype wire
