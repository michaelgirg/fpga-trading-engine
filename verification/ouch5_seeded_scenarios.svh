    logic [31:0] rng_state;
    byte unsigned market_bytes[138];
    int scenario_coverage[4][4][2];
    bit tx_stalled = 0;
    logic [576:0] held_tx;
    int replay_cycle = 0;
    int first_market_cycle, last_market_cycle, wire_cycle;
    bit market_seen = 0;
    bit wire_seen = 0;
    int first_to_wire_min = 32'h7fffffff;
    int first_to_wire_max = 0;
    int last_to_wire_min = 32'h7fffffff;
    int last_to_wire_max = 0;
    int latency_histogram[4];

    // A private PRNG keeps replay stable when unrelated simulator tests change.
    function automatic int unsigned choose(input int unsigned limit);
        rng_state = rng_state ^ (rng_state << 13);
        rng_state = rng_state ^ (rng_state >> 17);
        rng_state = rng_state ^ (rng_state << 5);
        return rng_state % limit;
    endfunction

    function automatic logic [15:0] locate_for(input int symbol);
        case (symbol)
            0: return 16'h1234;
            1: return 16'h2222;
            2: return 16'h3333;
            3: return 16'h4444;
        endcase
        return '0;
    endfunction

    function automatic logic [63:0] symbol_for(input int symbol);
        case (symbol)
            0: return 64'h5445535420202020;
            1: return 64'h4242424220202020;
            2: return 64'h4343434320202020;
            3: return 64'h4444444420202020;
        endcase
        return '0;
    endfunction

    function automatic logic [31:0] read_wire_u32(
        input logic [511:0] frame, input int offset
    );
        return {frame[offset*8 +: 8], frame[(offset+1)*8 +: 8],
                frame[(offset+2)*8 +: 8], frame[(offset+3)*8 +: 8]};
    endfunction

    always @(posedge clk) begin
        if (rst || STRESS_ROUNDS == 0) begin
            tx_stalled = 0;
            replay_cycle = 0;
            market_seen = 0;
            wire_seen = 0;
        end else begin
            replay_cycle++;
            if (rx_axis_tvalid) begin
                if (!market_seen) first_market_cycle = replay_cycle;
                market_seen = 1;
                if (rx_axis_tlast) last_market_cycle = replay_cycle;
            end
            if (soup_tx_valid && soup_tx_ready && soup_tx_data[31:24] == "O") begin
                wire_cycle = replay_cycle;
                wire_seen = 1;
            end
            if (tx_stalled && (soup_tx_valid !== 1'b1 ||
                {soup_tx_last, soup_tx_keep, soup_tx_data} !== held_tx))
                check(0, "Soup output changed while stalled");
            tx_stalled = soup_tx_valid && !soup_tx_ready;
            held_tx = {soup_tx_last, soup_tx_keep, soup_tx_data};
        end
    end

    task automatic put_market_be(input int offset, input logic [63:0] value,
                                 input int bytes_count);
        for (int i = 0; i < bytes_count; i++)
            market_bytes[offset+i] = value[(bytes_count-1-i)*8 +: 8];
    endtask

    task automatic send_two_sided_market(input int symbol, input bit sell,
                                         input int bid_price, input int ask_price);
        logic [511:0] beat;
        int checksum;
        foreach (market_bytes[i]) market_bytes[i] = 0;
        for (int i = 0; i < 12; i++) market_bytes[i] = 8'(i + 1);
        put_market_be(12, 16'h0800, 2);
        market_bytes[14] = 8'h45;
        put_market_be(16, 124, 2);
        market_bytes[22] = 64;
        market_bytes[23] = 17;
        put_market_be(26, 32'h0a000001, 4);
        put_market_be(30, 32'hef000001, 4);
        checksum = 0;
        for (int i = 14; i < 34; i += 2)
            checksum += (int'(market_bytes[i]) << 8) | int'(market_bytes[i+1]);
        while (checksum >> 16) checksum = (checksum & 65535) + (checksum >> 16);
        put_market_be(24, 16'(~checksum), 2);
        put_market_be(34, 10000, 2);
        put_market_be(36, 5000, 2);
        put_market_be(38, 104, 2);
        for (int i = 42; i < 52; i++) market_bytes[i] = "S";
        put_market_be(52, 1, 8);
        put_market_be(60, 2, 2);
        for (int msg_idx = 0; msg_idx < 2; msg_idx++) begin
            int base;
            int shares;
            base = 62 + msg_idx * 38;
            shares = ((msg_idx == 0) != sell) ? 200 + int'(choose(100)) :
                                               10 + int'(choose(10));
            put_market_be(base, 36, 2);
            market_bytes[base+2] = "A";
            put_market_be(base+3, {48'd0, locate_for(symbol)}, 2);
            put_market_be(base+5, 64'(msg_idx+1), 2);
            put_market_be(base+7, 64'(msg_idx+1), 6);
            put_market_be(base+13, 64'(msg_idx+1), 8);
            market_bytes[base+21] = msg_idx == 0 ? "B" : "S";
            put_market_be(base+22, 64'(shares), 4);
            put_market_be(base+26, symbol_for(symbol), 8);
            put_market_be(base+34, 64'(msg_idx == 0 ? bid_price : ask_price), 4);
        end
        for (int offset = 0; offset < 138; offset += 64) begin
            repeat (choose(6)) @(negedge clk);
            @(negedge clk);
            beat = '0;
            for (int lane = 0; lane < 64 && offset+lane < 138; lane++)
                beat[lane*8 +: 8] = market_bytes[offset+lane];
            rx_axis_tvalid = 1;
            rx_axis_tdata = beat;
            rx_axis_tkeep = mask(offset == 128 ? 10 : 64);
            rx_axis_tlast = offset == 128;
            @(negedge clk);
            rx_axis_tvalid = 0;
            rx_axis_tlast = 0;
        end
    endtask

    task automatic accept_wire_packet(input byte expected_type,
                                      output logic [511:0] frame);
        int cycles;
        cycles = 0;
        while (!soup_tx_valid && cycles < 2000) begin
            @(negedge clk);
            cycles++;
        end
        if (!soup_tx_valid) $fatal(1, "Seed %0d timed out waiting for OUCH %c", SEED, expected_type);
        frame = soup_tx_data;
        check(frame[23:16] == "U" && frame[31:24] == expected_type && soup_tx_last,
              "outbound Soup packet has expected OUCH type and boundary");
        check(soup_tx_keep == mask(expected_type == "O" ? 50 : 14),
              "outbound Soup packet has exact byte count");
        repeat (1 + choose(20)) @(negedge clk);
        soup_tx_ready = 1;
        @(negedge clk);
        soup_tx_ready = 0;
    endtask

    task automatic venue_response(input byte response_type, input logic [31:0] id,
                                   input int quantity, input int price);
        logic [511:0] payload;
        int payload_bytes;
        repeat (1 + choose(25)) @(negedge clk);
        payload = '0;
        payload[7:0] = response_type;
        put_u32_be(payload, 9, id);
        case (response_type)
            "A": begin payload_bytes = 64; payload[47*8 +: 8] = "L"; end
            "J": payload_bytes = 31;
            "E": begin
                payload_bytes = 36;
                put_u32_be(payload, 13, 32'(quantity));
                put_u32_be(payload, 21, 32'(price));
            end
            "C": begin payload_bytes = 20; put_u32_be(payload, 13, 32'(quantity)); end
            default: $fatal(1, "Unsupported test response");
        endcase
        send_ouch_response(payload, payload_bytes);
        repeat (12) @(negedge clk);
    endtask

    task automatic run_seeded_scenarios;
        logic [511:0] frame;
        logic [31:0] order_id;
        logic [63:0] expected_symbol;
        int symbol, mode, quantity, bid_price, ask_price, expected_position;
        int fill_events, filled_quantity, expected_responses;
        int first_latency, last_latency, latency_bucket;
        bit sell;
        rng_state = SEED == 0 ? 32'd1 : 32'(SEED);
        for (int round_idx = 0; round_idx < STRESS_ROUNDS; round_idx++) begin
            mode = round_idx % 4;
            symbol = (round_idx / 4) % 4;
            sell = ((round_idx / 16) % 2) != 0;
            quantity = 2 + int'(choose(7));
            bid_price = 10000 + int'(choose(1000));
            ask_price = bid_price + 1 + int'(choose(10));
            @(negedge clk);
            rst = 1;
            kill_switch = 0;
            rx_axis_tvalid = 0;
            soup_tx_ready = 0;
            soup_rx_valid = 0;
            order_quantity_cfg = 32'(quantity);
            repeat (5) @(negedge clk);
            rst = 0;
            send_login_accepted();
            send_two_sided_market(symbol, sell, bid_price, ask_price);
            accept_wire_packet("O", frame);
            check(market_seen && wire_seen && wire_cycle > last_market_cycle,
                  "packet and order handshakes are captured by passive timestamps");
            first_latency = wire_cycle - first_market_cycle;
            last_latency = wire_cycle - last_market_cycle;
            if (first_latency < first_to_wire_min) first_to_wire_min = first_latency;
            if (first_latency > first_to_wire_max) first_to_wire_max = first_latency;
            if (last_latency < last_to_wire_min) last_to_wire_min = last_latency;
            if (last_latency > last_to_wire_max) last_to_wire_max = last_latency;
            latency_bucket = first_latency < 32 ? 0 : first_latency < 64 ? 1 :
                             first_latency < 128 ? 2 : 3;
            latency_histogram[latency_bucket]++;
            order_id = read_wire_u32(frame, 4);
            expected_symbol = symbol_for(symbol);
            check(order_id == 1 && read_wire_u32(frame, 9) == quantity &&
                  frame[8*8 +: 8] == (sell ? "S" : "B") &&
                  read_wire_u32(frame, 25) == (sell ? bid_price : ask_price),
                  "golden imbalance policy matches encoded ID, side, size and price");
            for (int i = 0; i < 8; i++)
                check(frame[(13+i)*8 +: 8] == expected_symbol[(7-i)*8 +: 8],
                      "OUCH symbol mapping matches selected book");
            fill_events = 0;
            filled_quantity = 0;
            expected_responses = 1;
            if (mode == 0) begin
                venue_response("J", order_id, 0, 0);
            end else begin
                venue_response("A", order_id, 0, 0);
                check(live_order_mask[symbol] && acknowledged_order_count == 1,
                      "venue acknowledgment makes the selected order live");
                if (mode == 1) begin
                    venue_response("E", order_id, quantity, sell ? bid_price : ask_price);
                    fill_events = 1;
                    filled_quantity = quantity;
                    expected_responses = 2;
                end else begin
                    venue_response("E", order_id, 1, sell ? bid_price : ask_price);
                    check(working_order_mask[symbol] && outstanding_order_count == 1,
                          "partial fill preserves remaining working exposure");
                    if (mode == 2) begin
                        venue_response("E", order_id, quantity-1, sell ? bid_price : ask_price);
                        fill_events = 2;
                        filled_quantity = quantity;
                    end else begin
                        @(negedge clk);
                        kill_switch = 1;
                        accept_wire_packet("X", frame);
                        check(read_wire_u32(frame, 4) == order_id,
                              "kill-switch cancel retains the working order ID");
                        venue_response("C", order_id, quantity-1, 0);
                        fill_events = 1;
                        filled_quantity = 1;
                    end
                    expected_responses = 3;
                end
            end
            repeat (20) @(negedge clk);
            expected_position = sell ? -filled_quantity : filled_quantity;
            for (int idx = 0; idx < 4; idx++)
                check($signed(position_by_symbol[idx*32 +: 32]) ==
                      (idx == symbol ? expected_position : 0),
                      "golden signed position and symbol isolation agree");
            check(outstanding_order_count == 0 && working_order_mask == 0 && live_order_mask == 0,
                  "terminal venue response retires every lifecycle slot");
            check(lifecycle_fill_count == fill_events && applied_fill_count == fill_events &&
                  acknowledged_order_count == (mode == 0 ? 0 : 1) &&
                  rejected_order_count == (mode == 0 ? 1 : 0) &&
                  cancel_ack_count == (mode == 3 ? 1 : 0),
                  "venue events reconcile exactly once across lifecycle and position");
            check(passed_new_count == 1 && ouch_encoded_new_count == 1 &&
                  ouch_encoded_cancel_count == (mode == 3 ? 1 : 0) &&
                  ouch_decoded_event_count == expected_responses &&
                  soup_sequenced_packet_count == expected_responses,
                  "gateway byte traffic and event counters conserve the order");
            check(new_to_tx_sample_count == 1 &&
                  new_to_ack_sample_count == (mode == 0 ? 0 : 1) &&
                  new_to_fill_sample_count == (mode == 0 ? 0 : 1) &&
                  latency_tracked_order_count == 0 && latency_anomaly_count == 0,
                  "telemetry tracks first responses and retires without anomalies");
            check(protocol_error_count == 0 && gateway_protocol_error_count == 0 &&
                  cmac_axis_overflow_packet_count == 0 && cmac_axis_dropped_beat_count == 0,
                  "seeded packet-to-order replay remains lossless and protocol-clean");
            scenario_coverage[mode][symbol][int'(sell)]++;
            $display("SCENARIO seed=%0d round=%0d mode=%0d symbol=%0d sell=%0d qty=%0d position=%0d first_to_wire=%0d last_to_wire=%0d",
                     SEED, round_idx, mode, symbol, sell, quantity, expected_position,
                     first_latency, last_latency);
        end
        check(latency_histogram[0] + latency_histogram[1] + latency_histogram[2] +
              latency_histogram[3] == STRESS_ROUNDS,
              "packet latency histogram conserves every generated order");
        $display("PACKET LATENCY seed=%0d samples=%0d first_beat_to_wire_cycles=%0d..%0d last_beat_to_wire_cycles=%0d..%0d",
                 SEED, STRESS_ROUNDS, first_to_wire_min, first_to_wire_max,
                 last_to_wire_min, last_to_wire_max);
        $display("LATENCY HISTOGRAM seed=%0d first_beat_cycles_0_31=%0d cycles_32_63=%0d cycles_64_127=%0d cycles_128_plus=%0d",
                 SEED, latency_histogram[0], latency_histogram[1],
                 latency_histogram[2], latency_histogram[3]);
        if (STRESS_ROUNDS >= 32) begin
            for (int m = 0; m < 4; m++)
                for (int s = 0; s < 4; s++)
                    for (int d = 0; d < 2; d++)
                        check(scenario_coverage[m][s][d] > 0,
                              "all response-mode, symbol and direction combinations covered");
        end
        $display("SEEDED REPLAY COMPLETE: seed=%0d scenarios=%0d", SEED, STRESS_ROUNDS);
    endtask
