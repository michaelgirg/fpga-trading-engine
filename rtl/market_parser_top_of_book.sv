`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_top_of_book
// =============================================================================
// Small single-symbol top-of-book engine for normalized ITCH events.
//
// This block keeps a compact order table, applies add/execute/cancel/delete/
// replace events, and emits a quote update whenever the best bid/ask price or
// displayed size changes. Table lookup and quote recompute are iterative so the
// timing path stays small on FPGA.
module market_parser_top_of_book #(
    parameter int          ORDER_TABLE_DEPTH   = 16,
    parameter logic [15:0] TARGET_STOCK_LOCATE = 16'h0001
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         event_valid,
    output logic              event_ready,
    input  wire logic [255:0] event_data,
    input  wire logic [ 63:0] event_new_order_ref,
    input  wire logic [ 31:0] event_keep,
    input  wire logic         event_last,

    output logic              quote_valid,
    input  wire logic         quote_ready,
    output logic [15:0]       quote_stock_locate,
    output logic [31:0]       quote_bid_price,
    output logic [31:0]       quote_bid_shares,
    output logic [31:0]       quote_ask_price,
    output logic [31:0]       quote_ask_shares,
    output logic [47:0]       quote_timestamp,

    output logic [31:0]       accepted_event_count,
    output logic [31:0]       applied_event_count,
    output logic [31:0]       ignored_event_count,
    output logic [31:0]       table_overflow_count,
    output logic [31:0]       quote_update_count
);
    localparam int PTR_WIDTH = (ORDER_TABLE_DEPTH <= 1) ? 1 : $clog2(ORDER_TABLE_DEPTH);

    initial begin
        if (ORDER_TABLE_DEPTH < 2) begin
            $fatal(1, "ORDER_TABLE_DEPTH must be at least 2");
        end
    end

    typedef enum logic [2:0] {
        STATE_IDLE     = 3'd0,
        STATE_LOOKUP   = 3'd1,
        STATE_APPLY    = 3'd2,
        STATE_SCAN     = 3'd3,
        STATE_FINALIZE = 3'd4
    } state_t;

    state_t                 state_r;

    logic                   active_q   [ORDER_TABLE_DEPTH];
    logic [15:0]            stock_q    [ORDER_TABLE_DEPTH];
    logic [63:0]            order_ref_q[ORDER_TABLE_DEPTH];
    logic [ 7:0]            side_q     [ORDER_TABLE_DEPTH];
    logic [31:0]            shares_q   [ORDER_TABLE_DEPTH];
    logic [31:0]            price_q    [ORDER_TABLE_DEPTH];

    logic                   quote_valid_r;
    logic [31:0]            best_bid_price_r;
    logic [31:0]            best_bid_shares_r;
    logic [31:0]            best_ask_price_r;
    logic [31:0]            best_ask_shares_r;
    logic [47:0]            quote_timestamp_r;

    logic [31:0]            scan_bid_price_r;
    logic [31:0]            scan_bid_shares_r;
    logic [31:0]            scan_ask_price_r;
    logic [31:0]            scan_ask_shares_r;

    logic [ 7:0]            pending_kind_r;
    logic [15:0]            pending_stock_r;
    logic [47:0]            pending_timestamp_r;
    logic [63:0]            pending_order_ref_r;
    logic [63:0]            pending_new_order_ref_r;
    logic [31:0]            pending_shares_r;
    logic [31:0]            pending_price_r;
    logic [ 7:0]            pending_side_r;

    logic [PTR_WIDTH-1:0]   lookup_idx_r;
    logic [PTR_WIDTH-1:0]   scan_idx_r;
    logic [PTR_WIDTH-1:0]   found_idx_r;
    logic [PTR_WIDTH-1:0]   free_idx_r;
    logic                   found_valid_r;
    logic                   free_valid_r;

    logic [31:0]            accepted_event_count_r;
    logic [31:0]            applied_event_count_r;
    logic [31:0]            ignored_event_count_r;
    logic [31:0]            table_overflow_count_r;
    logic [31:0]            quote_update_count_r;

    logic [ 7:0]            event_kind_i;
    logic [15:0]            event_stock_i;
    logic [47:0]            event_timestamp_i;
    logic [63:0]            event_order_ref_i;
    logic [31:0]            event_shares_i;
    logic [31:0]            event_price_i;
    logic [ 7:0]            event_side_i;
    logic [ 7:0]            event_flags_i;
    logic                   event_fire_i;
    logic                   target_match_i;
    logic                   event_clean_i;

    assign event_kind_i      = event_data[7:0];
    assign event_stock_i     = event_data[31:16];
    assign event_timestamp_i = event_data[95:48];
    assign event_order_ref_i = event_data[159:96];
    assign event_shares_i    = event_data[191:160];
    assign event_price_i     = event_data[223:192];
    assign event_side_i      = event_data[231:224];
    assign event_flags_i     = event_data[239:232];

    assign target_match_i = (event_stock_i == TARGET_STOCK_LOCATE);
    assign event_clean_i  = (event_flags_i == 8'h00) && (event_keep == 32'hffff_ffff);

    assign event_ready = (state_r == STATE_IDLE) && (!quote_valid_r || quote_ready);
    assign event_fire_i = event_valid && event_ready;

    assign quote_valid        = quote_valid_r;
    assign quote_stock_locate = TARGET_STOCK_LOCATE;
    assign quote_bid_price    = best_bid_price_r;
    assign quote_bid_shares   = best_bid_shares_r;
    assign quote_ask_price    = best_ask_price_r;
    assign quote_ask_shares   = best_ask_shares_r;
    assign quote_timestamp    = quote_timestamp_r;

    assign accepted_event_count = accepted_event_count_r;
    assign applied_event_count  = applied_event_count_r;
    assign ignored_event_count  = ignored_event_count_r;
    assign table_overflow_count = table_overflow_count_r;
    assign quote_update_count   = quote_update_count_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int idx = 0; idx < ORDER_TABLE_DEPTH; idx++) begin
                active_q[idx]    <= 1'b0;
                stock_q[idx]     <= '0;
                order_ref_q[idx] <= '0;
                side_q[idx]      <= '0;
                shares_q[idx]    <= '0;
                price_q[idx]     <= '0;
            end

            state_r                <= STATE_IDLE;
            quote_valid_r          <= 1'b0;
            best_bid_price_r       <= '0;
            best_bid_shares_r      <= '0;
            best_ask_price_r       <= '0;
            best_ask_shares_r      <= '0;
            quote_timestamp_r      <= '0;
            scan_bid_price_r       <= '0;
            scan_bid_shares_r      <= '0;
            scan_ask_price_r       <= '0;
            scan_ask_shares_r      <= '0;
            pending_kind_r         <= '0;
            pending_stock_r        <= '0;
            pending_timestamp_r    <= '0;
            pending_order_ref_r    <= '0;
            pending_new_order_ref_r <= '0;
            pending_shares_r       <= '0;
            pending_price_r        <= '0;
            pending_side_r         <= '0;
            lookup_idx_r           <= '0;
            scan_idx_r             <= '0;
            found_idx_r            <= '0;
            free_idx_r             <= '0;
            found_valid_r          <= 1'b0;
            free_valid_r           <= 1'b0;
            accepted_event_count_r <= '0;
            applied_event_count_r  <= '0;
            ignored_event_count_r  <= '0;
            table_overflow_count_r <= '0;
            quote_update_count_r   <= '0;
        end else begin
            if (quote_valid_r && quote_ready) begin
                quote_valid_r <= 1'b0;
            end

            unique case (state_r)
                STATE_IDLE: begin
                    if (event_fire_i) begin
                        accepted_event_count_r <= accepted_event_count_r + 1'b1;

                        if (!target_match_i || !event_clean_i) begin
                            ignored_event_count_r <= ignored_event_count_r + 1'b1;
                        end else begin
                            pending_kind_r      <= event_kind_i;
                            pending_stock_r     <= event_stock_i;
                            pending_timestamp_r <= event_timestamp_i;
                            pending_order_ref_r <= event_order_ref_i;
                            pending_new_order_ref_r <= event_new_order_ref;
                            pending_shares_r    <= event_shares_i;
                            pending_price_r     <= event_price_i;
                            pending_side_r      <= event_side_i;
                            lookup_idx_r        <= '0;
                            found_idx_r         <= '0;
                            free_idx_r          <= '0;
                            found_valid_r       <= 1'b0;
                            free_valid_r        <= 1'b0;
                            state_r             <= STATE_LOOKUP;
                        end
                    end
                end

                STATE_LOOKUP: begin
                    if (active_q[lookup_idx_r] &&
                        order_ref_q[lookup_idx_r] == pending_order_ref_r &&
                        stock_q[lookup_idx_r] == TARGET_STOCK_LOCATE &&
                        !found_valid_r) begin
                        found_valid_r <= 1'b1;
                        found_idx_r   <= lookup_idx_r;
                    end

                    if (!active_q[lookup_idx_r] && !free_valid_r) begin
                        free_valid_r <= 1'b1;
                        free_idx_r   <= lookup_idx_r;
                    end

                    if (lookup_idx_r == PTR_WIDTH'(ORDER_TABLE_DEPTH - 1)) begin
                        state_r <= STATE_APPLY;
                    end else begin
                        lookup_idx_r <= lookup_idx_r + 1'b1;
                    end
                end

                STATE_APPLY: begin
                    int write_idx;
                    bit applied;
                    bit ignored;
                    bit overflow;

                    write_idx = -1;
                    applied   = 1'b0;
                    ignored   = 1'b0;
                    overflow  = 1'b0;

                    unique case (pending_kind_r)
                        EVENT_ADD: begin
                            if ((pending_side_r == "B" || pending_side_r == "S") &&
                                pending_shares_r != 32'd0 && pending_price_r != 32'd0) begin
                                if (found_valid_r) begin
                                    write_idx = int'(found_idx_r);
                                end else if (free_valid_r) begin
                                    write_idx = int'(free_idx_r);
                                end

                                if (write_idx >= 0) begin
                                    active_q[write_idx]    <= 1'b1;
                                    stock_q[write_idx]     <= pending_stock_r;
                                    order_ref_q[write_idx] <= pending_order_ref_r;
                                    side_q[write_idx]      <= pending_side_r;
                                    shares_q[write_idx]    <= pending_shares_r;
                                    price_q[write_idx]     <= pending_price_r;
                                    applied = 1'b1;
                                end else begin
                                    overflow = 1'b1;
                                end
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        EVENT_EXECUTE,
                        EVENT_CANCEL: begin
                            if (found_valid_r && pending_shares_r != 32'd0) begin
                                if (pending_shares_r >= shares_q[found_idx_r]) begin
                                    active_q[found_idx_r] <= 1'b0;
                                end else begin
                                    shares_q[found_idx_r] <= shares_q[found_idx_r] - pending_shares_r;
                                end
                                applied = 1'b1;
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        EVENT_DELETE: begin
                            if (found_valid_r) begin
                                active_q[found_idx_r] <= 1'b0;
                                applied = 1'b1;
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        EVENT_REPLACE: begin
                            if (found_valid_r && pending_shares_r != 32'd0 &&
                                pending_price_r != 32'd0 && pending_new_order_ref_r != 64'd0) begin
                                order_ref_q[found_idx_r] <= pending_new_order_ref_r;
                                shares_q[found_idx_r] <= pending_shares_r;
                                price_q[found_idx_r]  <= pending_price_r;
                                applied = 1'b1;
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        default: begin
                            ignored = 1'b1;
                        end
                    endcase

                    if (applied) begin
                        applied_event_count_r <= applied_event_count_r + 1'b1;
                        scan_idx_r            <= '0;
                        scan_bid_price_r      <= '0;
                        scan_bid_shares_r     <= '0;
                        scan_ask_price_r      <= '0;
                        scan_ask_shares_r     <= '0;
                        state_r               <= STATE_SCAN;
                    end else begin
                        state_r <= STATE_IDLE;
                    end

                    if (ignored) begin
                        ignored_event_count_r <= ignored_event_count_r + 1'b1;
                    end

                    if (overflow) begin
                        table_overflow_count_r <= table_overflow_count_r + 1'b1;
                        ignored_event_count_r  <= ignored_event_count_r + 1'b1;
                    end
                end

                STATE_SCAN: begin
                    if (active_q[scan_idx_r] && stock_q[scan_idx_r] == TARGET_STOCK_LOCATE &&
                        side_q[scan_idx_r] == "B" && price_q[scan_idx_r] != 32'd0) begin
                        if (price_q[scan_idx_r] > scan_bid_price_r) begin
                            scan_bid_price_r  <= price_q[scan_idx_r];
                            scan_bid_shares_r <= shares_q[scan_idx_r];
                        end else if (price_q[scan_idx_r] == scan_bid_price_r) begin
                            scan_bid_shares_r <= scan_bid_shares_r + shares_q[scan_idx_r];
                        end
                    end

                    if (active_q[scan_idx_r] && stock_q[scan_idx_r] == TARGET_STOCK_LOCATE &&
                        side_q[scan_idx_r] == "S" && price_q[scan_idx_r] != 32'd0) begin
                        if (scan_ask_price_r == 32'd0 || price_q[scan_idx_r] < scan_ask_price_r) begin
                            scan_ask_price_r  <= price_q[scan_idx_r];
                            scan_ask_shares_r <= shares_q[scan_idx_r];
                        end else if (price_q[scan_idx_r] == scan_ask_price_r) begin
                            scan_ask_shares_r <= scan_ask_shares_r + shares_q[scan_idx_r];
                        end
                    end

                    if (scan_idx_r == PTR_WIDTH'(ORDER_TABLE_DEPTH - 1)) begin
                        state_r <= STATE_FINALIZE;
                    end else begin
                        scan_idx_r <= scan_idx_r + 1'b1;
                    end
                end

                STATE_FINALIZE: begin
                    if (!quote_valid_r || quote_ready) begin
                        state_r <= STATE_IDLE;
                        if (scan_bid_price_r  != best_bid_price_r  ||
                            scan_bid_shares_r != best_bid_shares_r ||
                            scan_ask_price_r  != best_ask_price_r  ||
                            scan_ask_shares_r != best_ask_shares_r) begin
                            best_bid_price_r     <= scan_bid_price_r;
                            best_bid_shares_r    <= scan_bid_shares_r;
                            best_ask_price_r     <= scan_ask_price_r;
                            best_ask_shares_r    <= scan_ask_shares_r;
                            quote_timestamp_r    <= pending_timestamp_r;
                            quote_valid_r        <= 1'b1;
                            quote_update_count_r <= quote_update_count_r + 1'b1;
                        end
                    end
                end

                default: begin
                    state_r <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
`default_nettype wire
