`default_nettype none
// =============================================================================
// Module: market_parser_event_fifo
// =============================================================================
// Small ready/valid FIFO for normalized parser events.
//
// This block is the production-style decoupling point between parsing and a
// downstream strategy, DMA, register, or software path. It keeps backpressure
// local until the FIFO fills.
module market_parser_event_fifo #(
    parameter int EVENT_WIDTH = 256,
    parameter int KEEP_WIDTH  = 32,
    parameter int FIFO_DEPTH  = 16
) (
    input  wire logic                     clk,
    input  wire logic                     rst,

    input  wire logic                     event_in_valid,
    output logic                          event_in_ready,
    input  wire logic [EVENT_WIDTH-1:0]   event_in_data,
    input  wire logic [ KEEP_WIDTH-1:0]   event_in_keep,
    input  wire logic                     event_in_last,

    output logic                          event_out_valid,
    input  wire logic                     event_out_ready,
    output logic [EVENT_WIDTH-1:0]        event_out_data,
    output logic [ KEEP_WIDTH-1:0]        event_out_keep,
    output logic                          event_out_last,

    output logic [15:0]                   fifo_level,
    output logic [31:0]                   write_count,
    output logic [31:0]                   read_count,
    output logic [31:0]                   backpressure_count
);
    localparam int PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    initial begin
        if (FIFO_DEPTH < 2) begin
            $fatal(1, "FIFO_DEPTH must be at least 2");
        end
    end

    logic [EVENT_WIDTH-1:0] data_q[FIFO_DEPTH];
    logic [ KEEP_WIDTH-1:0] keep_q[FIFO_DEPTH];
    logic                   last_q[FIFO_DEPTH];

    logic [PTR_WIDTH-1:0] wr_ptr_r;
    logic [PTR_WIDTH-1:0] rd_ptr_r;
    logic [PTR_WIDTH:0]   count_r;
    logic [31:0]          write_count_r;
    logic [31:0]          read_count_r;
    logic [31:0]          backpressure_count_r;

    logic push_i;
    logic pop_i;

    assign event_in_ready  = (int'(count_r) < FIFO_DEPTH);
    assign event_out_valid = (count_r != '0);
    assign event_out_data  = data_q[rd_ptr_r];
    assign event_out_keep  = keep_q[rd_ptr_r];
    assign event_out_last  = last_q[rd_ptr_r];

    assign push_i = event_in_valid && event_in_ready;
    assign pop_i  = event_out_valid && event_out_ready;

    assign fifo_level          = 16'(count_r);
    assign write_count         = write_count_r;
    assign read_count          = read_count_r;
    assign backpressure_count  = backpressure_count_r;

    function automatic logic [PTR_WIDTH-1:0] inc_ptr(input logic [PTR_WIDTH-1:0] ptr);
        if (ptr == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
            inc_ptr = '0;
        end else begin
            inc_ptr = ptr + 1'b1;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr_r             <= '0;
            rd_ptr_r             <= '0;
            count_r              <= '0;
            write_count_r        <= '0;
            read_count_r         <= '0;
            backpressure_count_r <= '0;
        end else begin
            if (event_in_valid && !event_in_ready) begin
                backpressure_count_r <= backpressure_count_r + 1'b1;
            end

            if (push_i) begin
                data_q[wr_ptr_r] <= event_in_data;
                keep_q[wr_ptr_r] <= event_in_keep;
                last_q[wr_ptr_r] <= event_in_last;
                wr_ptr_r         <= inc_ptr(wr_ptr_r);
                write_count_r    <= write_count_r + 1'b1;
            end

            if (pop_i) begin
                rd_ptr_r     <= inc_ptr(rd_ptr_r);
                read_count_r <= read_count_r + 1'b1;
            end

            case ({push_i, pop_i})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: begin
                end
            endcase
        end
    end

endmodule
`default_nettype wire
