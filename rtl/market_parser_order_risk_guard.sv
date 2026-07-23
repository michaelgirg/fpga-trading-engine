`default_nettype none
// Independent final egress checks with an elastic registered input stage.
// Cancels always pass; rejected new orders return a local reject so upstream
// lifecycle state cannot remain pending.
module market_parser_order_risk_guard #(
    parameter int RATE_WINDOW_CYCLES = 1024
) (
    input  wire logic         clk,
    input  wire logic         rst,
    input  wire logic         risk_enable,
    input  wire logic         session_active,
    input  wire logic         kill_switch,
    input  wire logic [31:0]  max_order_quantity,
    input  wire logic [31:0]  min_order_price,
    input  wire logic [31:0]  max_order_price,
    input  wire logic [15:0]  max_outstanding_orders,
    input  wire logic [15:0]  max_new_orders_per_window,
    input  wire logic [15:0]  outstanding_order_count,

    input  wire logic         command_valid,
    output logic              command_ready,
    input  wire logic         command_cancel,
    input  wire logic [63:0]  command_id,
    input  wire logic [15:0]  command_stock_locate,
    input  wire logic         command_side,
    input  wire logic [31:0]  command_price,
    input  wire logic [31:0]  command_quantity,
    input  wire logic [47:0]  command_timestamp,

    output logic              guarded_command_valid,
    input  wire logic         guarded_command_ready,
    output logic              guarded_command_cancel,
    output logic [63:0]       guarded_command_id,
    output logic [15:0]       guarded_command_stock_locate,
    output logic              guarded_command_side,
    output logic [31:0]       guarded_command_price,
    output logic [31:0]       guarded_command_quantity,
    output logic [47:0]       guarded_command_timestamp,

    output logic              local_reject_valid,
    input  wire logic         local_reject_ready,
    output logic [63:0]       local_reject_order_id,
    output logic [ 2:0]       local_reject_reason,

    output logic [31:0]       passed_new_count,
    output logic [31:0]       passed_cancel_count,
    output logic [31:0]       control_reject_count,
    output logic [31:0]       quantity_reject_count,
    output logic [31:0]       price_reject_count,
    output logic [31:0]       outstanding_reject_count,
    output logic [31:0]       rate_reject_count
);
    localparam int RATE_COUNTER_WIDTH =
        (RATE_WINDOW_CYCLES <= 1) ? 1 : $clog2(RATE_WINDOW_CYCLES);

    localparam logic [2:0] REJECT_NONE        = 3'd0;
    localparam logic [2:0] REJECT_CONTROL     = 3'd1;
    localparam logic [2:0] REJECT_QUANTITY    = 3'd2;
    localparam logic [2:0] REJECT_PRICE       = 3'd3;
    localparam logic [2:0] REJECT_OUTSTANDING = 3'd4;
    localparam logic [2:0] REJECT_RATE        = 3'd5;

    logic guarded_command_valid_r;
    logic guarded_command_cancel_r;
    logic [63:0] guarded_command_id_r;
    logic [15:0] guarded_command_stock_locate_r;
    logic guarded_command_side_r;
    logic [31:0] guarded_command_price_r;
    logic [31:0] guarded_command_quantity_r;
    logic [47:0] guarded_command_timestamp_r;

    logic local_reject_valid_r;
    logic [63:0] local_reject_order_id_r;
    logic [2:0] local_reject_reason_r;

    logic input_valid_r;
    logic input_cancel_r;
    logic [63:0] input_id_r;
    logic [15:0] input_stock_locate_r;
    logic input_side_r;
    logic [31:0] input_price_r;
    logic [31:0] input_quantity_r;
    logic [47:0] input_timestamp_r;
    logic [15:0] input_outstanding_count_r;

    logic [RATE_COUNTER_WIDTH-1:0] rate_window_cycle_r;
    logic [15:0] new_orders_in_window_r;
    logic [2:0] reject_reason_i;
    logic input_allowed_i;
    logic command_fire_i;
    logic input_fire_i;
    logic guarded_slot_available_i;
    logic reject_slot_available_i;
    logic input_slot_available_i;

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    always_comb begin
        reject_reason_i = REJECT_NONE;
        if (!input_cancel_r) begin
            if (!risk_enable || !session_active || kill_switch) begin
                reject_reason_i = REJECT_CONTROL;
            end else if (input_quantity_r == 32'd0 ||
                         max_order_quantity == 32'd0 ||
                         input_quantity_r > max_order_quantity) begin
                reject_reason_i = REJECT_QUANTITY;
            end else if (input_price_r < min_order_price ||
                         max_order_price == 32'd0 ||
                         input_price_r > max_order_price) begin
                reject_reason_i = REJECT_PRICE;
            end else if (max_outstanding_orders == 16'd0 ||
                         input_outstanding_count_r >
                         max_outstanding_orders) begin
                reject_reason_i = REJECT_OUTSTANDING;
            end else if (max_new_orders_per_window == 16'd0 ||
                         new_orders_in_window_r >=
                         max_new_orders_per_window) begin
                reject_reason_i = REJECT_RATE;
            end
        end
    end

    assign input_allowed_i = input_cancel_r ||
                             reject_reason_i == REJECT_NONE;
    assign guarded_slot_available_i = !guarded_command_valid_r ||
                                      guarded_command_ready;
    assign reject_slot_available_i = !local_reject_valid_r ||
                                     local_reject_ready;
    assign input_slot_available_i = input_allowed_i ?
                                    guarded_slot_available_i :
                                    reject_slot_available_i;
    assign command_ready = !input_valid_r || input_slot_available_i;
    assign command_fire_i = command_valid && command_ready;
    assign input_fire_i = input_valid_r && input_slot_available_i;

    assign guarded_command_valid        = guarded_command_valid_r;
    assign guarded_command_cancel       = guarded_command_cancel_r;
    assign guarded_command_id           = guarded_command_id_r;
    assign guarded_command_stock_locate = guarded_command_stock_locate_r;
    assign guarded_command_side         = guarded_command_side_r;
    assign guarded_command_price        = guarded_command_price_r;
    assign guarded_command_quantity     = guarded_command_quantity_r;
    assign guarded_command_timestamp    = guarded_command_timestamp_r;
    assign local_reject_valid           = local_reject_valid_r;
    assign local_reject_order_id        = local_reject_order_id_r;
    assign local_reject_reason          = local_reject_reason_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            guarded_command_valid_r        <= 1'b0;
            guarded_command_cancel_r       <= 1'b0;
            guarded_command_id_r           <= '0;
            guarded_command_stock_locate_r <= '0;
            guarded_command_side_r         <= 1'b0;
            guarded_command_price_r        <= '0;
            guarded_command_quantity_r     <= '0;
            guarded_command_timestamp_r    <= '0;
            local_reject_valid_r            <= 1'b0;
            local_reject_order_id_r         <= '0;
            local_reject_reason_r           <= REJECT_NONE;
            input_valid_r                   <= 1'b0;
            input_cancel_r                  <= 1'b0;
            input_id_r                      <= '0;
            input_stock_locate_r            <= '0;
            input_side_r                    <= 1'b0;
            input_price_r                   <= '0;
            input_quantity_r                <= '0;
            input_timestamp_r               <= '0;
            input_outstanding_count_r       <= '0;
            rate_window_cycle_r             <= '0;
            new_orders_in_window_r          <= '0;
            passed_new_count                <= '0;
            passed_cancel_count             <= '0;
            control_reject_count            <= '0;
            quantity_reject_count           <= '0;
            price_reject_count              <= '0;
            outstanding_reject_count        <= '0;
            rate_reject_count               <= '0;
        end else begin
            if (guarded_command_valid_r && guarded_command_ready) begin
                guarded_command_valid_r <= 1'b0;
            end
            if (local_reject_valid_r && local_reject_ready) begin
                local_reject_valid_r <= 1'b0;
            end

            if (RATE_WINDOW_CYCLES <= 1 ||
                rate_window_cycle_r == RATE_WINDOW_CYCLES-1) begin
                rate_window_cycle_r    <= '0;
                new_orders_in_window_r <= '0;
            end else begin
                rate_window_cycle_r <= rate_window_cycle_r + 1'b1;
            end

            if (input_fire_i) begin
                if (input_allowed_i) begin
                    guarded_command_valid_r        <= 1'b1;
                    guarded_command_cancel_r       <= input_cancel_r;
                    guarded_command_id_r           <= input_id_r;
                    guarded_command_stock_locate_r <= input_stock_locate_r;
                    guarded_command_side_r         <= input_side_r;
                    guarded_command_price_r        <= input_price_r;
                    guarded_command_quantity_r     <= input_quantity_r;
                    guarded_command_timestamp_r    <= input_timestamp_r;
                    if (input_cancel_r) begin
                        passed_cancel_count <=
                            increment_saturating(passed_cancel_count);
                    end else begin
                        if (RATE_WINDOW_CYCLES <= 1 ||
                            rate_window_cycle_r ==
                            RATE_WINDOW_CYCLES-1) begin
                            new_orders_in_window_r <= 16'd1;
                        end else begin
                            new_orders_in_window_r <=
                                new_orders_in_window_r + 1'b1;
                        end
                        passed_new_count <=
                            increment_saturating(passed_new_count);
                    end
                end else begin
                    local_reject_valid_r    <= 1'b1;
                    local_reject_order_id_r <= input_id_r;
                    local_reject_reason_r   <= reject_reason_i;
                    case (reject_reason_i)
                        REJECT_CONTROL: control_reject_count <=
                            increment_saturating(control_reject_count);
                        REJECT_QUANTITY: quantity_reject_count <=
                            increment_saturating(quantity_reject_count);
                        REJECT_PRICE: price_reject_count <=
                            increment_saturating(price_reject_count);
                        REJECT_OUTSTANDING: outstanding_reject_count <=
                            increment_saturating(outstanding_reject_count);
                        default: rate_reject_count <=
                            increment_saturating(rate_reject_count);
                    endcase
                end
            end

            // This elastic input stage breaks lifecycle state and outstanding
            // accounting away from the risk-decision-to-ready path. It can
            // retire one staged command and accept the next in the same clock.
            if (command_fire_i) begin
                input_valid_r             <= 1'b1;
                input_cancel_r            <= command_cancel;
                input_id_r                <= command_id;
                input_stock_locate_r      <= command_stock_locate;
                input_side_r              <= command_side;
                input_price_r             <= command_price;
                input_quantity_r          <= command_quantity;
                input_timestamp_r         <= command_timestamp;
                input_outstanding_count_r <= outstanding_order_count;
            end else if (input_fire_i) begin
                input_valid_r <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
