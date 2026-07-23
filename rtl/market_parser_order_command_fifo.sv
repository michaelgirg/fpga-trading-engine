`default_nettype none
// Two-entry command FIFO with registered storage and occupancy-only input
// ready. This deliberately cuts downstream ready logic from the lifecycle path.
module market_parser_order_command_fifo (
    input  wire logic        clk,
    input  wire logic        rst,

    input  wire logic        input_valid,
    output logic             input_ready,
    input  wire logic        input_cancel,
    input  wire logic [63:0] input_id,
    input  wire logic [15:0] input_stock_locate,
    input  wire logic        input_side,
    input  wire logic [31:0] input_price,
    input  wire logic [31:0] input_quantity,

    output logic             output_valid,
    input  wire logic        output_ready,
    output logic             output_cancel,
    output logic [63:0]      output_id,
    output logic [15:0]      output_stock_locate,
    output logic             output_side,
    output logic [31:0]      output_price,
    output logic [31:0]      output_quantity,

    output logic [1:0]       occupancy
);
    logic cancel_r [0:1];
    logic [63:0] id_r [0:1];
    logic [15:0] stock_locate_r [0:1];
    logic side_r [0:1];
    logic [31:0] price_r [0:1];
    logic [31:0] quantity_r [0:1];
    logic write_pointer_r;
    logic read_pointer_r;
    logic push_i;
    logic pop_i;

    assign input_ready = occupancy != 2'd2;
    assign output_valid = occupancy != 2'd0;
    assign push_i = input_valid && input_ready;
    assign pop_i = output_valid && output_ready;

    assign output_cancel = cancel_r[read_pointer_r];
    assign output_id = id_r[read_pointer_r];
    assign output_stock_locate = stock_locate_r[read_pointer_r];
    assign output_side = side_r[read_pointer_r];
    assign output_price = price_r[read_pointer_r];
    assign output_quantity = quantity_r[read_pointer_r];

    always_ff @(posedge clk) begin
        if (rst) begin
            write_pointer_r <= 1'b0;
            read_pointer_r <= 1'b0;
            occupancy <= 2'd0;
            for (int i = 0; i < 2; i++) begin
                cancel_r[i] <= 1'b0;
                id_r[i] <= '0;
                stock_locate_r[i] <= '0;
                side_r[i] <= 1'b0;
                price_r[i] <= '0;
                quantity_r[i] <= '0;
            end
        end else begin
            if (push_i) begin
                cancel_r[write_pointer_r] <= input_cancel;
                id_r[write_pointer_r] <= input_id;
                stock_locate_r[write_pointer_r] <= input_stock_locate;
                side_r[write_pointer_r] <= input_side;
                price_r[write_pointer_r] <= input_price;
                quantity_r[write_pointer_r] <= input_quantity;
                write_pointer_r <= ~write_pointer_r;
            end
            if (pop_i) read_pointer_r <= ~read_pointer_r;

            case ({push_i, pop_i})
                2'b10: occupancy <= occupancy + 1'b1;
                2'b01: occupancy <= occupancy - 1'b1;
                default: occupancy <= occupancy;
            endcase
        end
    end
endmodule
`default_nettype wire
