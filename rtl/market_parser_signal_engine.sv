`default_nettype none
// =============================================================================
// Module: market_parser_signal_engine
// =============================================================================
// Deterministic quote-to-order-intent boundary. The block is intentionally
// venue-neutral: it emits risk-checked intents, not encoded exchange orders.
module market_parser_signal_engine #(
    parameter int NUM_SYMBOLS = 4,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = {
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    }
) (
    input  wire logic                         clk,
    input  wire logic                         rst,

    input  wire logic                         quote_valid,
    output logic                              quote_ready,
    input  wire logic [15:0]                  quote_stock_locate,
    input  wire logic [31:0]                  quote_bid_price,
    input  wire logic [31:0]                  quote_bid_shares,
    input  wire logic [31:0]                  quote_ask_price,
    input  wire logic [31:0]                  quote_ask_shares,
    input  wire logic [47:0]                  quote_timestamp,

    input  wire logic                         feed_healthy,
    input  wire logic                         strategy_enable,
    input  wire logic                         kill_switch,
    input  wire logic                         position_clear,
    input  wire logic [31:0]                  max_spread_ticks,
    input  wire logic [31:0]                  min_top_shares,
    input  wire logic [ 2:0]                  imbalance_shift,
    input  wire logic [31:0]                  order_quantity,
    input  wire logic [31:0]                  max_abs_position,

    input  wire logic                         fill_valid,
    input  wire logic [15:0]                  fill_stock_locate,
    input  wire logic                         fill_side,
    input  wire logic [31:0]                  fill_quantity,

    output logic                              intent_valid,
    input  wire logic                         intent_ready,
    output logic [15:0]                       intent_stock_locate,
    output logic                              intent_side,
    output logic [31:0]                       intent_price,
    output logic [31:0]                       intent_quantity,
    output logic [47:0]                       intent_timestamp,

    output logic [NUM_SYMBOLS*32-1:0]         position_by_symbol,
    output logic [31:0]                       evaluated_quote_count,
    output logic [31:0]                       generated_intent_count,
    output logic [31:0]                       control_suppressed_count,
    output logic [31:0]                       market_suppressed_count,
    output logic [31:0]                       risk_suppressed_count,
    output logic [31:0]                       applied_fill_count,
    output logic [31:0]                       untracked_fill_count
);
    localparam int SYMBOL_INDEX_WIDTH = (NUM_SYMBOLS <= 1) ? 1 : $clog2(NUM_SYMBOLS);
    localparam int QUOTE_FIFO_DEPTH = 4;
    localparam int QUOTE_FIFO_PTR_WIDTH = $clog2(QUOTE_FIFO_DEPTH);

    logic signed [31:0] position_r [0:NUM_SYMBOLS-1];

    logic                          input_quote_tracked_i;
    logic [SYMBOL_INDEX_WIDTH-1:0] input_quote_symbol_index_i;
    logic                          fill_tracked_i;
    logic [SYMBOL_INDEX_WIDTH-1:0] fill_symbol_index_i;

    logic [QUOTE_FIFO_PTR_WIDTH-1:0] quote_fifo_write_ptr_r;
    logic [QUOTE_FIFO_PTR_WIDTH-1:0] quote_fifo_read_ptr_r;
    logic [QUOTE_FIFO_PTR_WIDTH:0]   quote_fifo_count_r;
    logic                            quote_fifo_tracked_r [0:QUOTE_FIFO_DEPTH-1];
    logic [SYMBOL_INDEX_WIDTH-1:0]   quote_fifo_symbol_index_r [0:QUOTE_FIFO_DEPTH-1];
    logic [15:0]                     quote_fifo_stock_locate_r [0:QUOTE_FIFO_DEPTH-1];
    logic [31:0]                     quote_fifo_bid_price_r [0:QUOTE_FIFO_DEPTH-1];
    logic [31:0]                     quote_fifo_bid_shares_r [0:QUOTE_FIFO_DEPTH-1];
    logic [31:0]                     quote_fifo_ask_price_r [0:QUOTE_FIFO_DEPTH-1];
    logic [31:0]                     quote_fifo_ask_shares_r [0:QUOTE_FIFO_DEPTH-1];
    logic [47:0]                     quote_fifo_timestamp_r [0:QUOTE_FIFO_DEPTH-1];
    logic                            quote_stage_valid_i;
    logic                            quote_stage_tracked_i;
    logic [SYMBOL_INDEX_WIDTH-1:0]   quote_stage_symbol_index_i;
    logic [15:0]                     quote_stage_stock_locate_i;
    logic [31:0]                     quote_stage_bid_price_i;
    logic [31:0]                     quote_stage_bid_shares_i;
    logic [31:0]                     quote_stage_ask_price_i;
    logic [31:0]                     quote_stage_ask_shares_i;
    logic [47:0]                     quote_stage_timestamp_i;

    logic [63:0]                   shifted_ask_shares_i;
    logic [63:0]                   shifted_bid_shares_i;
    logic [31:0]                   spread_i;
    logic                          quote_stage_market_valid_i;
    logic                          quote_stage_buy_signal_i;
    logic                          quote_stage_sell_signal_i;

    logic                          analysis_valid_r;
    logic                          analysis_control_valid_r;
    logic                          analysis_market_valid_r;
    logic                          analysis_buy_signal_r;
    logic                          analysis_sell_signal_r;
    logic [SYMBOL_INDEX_WIDTH-1:0] analysis_symbol_index_r;
    logic [15:0]                   analysis_stock_locate_r;
    logic [31:0]                   analysis_bid_price_r;
    logic [31:0]                   analysis_ask_price_r;
    logic [31:0]                   analysis_order_quantity_r;
    logic signed [32:0]            analysis_buy_position_limit_r;
    logic signed [32:0]            analysis_sell_position_limit_r;
    logic [47:0]                   analysis_timestamp_r;

    logic signed [32:0]            current_position_i;
    logic                          buy_risk_valid_i;
    logic                          sell_risk_valid_i;
    logic                          intent_permitted_i;
    logic                          intent_slot_available_i;
    logic                          create_buy_intent_i;
    logic                          create_sell_intent_i;
    logic                          create_intent_i;
    logic                          control_suppressed_i;
    logic                          market_suppressed_i;
    logic                          risk_suppressed_i;
    logic                          analysis_retire_i;
    logic                          analysis_ready_i;
    logic                          quote_stage_advance_i;
    logic                          quote_fire_i;

    logic                          count_event_valid_r;
    logic                          count_control_event_r;
    logic                          count_market_event_r;
    logic                          count_risk_event_r;
    logic                          count_intent_event_r;

    logic                          intent_valid_r;
    logic [15:0]                   intent_stock_locate_r;
    logic                          intent_side_r;
    logic [31:0]                   intent_price_r;
    logic [31:0]                   intent_quantity_r;
    logic [47:0]                   intent_timestamp_r;

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating = (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    always_comb begin
        input_quote_tracked_i      = 1'b0;
        input_quote_symbol_index_i = '0;
        fill_tracked_i             = 1'b0;
        fill_symbol_index_i        = '0;

        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            if (quote_stock_locate == SYMBOL_LOCATES[i*16 +: 16]) begin
                input_quote_tracked_i      = 1'b1;
                input_quote_symbol_index_i = SYMBOL_INDEX_WIDTH'(i);
            end
            if (fill_stock_locate == SYMBOL_LOCATES[i*16 +: 16]) begin
                fill_tracked_i      = 1'b1;
                fill_symbol_index_i = SYMBOL_INDEX_WIDTH'(i);
            end
            position_by_symbol[i*32 +: 32] = position_r[i];
        end
    end

    always_comb begin
        shifted_ask_shares_i = {32'd0, quote_stage_ask_shares_i} <<
                               imbalance_shift;
        shifted_bid_shares_i = {32'd0, quote_stage_bid_shares_i} <<
                               imbalance_shift;
        spread_i = quote_stage_ask_price_i - quote_stage_bid_price_i;

        quote_stage_market_valid_i = quote_stage_tracked_i &&
            quote_stage_bid_price_i != 32'd0 &&
            quote_stage_ask_price_i > quote_stage_bid_price_i &&
            quote_stage_bid_shares_i != 32'd0 &&
            quote_stage_ask_shares_i != 32'd0 &&
            max_spread_ticks != 32'd0 && spread_i <= max_spread_ticks &&
            quote_stage_bid_shares_i >= min_top_shares &&
            quote_stage_ask_shares_i >= min_top_shares;
        quote_stage_buy_signal_i =
            {32'd0, quote_stage_bid_shares_i} > shifted_ask_shares_i;
        quote_stage_sell_signal_i =
            {32'd0, quote_stage_ask_shares_i} > shifted_bid_shares_i;
    end

    always_comb begin
        current_position_i =
            $signed({position_r[analysis_symbol_index_r][31],
                     position_r[analysis_symbol_index_r]});
        buy_risk_valid_i =
            current_position_i <= analysis_buy_position_limit_r;
        sell_risk_valid_i =
            current_position_i >= analysis_sell_position_limit_r;
    end

    assign quote_stage_valid_i = quote_fifo_count_r != 0;
    assign quote_stage_tracked_i =
        quote_fifo_tracked_r[quote_fifo_read_ptr_r];
    assign quote_stage_symbol_index_i =
        quote_fifo_symbol_index_r[quote_fifo_read_ptr_r];
    assign quote_stage_stock_locate_i =
        quote_fifo_stock_locate_r[quote_fifo_read_ptr_r];
    assign quote_stage_bid_price_i =
        quote_fifo_bid_price_r[quote_fifo_read_ptr_r];
    assign quote_stage_bid_shares_i =
        quote_fifo_bid_shares_r[quote_fifo_read_ptr_r];
    assign quote_stage_ask_price_i =
        quote_fifo_ask_price_r[quote_fifo_read_ptr_r];
    assign quote_stage_ask_shares_i =
        quote_fifo_ask_shares_r[quote_fifo_read_ptr_r];
    assign quote_stage_timestamp_i =
        quote_fifo_timestamp_r[quote_fifo_read_ptr_r];

    assign intent_permitted_i = feed_healthy && strategy_enable && !kill_switch;
    assign intent_valid = intent_valid_r && intent_permitted_i &&
                          !fill_valid && !position_clear;
    assign intent_slot_available_i = !intent_valid_r || intent_ready ||
                                     !intent_permitted_i;

    assign control_suppressed_i = analysis_valid_r &&
                                  (!analysis_control_valid_r ||
                                   !intent_permitted_i);
    assign market_suppressed_i = analysis_valid_r &&
                                 !control_suppressed_i &&
                                 (!analysis_market_valid_r ||
                                  (!analysis_buy_signal_r &&
                                   !analysis_sell_signal_r));
    assign risk_suppressed_i = analysis_valid_r &&
                               !control_suppressed_i &&
                               !market_suppressed_i &&
                               ((analysis_buy_signal_r &&
                                 !buy_risk_valid_i) ||
                                (analysis_sell_signal_r &&
                                 !sell_risk_valid_i));
    assign create_buy_intent_i = analysis_valid_r &&
                                 !control_suppressed_i &&
                                 !market_suppressed_i &&
                                 !risk_suppressed_i &&
                                 analysis_buy_signal_r;
    assign create_sell_intent_i = analysis_valid_r &&
                                  !control_suppressed_i &&
                                  !market_suppressed_i &&
                                  !risk_suppressed_i &&
                                  analysis_sell_signal_r;
    assign create_intent_i = create_buy_intent_i || create_sell_intent_i;

    // Fills and position clears hold both analysis stages for one cycle. The
    // pending quote is then risk-checked against the updated position.
    assign analysis_retire_i = analysis_valid_r && !fill_valid &&
                               !position_clear &&
                               (!create_intent_i || intent_slot_available_i);
    assign analysis_ready_i = !analysis_valid_r || analysis_retire_i;
    assign quote_stage_advance_i = quote_stage_valid_i && analysis_ready_i &&
                                   !fill_valid && !position_clear;
    // Upstream ready depends only on registered FIFO occupancy. Risk and
    // intent backpressure cannot propagate into the book/feed control path.
    assign quote_ready = (quote_fifo_count_r < QUOTE_FIFO_DEPTH) &&
                         !fill_valid && !position_clear;
    assign quote_fire_i = quote_valid && quote_ready;

    assign intent_stock_locate = intent_stock_locate_r;
    assign intent_side         = intent_side_r;
    assign intent_price        = intent_price_r;
    assign intent_quantity     = intent_quantity_r;
    assign intent_timestamp    = intent_timestamp_r;

    always_ff @(posedge clk) begin
        logic signed [32:0] fill_position_next;

        if (rst) begin
            quote_fifo_write_ptr_r     <= '0;
            quote_fifo_read_ptr_r      <= '0;
            quote_fifo_count_r         <= '0;
            analysis_valid_r          <= 1'b0;
            analysis_control_valid_r  <= 1'b0;
            analysis_market_valid_r   <= 1'b0;
            analysis_buy_signal_r     <= 1'b0;
            analysis_sell_signal_r    <= 1'b0;
            analysis_symbol_index_r   <= '0;
            analysis_stock_locate_r   <= '0;
            analysis_bid_price_r      <= '0;
            analysis_ask_price_r      <= '0;
            analysis_order_quantity_r <= '0;
            analysis_buy_position_limit_r <= '0;
            analysis_sell_position_limit_r <= '0;
            analysis_timestamp_r      <= '0;
            intent_valid_r            <= 1'b0;
            intent_stock_locate_r     <= '0;
            intent_side_r             <= 1'b0;
            intent_price_r            <= '0;
            intent_quantity_r         <= '0;
            intent_timestamp_r        <= '0;
            count_event_valid_r       <= 1'b0;
            count_control_event_r     <= 1'b0;
            count_market_event_r      <= 1'b0;
            count_risk_event_r        <= 1'b0;
            count_intent_event_r      <= 1'b0;
            evaluated_quote_count     <= '0;
            generated_intent_count    <= '0;
            control_suppressed_count  <= '0;
            market_suppressed_count   <= '0;
            risk_suppressed_count     <= '0;
            applied_fill_count        <= '0;
            untracked_fill_count      <= '0;
            for (int i = 0; i < NUM_SYMBOLS; i++) begin
                position_r[i] <= '0;
            end
        end else begin
            if (!intent_permitted_i || fill_valid || position_clear) begin
                intent_valid_r <= 1'b0;
            end else begin
                if (intent_valid_r && intent_ready) begin
                    intent_valid_r <= 1'b0;
                end
                if (analysis_retire_i && create_intent_i) begin
                    intent_valid_r        <= 1'b1;
                    intent_stock_locate_r <= analysis_stock_locate_r;
                    intent_side_r         <= create_sell_intent_i;
                    intent_price_r        <= create_buy_intent_i ?
                                             analysis_ask_price_r :
                                             analysis_bid_price_r;
                    intent_quantity_r     <= analysis_order_quantity_r;
                    intent_timestamp_r    <= analysis_timestamp_r;
                end
            end

            if (position_clear) begin
                for (int i = 0; i < NUM_SYMBOLS; i++) begin
                    position_r[i] <= '0;
                end
            end else if (fill_valid) begin
                if (fill_tracked_i) begin
                    if (fill_side == 1'b0) begin
                        fill_position_next =
                            $signed(position_r[fill_symbol_index_i]) +
                            $signed({1'b0, fill_quantity});
                    end else begin
                        fill_position_next =
                            $signed(position_r[fill_symbol_index_i]) -
                            $signed({1'b0, fill_quantity});
                    end

                    if (fill_position_next > 33'sh0_7fff_ffff) begin
                        position_r[fill_symbol_index_i] <= 32'sh7fff_ffff;
                    end else if (fill_position_next < -33'sh0_8000_0000) begin
                        position_r[fill_symbol_index_i] <= 32'sh8000_0000;
                    end else begin
                        position_r[fill_symbol_index_i] <=
                            fill_position_next[31:0];
                    end
                    applied_fill_count <=
                        increment_saturating(applied_fill_count);
                end else begin
                    untracked_fill_count <=
                        increment_saturating(untracked_fill_count);
                end
            end

            if (quote_stage_advance_i) begin
                analysis_valid_r <= 1'b1;
                analysis_control_valid_r <= intent_permitted_i &&
                    order_quantity != 32'd0 && max_abs_position != 32'd0;
                analysis_market_valid_r <= quote_stage_market_valid_i;
                analysis_buy_signal_r <= quote_stage_buy_signal_i;
                analysis_sell_signal_r <= quote_stage_sell_signal_i;
                analysis_symbol_index_r <= quote_stage_symbol_index_i;
                analysis_stock_locate_r <= quote_stage_stock_locate_i;
                analysis_bid_price_r <= quote_stage_bid_price_i;
                analysis_ask_price_r <= quote_stage_ask_price_i;
                analysis_order_quantity_r <= order_quantity;
                analysis_buy_position_limit_r <=
                    $signed({1'b0, max_abs_position}) -
                    $signed({1'b0, order_quantity});
                analysis_sell_position_limit_r <=
                    -$signed({1'b0, max_abs_position}) +
                    $signed({1'b0, order_quantity});
                analysis_timestamp_r <= quote_stage_timestamp_i;
            end else if (analysis_retire_i) begin
                analysis_valid_r <= 1'b0;
            end

            if (quote_fire_i) begin
                quote_fifo_tracked_r[quote_fifo_write_ptr_r] <=
                    input_quote_tracked_i;
                quote_fifo_symbol_index_r[quote_fifo_write_ptr_r] <=
                    input_quote_symbol_index_i;
                quote_fifo_stock_locate_r[quote_fifo_write_ptr_r] <=
                    quote_stock_locate;
                quote_fifo_bid_price_r[quote_fifo_write_ptr_r] <=
                    quote_bid_price;
                quote_fifo_bid_shares_r[quote_fifo_write_ptr_r] <=
                    quote_bid_shares;
                quote_fifo_ask_price_r[quote_fifo_write_ptr_r] <=
                    quote_ask_price;
                quote_fifo_ask_shares_r[quote_fifo_write_ptr_r] <=
                    quote_ask_shares;
                quote_fifo_timestamp_r[quote_fifo_write_ptr_r] <=
                    quote_timestamp;
                quote_fifo_write_ptr_r <= quote_fifo_write_ptr_r + 1'b1;
            end
            if (quote_stage_advance_i) begin
                quote_fifo_read_ptr_r <= quote_fifo_read_ptr_r + 1'b1;
            end
            case ({quote_fire_i, quote_stage_advance_i})
                2'b10: quote_fifo_count_r <= quote_fifo_count_r + 1'b1;
                2'b01: quote_fifo_count_r <= quote_fifo_count_r - 1'b1;
                default: quote_fifo_count_r <= quote_fifo_count_r;
            endcase

            if (count_event_valid_r) begin
                evaluated_quote_count <=
                    increment_saturating(evaluated_quote_count);
                if (count_control_event_r) begin
                    control_suppressed_count <=
                        increment_saturating(control_suppressed_count);
                end else if (count_market_event_r) begin
                    market_suppressed_count <=
                        increment_saturating(market_suppressed_count);
                end else if (count_risk_event_r) begin
                    risk_suppressed_count <=
                        increment_saturating(risk_suppressed_count);
                end else if (count_intent_event_r) begin
                    generated_intent_count <=
                        increment_saturating(generated_intent_count);
                end
            end

            // Register classification before touching the counters. This keeps
            // arithmetic and risk logic out of the wide counter-enable cones.
            count_event_valid_r   <= analysis_retire_i;
            count_control_event_r <= analysis_retire_i &&
                                     control_suppressed_i;
            count_market_event_r  <= analysis_retire_i &&
                                     market_suppressed_i;
            count_risk_event_r    <= analysis_retire_i && risk_suppressed_i;
            count_intent_event_r  <= analysis_retire_i && create_intent_i;
        end
    end

endmodule
`default_nettype wire
