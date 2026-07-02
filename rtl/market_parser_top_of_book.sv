`default_nettype none
import market_parser_pkg::*;
// =============================================================================
// Module: market_parser_top_of_book
// =============================================================================
// Small single-symbol top-of-book engine for normalized ITCH events.
//
// This is intentionally scoped as the next HFT pipeline block after parsing:
// keep a compact order table, apply add/execute/cancel/delete/replace events,
// and emit a quote update whenever the best bid/ask price or displayed size
// changes.
module market_parser_top_of_book #(
    parameter int          ORDER_TABLE_DEPTH  = 16,
    parameter logic [15:0] TARGET_STOCK_LOCATE = 16'h0001
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         event_valid,
    output logic              event_ready,
    input  wire logic [255:0] event_data,
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

    logic                   recompute_pending_r;
    logic [47:0]            pending_timestamp_r;

    logic [31:0]            accepted_event_count_r;
    logic [31:0]            applied_event_count_r;
    logic [31:0]            ignored_event_count_r;
    logic [31:0]            table_overflow_count_r;
    logic [31:0]            quote_update_count_r;

    logic [31:0]            best_bid_price_i;
    logic [31:0]            best_bid_shares_i;
    logic [31:0]            best_ask_price_i;
    logic [31:0]            best_ask_shares_i;

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

    assign event_ready = !recompute_pending_r && (!quote_valid_r || quote_ready);
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

    always_comb begin
        best_bid_price_i  = '0;
        best_bid_shares_i = '0;
        best_ask_price_i  = '0;
        best_ask_shares_i = '0;

        for (int idx = 0; idx < ORDER_TABLE_DEPTH; idx++) begin
            if (active_q[idx] && stock_q[idx] == TARGET_STOCK_LOCATE &&
                side_q[idx] == "B" && price_q[idx] != 32'd0) begin
                if (price_q[idx] > best_bid_price_i) begin
                    best_bid_price_i = price_q[idx];
                end
            end

            if (active_q[idx] && stock_q[idx] == TARGET_STOCK_LOCATE &&
                side_q[idx] == "S" && price_q[idx] != 32'd0) begin
                if (best_ask_price_i == 32'd0 || price_q[idx] < best_ask_price_i) begin
                    best_ask_price_i = price_q[idx];
                end
            end
        end

        for (int idx = 0; idx < ORDER_TABLE_DEPTH; idx++) begin
            if (active_q[idx] && stock_q[idx] == TARGET_STOCK_LOCATE &&
                side_q[idx] == "B" && price_q[idx] == best_bid_price_i) begin
                best_bid_shares_i = best_bid_shares_i + shares_q[idx];
            end

            if (active_q[idx] && stock_q[idx] == TARGET_STOCK_LOCATE &&
                side_q[idx] == "S" && price_q[idx] == best_ask_price_i) begin
                best_ask_shares_i = best_ask_shares_i + shares_q[idx];
            end
        end
    end

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

            quote_valid_r          <= 1'b0;
            best_bid_price_r       <= '0;
            best_bid_shares_r      <= '0;
            best_ask_price_r       <= '0;
            best_ask_shares_r      <= '0;
            quote_timestamp_r      <= '0;
            recompute_pending_r    <= 1'b0;
            pending_timestamp_r    <= '0;
            accepted_event_count_r <= '0;
            applied_event_count_r  <= '0;
            ignored_event_count_r  <= '0;
            table_overflow_count_r <= '0;
            quote_update_count_r   <= '0;
        end else begin
            if (quote_valid_r && quote_ready) begin
                quote_valid_r <= 1'b0;
            end

            if (recompute_pending_r && (!quote_valid_r || quote_ready)) begin
                recompute_pending_r <= 1'b0;
                if (best_bid_price_i  != best_bid_price_r  ||
                    best_bid_shares_i != best_bid_shares_r ||
                    best_ask_price_i  != best_ask_price_r  ||
                    best_ask_shares_i != best_ask_shares_r) begin
                    best_bid_price_r     <= best_bid_price_i;
                    best_bid_shares_r    <= best_bid_shares_i;
                    best_ask_price_r     <= best_ask_price_i;
                    best_ask_shares_r    <= best_ask_shares_i;
                    quote_timestamp_r    <= pending_timestamp_r;
                    quote_valid_r        <= 1'b1;
                    quote_update_count_r <= quote_update_count_r + 1'b1;
                end
            end

            if (event_fire_i) begin
                int found_idx;
                int free_idx;
                bit applied;
                bit ignored;
                bit overflow;

                found_idx = -1;
                free_idx  = -1;
                applied   = 1'b0;
                ignored   = 1'b0;
                overflow  = 1'b0;

                accepted_event_count_r <= accepted_event_count_r + 1'b1;

                for (int idx = 0; idx < ORDER_TABLE_DEPTH; idx++) begin
                    if (active_q[idx] && order_ref_q[idx] == event_order_ref_i &&
                        stock_q[idx] == TARGET_STOCK_LOCATE && found_idx < 0) begin
                        found_idx = idx;
                    end
                    if (!active_q[idx] && free_idx < 0) begin
                        free_idx = idx;
                    end
                end

                if (!target_match_i || !event_clean_i) begin
                    ignored = 1'b1;
                end else begin
                    unique case (event_kind_i)
                        EVENT_ADD: begin
                            if ((event_side_i == "B" || event_side_i == "S") &&
                                event_shares_i != 32'd0 && event_price_i != 32'd0) begin
                                int write_idx;
                                write_idx = (found_idx >= 0) ? found_idx : free_idx;
                                if (write_idx >= 0) begin
                                    active_q[write_idx]    <= 1'b1;
                                    stock_q[write_idx]     <= event_stock_i;
                                    order_ref_q[write_idx] <= event_order_ref_i;
                                    side_q[write_idx]      <= event_side_i;
                                    shares_q[write_idx]    <= event_shares_i;
                                    price_q[write_idx]     <= event_price_i;
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
                            if (found_idx >= 0 && event_shares_i != 32'd0) begin
                                if (event_shares_i >= shares_q[found_idx]) begin
                                    active_q[found_idx] <= 1'b0;
                                end else begin
                                    shares_q[found_idx] <= shares_q[found_idx] - event_shares_i;
                                end
                                applied = 1'b1;
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        EVENT_DELETE: begin
                            if (found_idx >= 0) begin
                                active_q[found_idx] <= 1'b0;
                                applied = 1'b1;
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        EVENT_REPLACE: begin
                            if (found_idx >= 0 && event_shares_i != 32'd0 &&
                                event_price_i != 32'd0) begin
                                shares_q[found_idx] <= event_shares_i;
                                price_q[found_idx]  <= event_price_i;
                                applied = 1'b1;
                            end else begin
                                ignored = 1'b1;
                            end
                        end

                        default: begin
                            ignored = 1'b1;
                        end
                    endcase
                end

                if (applied) begin
                    applied_event_count_r <= applied_event_count_r + 1'b1;
                    recompute_pending_r   <= 1'b1;
                    pending_timestamp_r   <= event_timestamp_i;
                end
                if (ignored) begin
                    ignored_event_count_r <= ignored_event_count_r + 1'b1;
                end
                if (overflow) begin
                    table_overflow_count_r <= table_overflow_count_r + 1'b1;
                    ignored_event_count_r  <= ignored_event_count_r + 1'b1;
                end
            end
        end
    end

endmodule
`default_nettype wire
