`default_nettype none
// =============================================================================
// Module: market_parser_multi_symbol_top_of_book
// =============================================================================
// Bounded multi-symbol book built from independent iterative single-symbol
// engines. Events are routed by stock locate and quote updates share one
// ordered output. Only one event is in flight across the bank at a time.
module market_parser_multi_symbol_top_of_book #(
    parameter int NUM_SYMBOLS = 1,
    parameter int ORDER_TABLE_DEPTH = 16,
    parameter logic [NUM_SYMBOLS*16-1:0] SYMBOL_LOCATES = 16'h0001
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
    output logic [31:0]       untracked_event_count,
    output logic [31:0]       table_overflow_count,
    output logic [31:0]       quote_update_count
);
    logic [NUM_SYMBOLS-1:0] book_event_valid;
    logic [NUM_SYMBOLS-1:0] book_event_ready;
    logic [NUM_SYMBOLS-1:0] book_quote_valid;
    logic [NUM_SYMBOLS-1:0] book_quote_ready;

    logic [15:0] book_quote_stock_locate[NUM_SYMBOLS];
    logic [31:0] book_quote_bid_price   [NUM_SYMBOLS];
    logic [31:0] book_quote_bid_shares  [NUM_SYMBOLS];
    logic [31:0] book_quote_ask_price   [NUM_SYMBOLS];
    logic [31:0] book_quote_ask_shares  [NUM_SYMBOLS];
    logic [47:0] book_quote_timestamp   [NUM_SYMBOLS];

    logic [31:0] book_accepted_event_count[NUM_SYMBOLS];
    logic [31:0] book_applied_event_count [NUM_SYMBOLS];
    logic [31:0] book_ignored_event_count [NUM_SYMBOLS];
    logic [31:0] book_table_overflow_count[NUM_SYMBOLS];
    logic [31:0] book_quote_update_count  [NUM_SYMBOLS];

    logic [NUM_SYMBOLS-1:0] selected_book_i;
    logic                    event_tracked_i;
    logic                    selected_book_ready_i;
    logic                    quote_slot_available_i;
    logic [31:0]             untracked_event_count_r;

    function automatic logic [15:0] configured_locate(input int idx);
        configured_locate = SYMBOL_LOCATES[idx*16 +: 16];
    endfunction

    initial begin
        if (NUM_SYMBOLS < 1) begin
            $fatal(1, "NUM_SYMBOLS must be at least 1");
        end
        for (int lhs = 0; lhs < NUM_SYMBOLS; lhs++) begin
            for (int rhs = lhs + 1; rhs < NUM_SYMBOLS; rhs++) begin
                if (configured_locate(lhs) == configured_locate(rhs)) begin
                    $fatal(1, "SYMBOL_LOCATES entries must be unique");
                end
            end
        end
    end

    always_comb begin
        event_tracked_i = 1'b0;
        selected_book_i = '0;
        for (int idx = 0; idx < NUM_SYMBOLS; idx++) begin
            if (!event_tracked_i && event_data[31:16] == configured_locate(idx)) begin
                event_tracked_i    = 1'b1;
                selected_book_i[idx] = 1'b1;
            end
        end
    end

    assign quote_slot_available_i = !(|book_quote_valid) || quote_ready;

    always_comb begin
        selected_book_ready_i = 1'b1;
        book_event_valid      = '0;
        for (int idx = 0; idx < NUM_SYMBOLS; idx++) begin
            if (selected_book_i[idx]) begin
                selected_book_ready_i = book_event_ready[idx];
                book_event_valid[idx] = event_valid && quote_slot_available_i;
            end
        end
    end

    assign event_ready = quote_slot_available_i &&
                         (!event_tracked_i || selected_book_ready_i);

    always_comb begin
        bit selected_quote;

        selected_quote     = 1'b0;
        book_quote_ready   = '0;
        quote_valid        = 1'b0;
        quote_stock_locate = '0;
        quote_bid_price    = '0;
        quote_bid_shares   = '0;
        quote_ask_price    = '0;
        quote_ask_shares   = '0;
        quote_timestamp    = '0;

        for (int idx = 0; idx < NUM_SYMBOLS; idx++) begin
            if (!selected_quote && book_quote_valid[idx]) begin
                selected_quote          = 1'b1;
                quote_valid             = 1'b1;
                quote_stock_locate      = book_quote_stock_locate[idx];
                quote_bid_price         = book_quote_bid_price[idx];
                quote_bid_shares        = book_quote_bid_shares[idx];
                quote_ask_price         = book_quote_ask_price[idx];
                quote_ask_shares        = book_quote_ask_shares[idx];
                quote_timestamp         = book_quote_timestamp[idx];
                book_quote_ready[idx]   = quote_ready;
            end
        end
    end

    always_comb begin
        accepted_event_count = untracked_event_count_r;
        applied_event_count  = '0;
        ignored_event_count  = untracked_event_count_r;
        table_overflow_count = '0;
        quote_update_count   = '0;

        for (int idx = 0; idx < NUM_SYMBOLS; idx++) begin
            accepted_event_count = accepted_event_count + book_accepted_event_count[idx];
            applied_event_count  = applied_event_count + book_applied_event_count[idx];
            ignored_event_count  = ignored_event_count + book_ignored_event_count[idx];
            table_overflow_count = table_overflow_count + book_table_overflow_count[idx];
            quote_update_count   = quote_update_count + book_quote_update_count[idx];
        end
    end

    assign untracked_event_count = untracked_event_count_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            untracked_event_count_r <= '0;
        end else if (event_valid && event_ready && !event_tracked_i) begin
            untracked_event_count_r <= untracked_event_count_r + 1'b1;
        end
    end

    generate
        for (genvar book_idx = 0; book_idx < NUM_SYMBOLS; book_idx++) begin : g_book
            localparam logic [15:0] BOOK_STOCK_LOCATE = SYMBOL_LOCATES[book_idx*16 +: 16];

            market_parser_top_of_book #(
                .ORDER_TABLE_DEPTH  (ORDER_TABLE_DEPTH),
                .TARGET_STOCK_LOCATE(BOOK_STOCK_LOCATE)
            ) book_i (
                .clk                 (clk),
                .rst                 (rst),
                .event_valid         (book_event_valid[book_idx]),
                .event_ready         (book_event_ready[book_idx]),
                .event_data          (event_data),
                .event_new_order_ref (event_new_order_ref),
                .event_keep          (event_keep),
                .event_last          (event_last),
                .quote_valid         (book_quote_valid[book_idx]),
                .quote_ready         (book_quote_ready[book_idx]),
                .quote_stock_locate  (book_quote_stock_locate[book_idx]),
                .quote_bid_price     (book_quote_bid_price[book_idx]),
                .quote_bid_shares    (book_quote_bid_shares[book_idx]),
                .quote_ask_price     (book_quote_ask_price[book_idx]),
                .quote_ask_shares    (book_quote_ask_shares[book_idx]),
                .quote_timestamp     (book_quote_timestamp[book_idx]),
                .accepted_event_count(book_accepted_event_count[book_idx]),
                .applied_event_count (book_applied_event_count[book_idx]),
                .ignored_event_count (book_ignored_event_count[book_idx]),
                .table_overflow_count(book_table_overflow_count[book_idx]),
                .quote_update_count  (book_quote_update_count[book_idx])
            );
        end
    endgenerate

endmodule
`default_nettype wire
