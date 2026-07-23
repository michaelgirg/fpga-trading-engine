`default_nettype none
// Venue-neutral order lifecycle boundary. One order may be working per symbol;
// protocol encoding is intentionally left to a downstream gateway.
module market_parser_order_manager #(
    parameter int NUM_SYMBOLS = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    },
    parameter logic [63:0] INITIAL_ORDER_ID = 64'd1
) (
    input  wire logic                         clk,
    input  wire logic                         rst,
    input  wire logic                         trading_enabled,
    input  wire logic                         cancel_all,

    input  wire logic                         intent_valid,
    output logic                              intent_ready,
    input  wire logic [15:0]                  intent_stock_locate,
    input  wire logic                         intent_side,
    input  wire logic [31:0]                  intent_price,
    input  wire logic [31:0]                  intent_quantity,
    input  wire logic [47:0]                  intent_timestamp,

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

    output logic                              fill_valid,
    output logic [15:0]                       fill_stock_locate,
    output logic                              fill_side,
    output logic [31:0]                       fill_price,
    output logic [31:0]                       fill_quantity,

    output logic [NUM_SYMBOLS-1:0]            working_order_mask,
    output logic [NUM_SYMBOLS-1:0]            live_order_mask,
    output logic [NUM_SYMBOLS*32-1:0]         leaves_quantity_by_symbol,
    output logic [15:0]                       outstanding_order_count,
    output logic [31:0]                       accepted_intent_count,
    output logic [31:0]                       busy_intent_count,
    output logic [31:0]                       untracked_intent_count,
    output logic [31:0]                       new_command_count,
    output logic [31:0]                       acknowledged_order_count,
    output logic [31:0]                       rejected_order_count,
    output logic [31:0]                       cancel_command_count,
    output logic [31:0]                       cancel_ack_count,
    output logic [31:0]                       fill_event_count,
    output logic [31:0]                       canceled_before_send_count,
    output logic [31:0]                       protocol_error_count
);
    localparam int SYMBOL_INDEX_WIDTH =
        (NUM_SYMBOLS <= 1) ? 1 : $clog2(NUM_SYMBOLS);

    localparam logic [2:0] ST_IDLE           = 3'd0;
    localparam logic [2:0] ST_NEW_QUEUED     = 3'd1;
    localparam logic [2:0] ST_NEW_PENDING    = 3'd2;
    localparam logic [2:0] ST_LIVE           = 3'd3;
    localparam logic [2:0] ST_CANCEL_QUEUED  = 3'd4;
    localparam logic [2:0] ST_CANCEL_PENDING = 3'd5;

    localparam logic [1:0] EVENT_ACK        = 2'd0;
    localparam logic [1:0] EVENT_REJECT     = 2'd1;
    localparam logic [1:0] EVENT_FILL       = 2'd2;
    localparam logic [1:0] EVENT_CANCEL_ACK = 2'd3;

    logic [2:0]  state_r [0:NUM_SYMBOLS-1];
    logic [63:0] order_id_r [0:NUM_SYMBOLS-1];
    logic        order_side_r [0:NUM_SYMBOLS-1];
    logic [31:0] order_price_r [0:NUM_SYMBOLS-1];
    logic [31:0] leaves_quantity_r [0:NUM_SYMBOLS-1];
    logic [47:0] order_timestamp_r [0:NUM_SYMBOLS-1];
    logic        cancel_requested_r [0:NUM_SYMBOLS-1];

    logic [63:0] next_order_id_r;
    logic        order_cmd_valid_r;
    logic        order_cmd_cancel_r;
    logic [63:0] order_cmd_id_r;
    logic [15:0] order_cmd_stock_locate_r;
    logic        order_cmd_side_r;
    logic [31:0] order_cmd_price_r;
    logic [31:0] order_cmd_quantity_r;
    logic [47:0] order_cmd_timestamp_r;

    logic                         intent_tracked_i;
    logic [SYMBOL_INDEX_WIDTH-1:0] intent_symbol_index_i;
    logic [NUM_SYMBOLS-1:0]       event_match_i;
    logic [NUM_SYMBOLS-1:0]       event_match_r;
    logic                         event_pipe_valid_r;
    logic [ 1:0]                  event_pipe_type_r;
    logic [31:0]                  event_pipe_price_r;
    logic [31:0]                  event_pipe_quantity_r;
    logic                         cancel_candidate_valid_i;
    logic [SYMBOL_INDEX_WIDTH-1:0] cancel_candidate_index_i;
    logic                         order_cmd_fire_i;
    logic                         intent_fire_i;
    logic                         tx_slot_available_i;

    function automatic logic [15:0] configured_locate(input int index);
        configured_locate = SYMBOL_LOCATES[index*16 +: 16];
    endfunction

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    always_comb begin
        intent_tracked_i        = 1'b0;
        intent_symbol_index_i   = '0;
        event_match_i           = '0;
        cancel_candidate_valid_i = 1'b0;
        cancel_candidate_index_i = '0;
        working_order_mask      = '0;
        live_order_mask         = '0;
        leaves_quantity_by_symbol = '0;
        outstanding_order_count = '0;

        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            if (intent_stock_locate == configured_locate(i)) begin
                intent_tracked_i      = 1'b1;
                intent_symbol_index_i = SYMBOL_INDEX_WIDTH'(i);
            end
            event_match_i[i] = state_r[i] != ST_IDLE &&
                               exchange_event_order_id == order_id_r[i];
            if (!cancel_candidate_valid_i &&
                state_r[i] == ST_LIVE && cancel_requested_r[i]) begin
                cancel_candidate_valid_i = 1'b1;
                cancel_candidate_index_i = SYMBOL_INDEX_WIDTH'(i);
            end

            working_order_mask[i] = state_r[i] != ST_IDLE;
            live_order_mask[i] = state_r[i] == ST_LIVE ||
                                 state_r[i] == ST_CANCEL_QUEUED ||
                                 state_r[i] == ST_CANCEL_PENDING;
            leaves_quantity_by_symbol[i*32 +: 32] = leaves_quantity_r[i];
            if (state_r[i] != ST_IDLE) begin
                outstanding_order_count = outstanding_order_count + 1'b1;
            end
        end
    end

    assign tx_slot_available_i = !order_cmd_valid_r || order_cmd_ready;
    assign order_cmd_fire_i = order_cmd_valid_r && order_cmd_ready;

    // Busy and untracked intents are consumed and classified without needing
    // a command slot. This prevents one live symbol from blocking all others.
    always_comb begin
        intent_ready = 1'b0;
        if (trading_enabled && !cancel_all && !event_pipe_valid_r) begin
            if (!intent_tracked_i ||
                state_r[intent_symbol_index_i] != ST_IDLE) begin
                intent_ready = 1'b1;
            end else begin
                intent_ready = tx_slot_available_i &&
                               !cancel_candidate_valid_i;
            end
        end
    end
    assign intent_fire_i = intent_valid && intent_ready;

    // Matching is registered separately from reconciliation so the 64-bit ID
    // comparisons do not share a cycle with fill arithmetic and state updates.
    // The stage consumes one event every clock and therefore never backpressures.
    assign exchange_event_ready = 1'b1;
    assign order_cmd_valid        = order_cmd_valid_r;
    assign order_cmd_cancel       = order_cmd_cancel_r;
    assign order_cmd_id           = order_cmd_id_r;
    assign order_cmd_stock_locate = order_cmd_stock_locate_r;
    assign order_cmd_side         = order_cmd_side_r;
    assign order_cmd_price        = order_cmd_price_r;
    assign order_cmd_quantity     = order_cmd_quantity_r;
    assign order_cmd_timestamp    = order_cmd_timestamp_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            event_pipe_valid_r    <= 1'b0;
            event_match_r         <= '0;
            event_pipe_type_r     <= '0;
            event_pipe_price_r    <= '0;
            event_pipe_quantity_r <= '0;
        end else begin
            event_pipe_valid_r    <= exchange_event_valid;
            event_match_r         <= event_match_i;
            event_pipe_type_r     <= exchange_event_type;
            event_pipe_price_r    <= exchange_event_price;
            event_pipe_quantity_r <= exchange_event_quantity;
        end
    end

    always_ff @(posedge clk) begin
        logic [31:0] applied_fill_quantity;

        if (rst) begin
            next_order_id_r            <= INITIAL_ORDER_ID;
            order_cmd_valid_r          <= 1'b0;
            order_cmd_cancel_r         <= 1'b0;
            order_cmd_id_r             <= '0;
            order_cmd_stock_locate_r   <= '0;
            order_cmd_side_r           <= 1'b0;
            order_cmd_price_r          <= '0;
            order_cmd_quantity_r       <= '0;
            order_cmd_timestamp_r      <= '0;
            fill_valid                 <= 1'b0;
            fill_stock_locate          <= '0;
            fill_side                  <= 1'b0;
            fill_price                 <= '0;
            fill_quantity              <= '0;
            accepted_intent_count      <= '0;
            busy_intent_count          <= '0;
            untracked_intent_count     <= '0;
            new_command_count          <= '0;
            acknowledged_order_count  <= '0;
            rejected_order_count      <= '0;
            cancel_command_count       <= '0;
            cancel_ack_count           <= '0;
            fill_event_count           <= '0;
            canceled_before_send_count <= '0;
            protocol_error_count       <= '0;
            for (int i = 0; i < NUM_SYMBOLS; i++) begin
                state_r[i]             <= ST_IDLE;
                order_id_r[i]          <= '0;
                order_side_r[i]        <= 1'b0;
                order_price_r[i]       <= '0;
                leaves_quantity_r[i]   <= '0;
                order_timestamp_r[i]   <= '0;
                cancel_requested_r[i]  <= 1'b0;
            end
        end else begin
            fill_valid <= 1'b0;

            if (order_cmd_fire_i) begin
                order_cmd_valid_r <= 1'b0;
                for (int i = 0; i < NUM_SYMBOLS; i++) begin
                    if (order_cmd_id_r == order_id_r[i]) begin
                        if (!order_cmd_cancel_r && state_r[i] == ST_NEW_QUEUED) begin
                            state_r[i] <= ST_NEW_PENDING;
                            new_command_count <=
                                increment_saturating(new_command_count);
                        end else if (order_cmd_cancel_r &&
                                     state_r[i] == ST_CANCEL_QUEUED) begin
                            state_r[i] <= ST_CANCEL_PENDING;
                            cancel_command_count <=
                                increment_saturating(cancel_command_count);
                        end
                    end
                end
            end

            // Fail closed: withdraw a new command that has not crossed yet,
            // and mark sent or live orders for deterministic cancellation.
            if (cancel_all) begin
                for (int i = 0; i < NUM_SYMBOLS; i++) begin
                    if (state_r[i] == ST_NEW_QUEUED &&
                        order_cmd_valid_r && !order_cmd_cancel_r &&
                        order_cmd_id_r == order_id_r[i] &&
                        !order_cmd_fire_i) begin
                        state_r[i]            <= ST_IDLE;
                        leaves_quantity_r[i]  <= '0;
                        cancel_requested_r[i] <= 1'b0;
                        order_cmd_valid_r     <= 1'b0;
                        canceled_before_send_count <=
                            increment_saturating(canceled_before_send_count);
                    end else if (state_r[i] == ST_NEW_PENDING ||
                                 state_r[i] == ST_LIVE ||
                                 (state_r[i] == ST_NEW_QUEUED &&
                                  order_cmd_fire_i)) begin
                        cancel_requested_r[i] <= 1'b1;
                    end
                end
            end

            if (event_pipe_valid_r) begin
                if (event_match_r == '0) begin
                    protocol_error_count <=
                        increment_saturating(protocol_error_count);
                end else begin
                    for (int i = 0; i < NUM_SYMBOLS; i++) begin
                        if (event_match_r[i]) begin
                            case (event_pipe_type_r)
                                EVENT_ACK: begin
                                    if (state_r[i] == ST_NEW_PENDING) begin
                                        state_r[i] <= ST_LIVE;
                                        acknowledged_order_count <=
                                            increment_saturating(
                                                acknowledged_order_count);
                                    end else begin
                                        protocol_error_count <=
                                            increment_saturating(
                                                protocol_error_count);
                                    end
                                end
                                EVENT_REJECT: begin
                                    if (state_r[i] == ST_NEW_PENDING) begin
                                        state_r[i] <= ST_IDLE;
                                        leaves_quantity_r[i] <= '0;
                                        cancel_requested_r[i] <= 1'b0;
                                        rejected_order_count <=
                                            increment_saturating(
                                                rejected_order_count);
                                    end else begin
                                        protocol_error_count <=
                                            increment_saturating(
                                                protocol_error_count);
                                    end
                                end
                                EVENT_FILL: begin
                                    if ((state_r[i] == ST_LIVE ||
                                         state_r[i] == ST_CANCEL_QUEUED ||
                                         state_r[i] == ST_CANCEL_PENDING) &&
                                        event_pipe_quantity_r != 32'd0) begin
                                        if (event_pipe_quantity_r >
                                            leaves_quantity_r[i]) begin
                                            applied_fill_quantity =
                                                leaves_quantity_r[i];
                                            protocol_error_count <=
                                                increment_saturating(
                                                    protocol_error_count);
                                        end else begin
                                            applied_fill_quantity =
                                                event_pipe_quantity_r;
                                        end

                                        fill_valid <= 1'b1;
                                        fill_stock_locate <= configured_locate(i);
                                        fill_side <= order_side_r[i];
                                        fill_price <= event_pipe_price_r;
                                        fill_quantity <= applied_fill_quantity;
                                        fill_event_count <=
                                            increment_saturating(fill_event_count);

                                        if (applied_fill_quantity >=
                                            leaves_quantity_r[i]) begin
                                            state_r[i] <= ST_IDLE;
                                            leaves_quantity_r[i] <= '0;
                                            cancel_requested_r[i] <= 1'b0;
                                            if (state_r[i] == ST_CANCEL_QUEUED &&
                                                order_cmd_valid_r &&
                                                order_cmd_cancel_r &&
                                                order_cmd_id_r == order_id_r[i] &&
                                                !order_cmd_fire_i) begin
                                                order_cmd_valid_r <= 1'b0;
                                            end
                                        end else begin
                                            leaves_quantity_r[i] <=
                                                leaves_quantity_r[i] -
                                                applied_fill_quantity;
                                        end
                                    end else begin
                                        protocol_error_count <=
                                            increment_saturating(
                                                protocol_error_count);
                                    end
                                end
                                EVENT_CANCEL_ACK: begin
                                    if (state_r[i] == ST_CANCEL_PENDING) begin
                                        state_r[i] <= ST_IDLE;
                                        leaves_quantity_r[i] <= '0;
                                        cancel_requested_r[i] <= 1'b0;
                                        cancel_ack_count <=
                                            increment_saturating(cancel_ack_count);
                                    end else begin
                                        protocol_error_count <=
                                            increment_saturating(
                                                protocol_error_count);
                                    end
                                end
                                default: begin
                                    protocol_error_count <=
                                        increment_saturating(
                                            protocol_error_count);
                                end
                            endcase
                        end
                    end
                end
            end else if (tx_slot_available_i && cancel_candidate_valid_i) begin
                order_cmd_valid_r        <= 1'b1;
                order_cmd_cancel_r       <= 1'b1;
                order_cmd_id_r           <= order_id_r[cancel_candidate_index_i];
                order_cmd_stock_locate_r <=
                    configured_locate(cancel_candidate_index_i);
                order_cmd_side_r         <= order_side_r[cancel_candidate_index_i];
                order_cmd_price_r        <= order_price_r[cancel_candidate_index_i];
                order_cmd_quantity_r     <=
                    leaves_quantity_r[cancel_candidate_index_i];
                order_cmd_timestamp_r    <=
                    order_timestamp_r[cancel_candidate_index_i];
                state_r[cancel_candidate_index_i] <= ST_CANCEL_QUEUED;
                cancel_requested_r[cancel_candidate_index_i] <= 1'b0;
            end

            if (intent_fire_i) begin
                if (!intent_tracked_i) begin
                    untracked_intent_count <=
                        increment_saturating(untracked_intent_count);
                end else if (state_r[intent_symbol_index_i] != ST_IDLE) begin
                    busy_intent_count <=
                        increment_saturating(busy_intent_count);
                end else if (!cancel_candidate_valid_i &&
                             !event_pipe_valid_r && tx_slot_available_i) begin
                    state_r[intent_symbol_index_i] <= ST_NEW_QUEUED;
                    order_id_r[intent_symbol_index_i] <= next_order_id_r;
                    order_side_r[intent_symbol_index_i] <= intent_side;
                    order_price_r[intent_symbol_index_i] <= intent_price;
                    leaves_quantity_r[intent_symbol_index_i] <= intent_quantity;
                    order_timestamp_r[intent_symbol_index_i] <= intent_timestamp;
                    cancel_requested_r[intent_symbol_index_i] <= 1'b0;

                    order_cmd_valid_r        <= 1'b1;
                    order_cmd_cancel_r       <= 1'b0;
                    order_cmd_id_r           <= next_order_id_r;
                    order_cmd_stock_locate_r <= intent_stock_locate;
                    order_cmd_side_r         <= intent_side;
                    order_cmd_price_r        <= intent_price;
                    order_cmd_quantity_r     <= intent_quantity;
                    order_cmd_timestamp_r    <= intent_timestamp;
                    next_order_id_r <= (next_order_id_r == 64'hffff_ffff_ffff_ffff) ?
                                       INITIAL_ORDER_ID : next_order_id_r + 1'b1;
                    accepted_intent_count <=
                        increment_saturating(accepted_intent_count);
                end
            end
        end
    end

endmodule
`default_nettype wire
