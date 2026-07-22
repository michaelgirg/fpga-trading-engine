`timescale 1ns / 100ps
`default_nettype none

module market_parser_100g_cmac_axis_decision_top_tb #(
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
    logic intent_valid;
    logic [15:0] intent_stock_locate;
    logic intent_side;
    logic [31:0] intent_price;
    logic [31:0] intent_quantity;
    logic [47:0] intent_timestamp;
    logic [95:0] position_by_symbol;
    logic [31:0] evaluated_quote_count;
    logic [31:0] generated_intent_count;
    logic [31:0] control_suppressed_count;
    logic [31:0] market_suppressed_count;
    logic [31:0] risk_suppressed_count;
    logic [31:0] book_quote_update_count;
    logic [31:0] cmac_axis_accepted_packet_count;
    logic feed_healthy;

    byte_t raw_0_mem[MULTI_SYMBOL_RAW_0_BYTES];
    byte_t raw_1_mem[MULTI_SYMBOL_RAW_1_BYTES];
    logic [15:0] observed_locate [0:1];
    logic observed_side [0:1];
    logic [31:0] observed_price [0:1];
    logic [31:0] observed_quantity [0:1];
    logic [47:0] observed_timestamp [0:1];
    int observed_intents;
    int failed;

    always #HALF_CLK_PERIOD clk <= ~clk;

    market_parser_100g_cmac_axis_decision_top #(
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
        .kill_switch(1'b0),
        .position_clear(1'b0),
        .max_spread_ticks(32'd100),
        .min_top_shares(32'd1),
        .imbalance_shift(3'd1),
        .order_quantity(32'd2),
        .max_abs_position(32'd10),
        .fill_valid(1'b0),
        .fill_stock_locate(16'd0),
        .fill_side(1'b0),
        .fill_quantity(32'd0),
        .intent_valid(intent_valid),
        .intent_ready(1'b1),
        .intent_stock_locate(intent_stock_locate),
        .intent_side(intent_side),
        .intent_price(intent_price),
        .intent_quantity(intent_quantity),
        .intent_timestamp(intent_timestamp),
        .position_by_symbol(position_by_symbol),
        .evaluated_quote_count(evaluated_quote_count),
        .generated_intent_count(generated_intent_count),
        .control_suppressed_count(control_suppressed_count),
        .market_suppressed_count(market_suppressed_count),
        .risk_suppressed_count(risk_suppressed_count),
        .applied_fill_count(),
        .untracked_fill_count(),
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
        .cmac_axis_accepted_packet_count(cmac_axis_accepted_packet_count),
        .cmac_axis_overflow_packet_count(),
        .cmac_axis_dropped_beat_count(),
        .cmac_axis_fifo_level(),
        .cmac_axis_fifo_high_watermark(),
        .cmac_axis_buffered_packet_count(),
        .book_accepted_event_count(),
        .book_applied_event_count(),
        .book_ignored_event_count(),
        .book_untracked_event_count(),
        .book_table_overflow_count(),
        .book_quote_update_count(book_quote_update_count),
        .feed_healthy(feed_healthy),
        .feed_rebuilding(),
        .feed_rebuild_ready(),
        .feed_gap_count(),
        .feed_suppressed_event_count(),
        .feed_idle_cycles(),
        .feed_timeout_count(),
        .feed_activation_reject_count(),
        .feed_session_change_count(),
        .feed_end_of_session_count()
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            observed_intents <= 0;
        end else if (intent_valid) begin
            if (observed_intents < 2) begin
                observed_locate[observed_intents] <= intent_stock_locate;
                observed_side[observed_intents] <= intent_side;
                observed_price[observed_intents] <= intent_price;
                observed_quantity[observed_intents] <= intent_quantity;
                observed_timestamp[observed_intents] <= intent_timestamp;
            end
            observed_intents <= observed_intents + 1;
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

    initial begin
        int wait_cycles;
        failed = 0;
        rst = 1'b1;
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata = '0;
        rx_axis_tkeep = '0;
        rx_axis_tlast = 1'b0;
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_0.hex"}, raw_0_mem);
        $readmemh({VECTOR_DIR, "/multi_symbol_raw_1.hex"}, raw_1_mem);

        repeat (5) @(posedge clk);
        rst = 1'b0;
        send_packet(MULTI_SYMBOL_RAW_0_BYTES, raw_0_mem);
        send_packet(MULTI_SYMBOL_RAW_1_BYTES, raw_1_mem);

        wait_cycles = 0;
        while ((book_quote_update_count < 32'd6 || observed_intents < 2) &&
               wait_cycles < 10000) begin
            @(posedge clk);
            wait_cycles++;
        end
        repeat (3) @(posedge clk);

        check(feed_healthy, "end-to-end replay keeps feed healthy");
        check(cmac_axis_accepted_packet_count == 32'd2,
              "CMAC bridge accepts both replay packets");
        check(book_quote_update_count == 32'd6,
              "book path emits all six expected quote updates");
        check(evaluated_quote_count == 32'd6,
              "decision engine evaluates every quote update");
        check(observed_intents == 2 && generated_intent_count == 32'd2,
              "decision engine emits exactly two actionable intents");
        check(market_suppressed_count == 32'd4 &&
              control_suppressed_count == 32'd0 &&
              risk_suppressed_count == 32'd0,
              "all nonactionable quotes have an exact suppression reason");
        check(observed_locate[0] == 16'h1111 && !observed_side[0] &&
              observed_price[0] == 32'd1050 &&
              observed_quantity[0] == 32'd2 &&
              observed_timestamp[0] == 48'd204,
              "first packet-to-intent result matches golden quote policy");
        check(observed_locate[1] == 16'h1111 && !observed_side[1] &&
              observed_price[1] == 32'd1050 &&
              observed_quantity[1] == 32'd2 &&
              observed_timestamp[1] == 48'd206,
              "second packet-to-intent result matches golden quote policy");
        check(position_by_symbol == '0,
              "intents do not change position before fill acknowledgment");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule

`default_nettype wire
