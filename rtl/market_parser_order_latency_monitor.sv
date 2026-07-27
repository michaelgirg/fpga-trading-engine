`default_nettype none
// Passive order-path telemetry. Matching, arithmetic, and extrema updates are
// separated by registers so no monitor output feeds a trading ready path.
module market_parser_order_latency_monitor #(
    parameter int TABLE_DEPTH = 16
) (
    input  wire logic        clk,
    input  wire logic        rst,
    input  wire logic        clear,

    input  wire logic        command_valid,
    input  wire logic        command_ready,
    input  wire logic        command_cancel,
    input  wire logic [63:0] command_id,
    input  wire logic [31:0] command_quantity,

    input  wire logic        tx_valid,
    input  wire logic        tx_ready,
    input  wire logic        tx_is_new,
    input  wire logic [63:0] tx_order_id,

    input  wire logic        response_valid,
    input  wire logic        response_ready,
    input  wire logic [1:0]  response_type,
    input  wire logic [63:0] response_order_id,
    input  wire logic [31:0] response_quantity,

    output logic [63:0]      cycle_count,
    output logic [15:0]      tracked_order_count,
    output logic [31:0]      activity_hash,

    output logic [31:0]      new_to_tx_last_cycles,
    output logic [31:0]      new_to_tx_min_cycles,
    output logic [31:0]      new_to_tx_max_cycles,
    output logic [31:0]      new_to_tx_sample_count,

    output logic [31:0]      new_to_ack_last_cycles,
    output logic [31:0]      new_to_ack_min_cycles,
    output logic [31:0]      new_to_ack_max_cycles,
    output logic [31:0]      new_to_ack_sample_count,

    output logic [31:0]      new_to_fill_last_cycles,
    output logic [31:0]      new_to_fill_min_cycles,
    output logic [31:0]      new_to_fill_max_cycles,
    output logic [31:0]      new_to_fill_sample_count,

    output logic [31:0]      duplicate_order_count,
    output logic [31:0]      duplicate_tx_count,
    output logic [31:0]      duplicate_response_count,
    output logic [31:0]      unmatched_tx_count,
    output logic [31:0]      unmatched_response_count,
    output logic [31:0]      table_full_count,
    output logic [31:0]      anomaly_count
);
    localparam logic [1:0] EVENT_ACK        = 2'd0;
    localparam logic [1:0] EVENT_REJECT     = 2'd1;
    localparam logic [1:0] EVENT_FILL       = 2'd2;
    localparam logic [1:0] EVENT_CANCEL_ACK = 2'd3;
    localparam int INDEX_WIDTH = (TABLE_DEPTH <= 1) ? 1 : $clog2(TABLE_DEPTH);

    logic [TABLE_DEPTH-1:0] slot_valid_r;
    logic [TABLE_DEPTH-1:0] slot_tx_seen_r;
    logic [TABLE_DEPTH-1:0] slot_ack_seen_r;
    logic [TABLE_DEPTH-1:0] slot_fill_seen_r;
    logic [63:0] slot_id_r [0:TABLE_DEPTH-1];
    logic [63:0] slot_start_cycle_r [0:TABLE_DEPTH-1];
    logic [31:0] slot_leaves_r [0:TABLE_DEPTH-1];

    // Stage 1: capture accepted handshakes and their original event cycle.
    logic command_event_valid_r;
    logic [63:0] command_event_id_r;
    logic [31:0] command_event_quantity_r;
    logic [63:0] command_event_cycle_r;
    logic tx_event_valid_r;
    logic [63:0] tx_event_id_r;
    logic [63:0] tx_event_cycle_r;
    logic response_event_valid_r;
    logic [1:0] response_event_type_r;
    logic [63:0] response_event_id_r;
    logic [31:0] response_event_quantity_r;
    logic [63:0] response_event_cycle_r;

    // Stage 2: table lookup and state update produce matched samples.
    logic tx_match_sample_valid_r;
    logic [63:0] tx_match_start_cycle_r;
    logic [63:0] tx_match_event_cycle_r;
    logic [63:0] tx_match_id_r;
    logic ack_match_sample_valid_r;
    logic [63:0] ack_match_start_cycle_r;
    logic [63:0] ack_match_event_cycle_r;
    logic [63:0] ack_match_id_r;
    logic fill_match_sample_valid_r;
    logic [63:0] fill_match_start_cycle_r;
    logic [63:0] fill_match_event_cycle_r;
    logic [63:0] fill_match_id_r;
    logic [31:0] fill_match_quantity_r;
    logic anomaly_hash_valid_r;
    logic [31:0] anomaly_hash_mix_r;

    // Stage 3: latency subtraction only.
    logic tx_latency_valid_r;
    logic [31:0] tx_latency_r;
    logic [31:0] tx_latency_id_r;
    logic ack_latency_valid_r;
    logic [31:0] ack_latency_r;
    logic [31:0] ack_latency_id_r;
    logic fill_latency_valid_r;
    logic [31:0] fill_latency_r;
    logic [31:0] fill_latency_id_r;
    logic [31:0] fill_latency_quantity_r;

    logic command_slot_free_i;
    logic command_match_found_i;
    logic tx_match_found_i;
    logic response_match_found_i;
    logic [INDEX_WIDTH-1:0] command_index_i;
    logic [INDEX_WIDTH-1:0] tx_index_i;
    logic [INDEX_WIDTH-1:0] response_index_i;
    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    function automatic logic [15:0] count_valid_slots(
        input logic [TABLE_DEPTH-1:0] valid_slots
    );
        logic [15:0] count;
        begin
            count = '0;
            for (int i = 0; i < TABLE_DEPTH; i++)
                count = count + valid_slots[i];
            count_valid_slots = count;
        end
    endfunction

    function automatic logic [31:0] latency_cycles(
        input logic [63:0] event_cycle,
        input logic [63:0] start_cycle
    );
        logic [63:0] delta;
        begin
            delta = event_cycle - start_cycle;
            latency_cycles = (|delta[63:32]) ? 32'hffff_ffff : delta[31:0];
        end
    endfunction

    always_comb begin
        command_index_i = command_event_id_r[INDEX_WIDTH-1:0];
        tx_index_i = tx_event_id_r[INDEX_WIDTH-1:0];
        response_index_i = response_event_id_r[INDEX_WIDTH-1:0];
        command_slot_free_i = !slot_valid_r[command_index_i];
        command_match_found_i = slot_valid_r[command_index_i] &&
                                slot_id_r[command_index_i] ==
                                    command_event_id_r;
        tx_match_found_i = slot_valid_r[tx_index_i] &&
                           slot_id_r[tx_index_i] == tx_event_id_r;
        response_match_found_i = slot_valid_r[response_index_i] &&
                                 slot_id_r[response_index_i] ==
                                     response_event_id_r;
    end

    always_ff @(posedge clk) begin : monitor_pipeline
        if (rst || clear) begin
            cycle_count <= '0;
            tracked_order_count <= '0;
            activity_hash <= '0;
            slot_valid_r <= '0;
            slot_tx_seen_r <= '0;
            slot_ack_seen_r <= '0;
            slot_fill_seen_r <= '0;
            command_event_valid_r <= 1'b0;
            tx_event_valid_r <= 1'b0;
            response_event_valid_r <= 1'b0;
            tx_match_sample_valid_r <= 1'b0;
            ack_match_sample_valid_r <= 1'b0;
            fill_match_sample_valid_r <= 1'b0;
            anomaly_hash_valid_r <= 1'b0;
            tx_latency_valid_r <= 1'b0;
            ack_latency_valid_r <= 1'b0;
            fill_latency_valid_r <= 1'b0;
            new_to_tx_last_cycles <= '0;
            new_to_tx_min_cycles <= 32'hffff_ffff;
            new_to_tx_max_cycles <= '0;
            new_to_tx_sample_count <= '0;
            new_to_ack_last_cycles <= '0;
            new_to_ack_min_cycles <= 32'hffff_ffff;
            new_to_ack_max_cycles <= '0;
            new_to_ack_sample_count <= '0;
            new_to_fill_last_cycles <= '0;
            new_to_fill_min_cycles <= 32'hffff_ffff;
            new_to_fill_max_cycles <= '0;
            new_to_fill_sample_count <= '0;
            duplicate_order_count <= '0;
            duplicate_tx_count <= '0;
            duplicate_response_count <= '0;
            unmatched_tx_count <= '0;
            unmatched_response_count <= '0;
            table_full_count <= '0;
            anomaly_count <= '0;
            command_event_id_r <= '0;
            command_event_quantity_r <= '0;
            command_event_cycle_r <= '0;
            tx_event_id_r <= '0;
            tx_event_cycle_r <= '0;
            response_event_type_r <= '0;
            response_event_id_r <= '0;
            response_event_quantity_r <= '0;
            response_event_cycle_r <= '0;
            tx_match_start_cycle_r <= '0;
            tx_match_event_cycle_r <= '0;
            tx_match_id_r <= '0;
            ack_match_start_cycle_r <= '0;
            ack_match_event_cycle_r <= '0;
            ack_match_id_r <= '0;
            fill_match_start_cycle_r <= '0;
            fill_match_event_cycle_r <= '0;
            fill_match_id_r <= '0;
            fill_match_quantity_r <= '0;
            anomaly_hash_mix_r <= '0;
            tx_latency_r <= '0;
            tx_latency_id_r <= '0;
            ack_latency_r <= '0;
            ack_latency_id_r <= '0;
            fill_latency_r <= '0;
            fill_latency_id_r <= '0;
            fill_latency_quantity_r <= '0;
            for (int i = 0; i < TABLE_DEPTH; i++) begin
                slot_id_r[i] <= '0;
                slot_start_cycle_r[i] <= '0;
                slot_leaves_r[i] <= '0;
            end
        end else begin
            cycle_count <= cycle_count + 1'b1;

            // Stage 1: registered, non-intrusive taps on accepted events.
            command_event_valid_r <= command_valid && command_ready &&
                                     !command_cancel;
            if (command_valid && command_ready && !command_cancel) begin
                command_event_id_r <= command_id;
                command_event_quantity_r <= command_quantity;
                command_event_cycle_r <= cycle_count;
            end
            tx_event_valid_r <= tx_valid && tx_ready && tx_is_new;
            if (tx_valid && tx_ready && tx_is_new) begin
                tx_event_id_r <= tx_order_id;
                tx_event_cycle_r <= cycle_count;
            end
            response_event_valid_r <= response_valid && response_ready;
            if (response_valid && response_ready) begin
                response_event_type_r <= response_type;
                response_event_id_r <= response_order_id;
                response_event_quantity_r <= response_quantity;
                response_event_cycle_r <= cycle_count;
            end

            // Stage 2 defaults. A valid sample is emitted only on a clean match.
            tx_match_sample_valid_r <= 1'b0;
            ack_match_sample_valid_r <= 1'b0;
            fill_match_sample_valid_r <= 1'b0;
            anomaly_hash_valid_r <= 1'b0;

            // This status value is deliberately one cycle behind the table.
            // It must not pull response matching and fill retirement into a
            // counter clock-enable path.
            tracked_order_count <= count_valid_slots(slot_valid_r);

            if (command_event_valid_r) begin
                if (command_match_found_i) begin
                    duplicate_order_count <=
                        increment_saturating(duplicate_order_count);
                    anomaly_count <= increment_saturating(anomaly_count);
                    anomaly_hash_valid_r <= 1'b1;
                    anomaly_hash_mix_r <= command_event_id_r[31:0] ^
                                          32'h4455_504f;
                end else if (command_slot_free_i) begin
                    slot_valid_r[command_index_i] <= 1'b1;
                    slot_tx_seen_r[command_index_i] <= 1'b0;
                    slot_ack_seen_r[command_index_i] <= 1'b0;
                    slot_fill_seen_r[command_index_i] <= 1'b0;
                    slot_id_r[command_index_i] <= command_event_id_r;
                    slot_start_cycle_r[command_index_i] <= command_event_cycle_r;
                    slot_leaves_r[command_index_i] <= command_event_quantity_r;
                end else begin
                    table_full_count <= increment_saturating(table_full_count);
                    anomaly_count <= increment_saturating(anomaly_count);
                    anomaly_hash_valid_r <= 1'b1;
                    anomaly_hash_mix_r <= command_event_id_r[31:0] ^
                                          32'h4655_4c4c;
                end
            end

            if (tx_event_valid_r) begin
                if (!tx_match_found_i) begin
                    unmatched_tx_count <= increment_saturating(unmatched_tx_count);
                    anomaly_count <= increment_saturating(anomaly_count);
                    anomaly_hash_valid_r <= 1'b1;
                    anomaly_hash_mix_r <= tx_event_id_r[31:0] ^ 32'h554e_4d54;
                end else if (slot_tx_seen_r[tx_index_i]) begin
                    duplicate_tx_count <= increment_saturating(duplicate_tx_count);
                    anomaly_count <= increment_saturating(anomaly_count);
                    anomaly_hash_valid_r <= 1'b1;
                    anomaly_hash_mix_r <= tx_event_id_r[31:0] ^ 32'h4455_5054;
                end else begin
                    slot_tx_seen_r[tx_index_i] <= 1'b1;
                    tx_match_sample_valid_r <= 1'b1;
                    tx_match_start_cycle_r <=
                        slot_start_cycle_r[tx_index_i];
                    tx_match_event_cycle_r <= tx_event_cycle_r;
                    tx_match_id_r <= tx_event_id_r;
                end
            end

            if (response_event_valid_r) begin
                if (!response_match_found_i) begin
                    unmatched_response_count <=
                        increment_saturating(unmatched_response_count);
                    anomaly_count <= increment_saturating(anomaly_count);
                    anomaly_hash_valid_r <= 1'b1;
                    anomaly_hash_mix_r <= response_event_id_r[31:0] ^
                                          32'h554e_4d52;
                end else begin
                    case (response_event_type_r)
                        EVENT_ACK: begin
                            if (slot_ack_seen_r[response_index_i]) begin
                                duplicate_response_count <= increment_saturating(
                                    duplicate_response_count);
                                anomaly_count <= increment_saturating(anomaly_count);
                                anomaly_hash_valid_r <= 1'b1;
                                anomaly_hash_mix_r <= response_event_id_r[31:0] ^
                                                      32'h4455_5041;
                            end else begin
                                slot_ack_seen_r[response_index_i] <= 1'b1;
                                ack_match_sample_valid_r <= 1'b1;
                                ack_match_start_cycle_r <=
                                    slot_start_cycle_r[response_index_i];
                                ack_match_event_cycle_r <= response_event_cycle_r;
                                ack_match_id_r <= response_event_id_r;
                            end
                        end
                        EVENT_REJECT, EVENT_CANCEL_ACK: begin
                            slot_valid_r[response_index_i] <= 1'b0;
                        end
                        EVENT_FILL: begin
                            if (!slot_fill_seen_r[response_index_i]) begin
                                slot_fill_seen_r[response_index_i] <= 1'b1;
                                fill_match_sample_valid_r <= 1'b1;
                                fill_match_start_cycle_r <=
                                    slot_start_cycle_r[response_index_i];
                                fill_match_event_cycle_r <= response_event_cycle_r;
                                fill_match_id_r <= response_event_id_r;
                                fill_match_quantity_r <= response_event_quantity_r;
                            end
                            if (response_event_quantity_r >=
                                slot_leaves_r[response_index_i]) begin
                                slot_valid_r[response_index_i] <= 1'b0;
                                slot_leaves_r[response_index_i] <= '0;
                            end else begin
                                slot_leaves_r[response_index_i] <=
                                    slot_leaves_r[response_index_i] -
                                    response_event_quantity_r;
                            end
                        end
                        default: begin
                            unmatched_response_count <= increment_saturating(
                                unmatched_response_count);
                            anomaly_count <= increment_saturating(anomaly_count);
                            anomaly_hash_valid_r <= 1'b1;
                            anomaly_hash_mix_r <= response_event_id_r[31:0] ^
                                                  32'h4241_4452;
                        end
                    endcase
                end
            end

            // Stage 3: arithmetic is isolated from matching and extrema logic.
            tx_latency_valid_r <= tx_match_sample_valid_r;
            if (tx_match_sample_valid_r) begin
                tx_latency_r <= latency_cycles(
                    tx_match_event_cycle_r, tx_match_start_cycle_r);
                tx_latency_id_r <= tx_match_id_r[31:0];
            end
            ack_latency_valid_r <= ack_match_sample_valid_r;
            if (ack_match_sample_valid_r) begin
                ack_latency_r <= latency_cycles(
                    ack_match_event_cycle_r, ack_match_start_cycle_r);
                ack_latency_id_r <= ack_match_id_r[31:0];
            end
            fill_latency_valid_r <= fill_match_sample_valid_r;
            if (fill_match_sample_valid_r) begin
                fill_latency_r <= latency_cycles(
                    fill_match_event_cycle_r, fill_match_start_cycle_r);
                fill_latency_id_r <= fill_match_id_r[31:0];
                fill_latency_quantity_r <= fill_match_quantity_r;
            end

            // Stage 4: only registered 32-bit samples feed statistics.
            if (tx_latency_valid_r) begin
                new_to_tx_last_cycles <= tx_latency_r;
                if (new_to_tx_sample_count == 0 ||
                    tx_latency_r < new_to_tx_min_cycles)
                    new_to_tx_min_cycles <= tx_latency_r;
                if (tx_latency_r > new_to_tx_max_cycles)
                    new_to_tx_max_cycles <= tx_latency_r;
                new_to_tx_sample_count <=
                    increment_saturating(new_to_tx_sample_count);
            end
            if (ack_latency_valid_r) begin
                new_to_ack_last_cycles <= ack_latency_r;
                if (new_to_ack_sample_count == 0 ||
                    ack_latency_r < new_to_ack_min_cycles)
                    new_to_ack_min_cycles <= ack_latency_r;
                if (ack_latency_r > new_to_ack_max_cycles)
                    new_to_ack_max_cycles <= ack_latency_r;
                new_to_ack_sample_count <=
                    increment_saturating(new_to_ack_sample_count);
            end
            if (fill_latency_valid_r) begin
                new_to_fill_last_cycles <= fill_latency_r;
                if (new_to_fill_sample_count == 0 ||
                    fill_latency_r < new_to_fill_min_cycles)
                    new_to_fill_min_cycles <= fill_latency_r;
                if (fill_latency_r > new_to_fill_max_cycles)
                    new_to_fill_max_cycles <= fill_latency_r;
                new_to_fill_sample_count <=
                    increment_saturating(new_to_fill_sample_count);
            end

            // The compact harness consumes one registered digest, not a wide
            // combinational reduction of every telemetry register.
            if (fill_latency_valid_r) begin
                activity_hash <= {activity_hash[30:0], activity_hash[31]} ^
                                 fill_latency_id_r ^ fill_latency_r ^
                                 fill_latency_quantity_r;
            end else if (ack_latency_valid_r) begin
                activity_hash <= {activity_hash[30:0], activity_hash[31]} ^
                                 ack_latency_id_r ^ ack_latency_r;
            end else if (tx_latency_valid_r) begin
                activity_hash <= {activity_hash[30:0], activity_hash[31]} ^
                                 tx_latency_id_r ^ tx_latency_r;
            end else if (anomaly_hash_valid_r) begin
                activity_hash <= {activity_hash[30:0], activity_hash[31]} ^
                                 anomaly_hash_mix_r;
            end
        end
    end
endmodule
`default_nettype wire
