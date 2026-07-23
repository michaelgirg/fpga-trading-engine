`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_cmac_axis_order_top_tb #(
    parameter realtime CLK_PERIOD = 3.102ns,
    parameter string VECTOR_DIR = "verification/vectors"
);
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;
    localparam logic [47:0] SYMBOL_LOCATES = {16'h3333, 16'h2222, 16'h1111};
    localparam int RX_BYTES_PER_BEAT = 64;
`include "verification/vectors/multi_symbol_meta.svh"

    typedef logic [7:0] byte_t;

    logic clk = 1'b0;
    logic rst;
    logic rx_axis_tvalid;
    logic [511:0] rx_axis_tdata;
    logic [63:0] rx_axis_tkeep;
    logic rx_axis_tlast;
    logic kill_switch;
    logic order_cmd_valid;
    logic order_cmd_cancel;
    logic [63:0] order_cmd_id;
    logic [15:0] order_cmd_stock_locate;
    logic order_cmd_side;
    logic [31:0] order_cmd_price;
    logic [31:0] order_cmd_quantity;
    logic [47:0] order_cmd_timestamp;
    logic exchange_event_valid;
    logic [1:0] exchange_event_type;
    logic [63:0] exchange_event_order_id;
    logic [31:0] exchange_event_price;
    logic [31:0] exchange_event_quantity;
    logic [95:0] position_by_symbol;
    logic [2:0] working_order_mask;
    logic [2:0] live_order_mask;
    logic [15:0] outstanding_order_count;
    logic [31:0] accepted_intent_count;
    logic [31:0] busy_intent_count;
    logic [31:0] new_command_count;
    logic [31:0] acknowledged_order_count;
    logic [31:0] cancel_command_count;
    logic [31:0] cancel_ack_count;
    logic [31:0] lifecycle_fill_count;
    logic [31:0] protocol_error_count;
    logic [31:0] evaluated_quote_count;
    logic [31:0] generated_intent_count;
    logic [31:0] applied_fill_count;
    logic [31:0] cmac_axis_accepted_packet_count;
    logic [31:0] book_quote_update_count;
    logic feed_healthy;

    byte_t raw_0_mem[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t raw_1_mem[MULTI_SYMBOL_RAW_1_BYTES];
    logic [63:0] observed_new_id [0:1];
    logic [15:0] observed_new_locate [0:1];
    logic observed_new_side [0:1];
    logic [31:0] observed_new_price [0:1];
    logic [31:0] observed_new_quantity [0:1];
    logic [47:0] observed_new_timestamp [0:1];
    logic [63:0] observed_cancel_id;
    int observed_new_commands;
    int observed_cancel_commands;
    int failed;

    always #HALF_CLK_PERIOD clk <= ~clk;

    market_parser_100g_cmac_axis_order_top #(
        .FEED_UDP_PORT(16'd5000),
        .NUM_SYMBOLS(3),
        .SYMBOL_LOCATES(SYMBOL_LOCATES),
        .CMAC_RX_FIFO_DEPTH(64),
        .ORDER_TABLE_DEPTH(8)
    ) dut (
        .clk(clk),
        .rst(rst),
        .feed_recover(1'b0),
        .feed_activate(1'b0),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(1'b0),
        .strategy_enable(1'b1),
        .kill_switch(kill_switch),
        .position_clear(1'b0),
        .max_spread_ticks(32'd100),
        .min_top_shares(32'd1),
        .imbalance_shift(3'd1),
        .order_quantity(32'd2),
        .max_abs_position(32'd10),
        .order_cmd_valid(order_cmd_valid),
        .order_cmd_ready(1'b1),
        .order_cmd_cancel(order_cmd_cancel),
        .order_cmd_id(order_cmd_id),
        .order_cmd_stock_locate(order_cmd_stock_locate),
        .order_cmd_side(order_cmd_side),
        .order_cmd_price(order_cmd_price),
        .order_cmd_quantity(order_cmd_quantity),
        .order_cmd_timestamp(order_cmd_timestamp),
        .exchange_event_valid(exchange_event_valid),
        .exchange_event_ready(),
        .exchange_event_type(exchange_event_type),
        .exchange_event_order_id(exchange_event_order_id),
        .exchange_event_price(exchange_event_price),
        .exchange_event_quantity(exchange_event_quantity),
        .s_axi_awaddr(12'd0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata(32'd0),
        .s_axi_wstrb(4'd0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),
        .s_axi_bresp(),
        .s_axi_bvalid(),
        .s_axi_bready(1'b1),
        .s_axi_araddr(12'd0),
        .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rdata(),
        .s_axi_rresp(),
        .s_axi_rvalid(),
        .s_axi_rready(1'b1),
        .position_by_symbol(position_by_symbol),
        .working_order_mask(working_order_mask),
        .live_order_mask(live_order_mask),
        .leaves_quantity_by_symbol(),
        .outstanding_order_count(outstanding_order_count),
        .accepted_intent_count(accepted_intent_count),
        .busy_intent_count(busy_intent_count),
        .untracked_intent_count(),
        .new_command_count(new_command_count),
        .acknowledged_order_count(acknowledged_order_count),
        .rejected_order_count(),
        .cancel_command_count(cancel_command_count),
        .cancel_ack_count(cancel_ack_count),
        .lifecycle_fill_count(lifecycle_fill_count),
        .canceled_before_send_count(),
        .protocol_error_count(protocol_error_count),
        .evaluated_quote_count(evaluated_quote_count),
        .generated_intent_count(generated_intent_count),
        .control_suppressed_count(),
        .market_suppressed_count(),
        .risk_suppressed_count(),
        .applied_fill_count(applied_fill_count),
        .untracked_fill_count(),
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(),
        .cmac_axis_dropped_beat_count(),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy),
        .feed_rebuilding(),
        .feed_gap_count(),
        .feed_timeout_count()
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            observed_new_commands <= 0;
            observed_cancel_commands <= 0;
            observed_cancel_id <= '0;
        end else if (order_cmd_valid) begin
            if (order_cmd_cancel) begin
                observed_cancel_id <= order_cmd_id;
                observed_cancel_commands <= observed_cancel_commands + 1;
            end else begin
                if (observed_new_commands < 2) begin
                    observed_new_id[observed_new_commands] <= order_cmd_id;
                    observed_new_locate[observed_new_commands] <=
                        order_cmd_stock_locate;
                    observed_new_side[observed_new_commands] <= order_cmd_side;
                    observed_new_price[observed_new_commands] <= order_cmd_price;
                    observed_new_quantity[observed_new_commands] <=
                        order_cmd_quantity;
                    observed_new_timestamp[observed_new_commands] <=
                        order_cmd_timestamp;
                end
                observed_new_commands <= observed_new_commands + 1;
            end
        end
    end

    task automatic check(input bit condition, input string message);
        if (condition) begin
            $display("PASS: %s", message);
        end else begin
            $display("FAIL: %s", message);
            failed++;
        end
    endtask

    task automatic send_packet(input int packet_bytes, input byte_t packet_mem[]);
        int offset;
        int beat_bytes;
        logic [511:0] beat_data;
        logic [63:0] beat_keep;

        offset = 0;
        @(negedge clk);
        while (offset < packet_bytes) begin
            beat_bytes = ((packet_bytes - offset) >= RX_BYTES_PER_BEAT) ?
                         RX_BYTES_PER_BEAT : packet_bytes - offset;
            beat_data = '0;
            beat_keep = '0;
            for (int lane = 0; lane < beat_bytes; lane++) begin
                beat_data[lane*8 +: 8] = packet_mem[offset + lane];
                beat_keep[lane] = 1'b1;
            end
            rx_axis_tvalid = 1'b1;
            rx_axis_tdata = beat_data;
            rx_axis_tkeep = beat_keep;
            rx_axis_tlast = (offset + beat_bytes >= packet_bytes);
            @(negedge clk);
            offset += beat_bytes;
        end
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata = '0;
        rx_axis_tkeep = '0;
        rx_axis_tlast = 1'b0;
    endtask

    task automatic send_event(
        input logic [1:0] event_type,
        input logic [63:0] order_id,
        input logic [31:0] price,
        input logic [31:0] quantity
    );
        @(negedge clk);
        exchange_event_valid = 1'b1;
        exchange_event_type = event_type;
        exchange_event_order_id = order_id;
        exchange_event_price = price;
        exchange_event_quantity = quantity;
        @(negedge clk);
        exchange_event_valid = 1'b0;
    endtask

    task automatic wait_for_count(
        input bit cancel_count,
        input int expected,
        input string message
    );
        int wait_cycles;
        wait_cycles = 0;
        while (((cancel_count ? observed_cancel_commands : observed_new_commands)
                < expected) && wait_cycles < 10000) begin
            @(posedge clk);
            wait_cycles++;
        end
        check((cancel_count ? observed_cancel_commands : observed_new_commands)
              >= expected, message);
    endtask

    initial begin
        int decision_wait_cycles;

        failed = 0;
        rst = 1'b1;
        kill_switch = 1'b0;
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata = '0;
        rx_axis_tkeep = '0;
        rx_axis_tlast = 1'b0;
        exchange_event_valid = 1'b0;
        exchange_event_type = '0;
        exchange_event_order_id = '0;
        exchange_event_price = '0;
        exchange_event_quantity = '0;
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_0.hex"}, raw_0_mem);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_1.hex"}, raw_1_mem);

        repeat (5) @(posedge clk);
        rst = 1'b0;

        send_packet(MULTI_SYMBOL_RAW_0_BYTES, raw_0_mem);
        send_packet(MULTI_SYMBOL_RAW_1_BYTES, raw_1_mem);
        wait_for_count(1'b0, 1, "golden replay produces a transmitted new order");
        check(observed_new_id[0] == 64'd1 &&
              observed_new_locate[0] == 16'h1111 &&
              !observed_new_side[0] && observed_new_price[0] == 32'd1050 &&
              observed_new_quantity[0] == 32'd2 &&
              observed_new_timestamp[0] == 48'd204,
              "packet-to-order command matches the first golden decision");

        decision_wait_cycles = 0;
        while ((evaluated_quote_count < 32'd6 ||
                generated_intent_count < 32'd2 ||
                busy_intent_count < 32'd1) &&
               decision_wait_cycles < 10000) begin
            @(posedge clk);
            decision_wait_cycles++;
        end
        check(decision_wait_cycles < 10000,
              "decision and busy-intent accounting completes without timeout");

        send_event(2'd0, observed_new_id[0], 32'd0, 32'd0);
        send_event(2'd2, observed_new_id[0], 32'd1050, 32'd1);
        repeat (3) @(posedge clk);
        check(position_by_symbol[31:0] == 32'd1 &&
              applied_fill_count == 32'd1 && lifecycle_fill_count == 32'd1,
              "partial exchange fills close the loop into signed position");
        check(outstanding_order_count == 16'd1,
              "partially filled order retains its remaining quantity");

        @(negedge clk);
        kill_switch = 1'b1;
        wait_for_count(1'b1, 1, "kill switch emits a cancel for the live order");
        check(observed_cancel_id == observed_new_id[0],
              "cancel command preserves the live client order ID");
        send_event(2'd3, observed_cancel_id, 32'd0, 32'd0);
        repeat (3) @(posedge clk);

        check(feed_healthy && cmac_axis_accepted_packet_count == 32'd2,
              "closed-loop replay preserves feed health and packet accounting");
        check(book_quote_update_count == 32'd6 &&
              evaluated_quote_count == 32'd6 && generated_intent_count == 32'd2,
              "all quote updates reach deterministic decision accounting");
        check(accepted_intent_count == 32'd1 && busy_intent_count == 32'd1 &&
              new_command_count == 32'd1 && observed_new_commands == 1,
              "one-working-order policy classifies the second intent as busy");
        check(acknowledged_order_count == 32'd1 &&
              cancel_command_count == 32'd1 && cancel_ack_count == 32'd1,
              "acknowledgment and cancel lifecycle counters are exact");
        check(outstanding_order_count == 16'd0 &&
              working_order_mask == '0 && live_order_mask == '0,
              "no working order remains after fill and cancel completion");
        check(protocol_error_count == 32'd0,
              "well-formed exchange replay produces no protocol errors");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
