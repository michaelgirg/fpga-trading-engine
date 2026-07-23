`default_nettype none
// SoupBinTCP 3.0 logical-packet boundary above a reliable TCP transport.
// Byte zero occupies data[7:0]. OUCH payloads are limited to 64 bytes.
module market_parser_soupbintcp_client #(
    parameter int WATCHDOG_CYCLES = 1024,
    parameter int CLIENT_HEARTBEAT_CYCLES = 0
) (
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire logic         transport_connected,
    input  wire logic         login_valid,
    output logic              login_ready,
    input  wire logic [47:0]  login_username,
    input  wire logic [79:0]  login_password,
    input  wire logic [79:0]  requested_session,
    input  wire logic [63:0]  requested_sequence,
    input  wire logic         logout_valid,
    output logic              logout_ready,

    input  wire logic         ouch_tx_valid,
    output logic              ouch_tx_ready,
    input  wire logic [511:0] ouch_tx_data,
    input  wire logic [63:0]  ouch_tx_keep,
    input  wire logic         ouch_tx_last,

    output logic              soup_tx_valid,
    input  wire logic         soup_tx_ready,
    output logic [511:0]      soup_tx_data,
    output logic [63:0]       soup_tx_keep,
    output logic              soup_tx_last,

    input  wire logic         soup_rx_valid,
    output logic              soup_rx_ready,
    input  wire logic [511:0] soup_rx_data,
    input  wire logic [63:0]  soup_rx_keep,
    input  wire logic         soup_rx_last,

    output logic              ouch_rx_valid,
    input  wire logic         ouch_rx_ready,
    output logic [511:0]      ouch_rx_data,
    output logic [63:0]       ouch_rx_keep,
    output logic              ouch_rx_last,

    output logic              session_active,
    output logic              session_fault,
    output logic              login_in_progress,
    output logic [79:0]       current_session,
    output logic [63:0]       next_sequence,
    output logic [31:0]       login_request_count,
    output logic [31:0]       login_accepted_count,
    output logic [31:0]       login_rejected_count,
    output logic [31:0]       logout_request_count,
    output logic [31:0]       end_session_count,
    output logic [31:0]       heartbeat_count,
    output logic [31:0]       client_heartbeat_count,
    output logic [31:0]       sequenced_packet_count,
    output logic [31:0]       inactive_data_count,
    output logic [31:0]       malformed_packet_count,
    output logic [31:0]       unsupported_packet_count,
    output logic [31:0]       watchdog_timeout_count,
    output logic [31:0]       tx_unsequenced_count,
    output logic [31:0]       tx_malformed_count,
    output logic [31:0]       sequence_parse_error_count
);
    localparam logic [1:0] RX_IDLE   = 2'd0;
    localparam logic [1:0] RX_SECOND = 2'd1;
    localparam logic [1:0] RX_DRAIN  = 2'd2;

    logic [1:0] rx_state_r;
    logic tx_valid_r;
    logic [511:0] tx_data_r;
    logic [63:0] tx_keep_r;
    logic ouch_valid_r;
    logic [511:0] ouch_data_r;
    logic [63:0] ouch_keep_r;
    logic [511:0] partial_ouch_data_r;
    logic [6:0] partial_payload_bytes_r;
    logic [6:0] partial_second_bytes_r;
    logic [31:0] watchdog_r;
    logic [31:0] tx_idle_r;

    logic login_build_active_r;
    logic login_format_active_r;
    logic login_packet_pending_r;
    logic [5:0] login_shift_count_r;
    logic [63:0] login_binary_r;
    logic [79:0] login_bcd_r;
    logic [4:0] login_format_index_r;
    logic login_format_seen_nonzero_r;
    logic [511:0] login_data_r;

    logic sequence_parse_active_r;
    logic [4:0] sequence_parse_index_r;
    logic [159:0] sequence_ascii_r;
    logic [63:0] sequence_parse_value_r;
    logic sequence_parse_seen_digit_r;
    logic sequence_parse_bad_r;

    logic [6:0] tx_payload_bytes_i;
    logic tx_keep_valid_i;
    logic tx_slot_available_i;
    logic tx_fire_i;
    logic logout_fire_i;
    logic [6:0] rx_beat_bytes_i;
    logic rx_keep_valid_i;
    logic [15:0] rx_packet_length_i;
    logic [16:0] rx_total_bytes_i;
    logic [15:0] rx_payload_bytes_i;
    logic [7:0] rx_packet_type_i;
    logic ouch_slot_available_i;
    logic rx_fire_i;

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    function automatic logic [63:0] increment_sequence(
        input logic [63:0] value
    );
        increment_sequence = (value == 64'hffff_ffff_ffff_ffff) ?
                             value : value + 1'b1;
    endfunction

    function automatic logic [6:0] count_keep(input logic [63:0] keep);
        logic [6:0] count;
        count = 7'd0;
        for (int i = 0; i < 64; i++) count = count + keep[i];
        count_keep = count;
    endfunction

    function automatic logic keep_is_contiguous(input logic [63:0] keep);
        logic saw_zero;
        logic valid;
        saw_zero = 1'b0;
        valid = 1'b1;
        for (int i = 0; i < 64; i++) begin
            if (!keep[i]) saw_zero = 1'b1;
            else if (saw_zero) valid = 1'b0;
        end
        keep_is_contiguous = valid;
    endfunction

    function automatic logic [63:0] keep_mask(input logic [6:0] count);
        if (count == 0) keep_mask = 64'd0;
        else if (count >= 64) keep_mask = 64'hffff_ffff_ffff_ffff;
        else keep_mask = (64'h1 << count) - 1'b1;
    endfunction

    assign tx_payload_bytes_i = count_keep(ouch_tx_keep);
    assign tx_keep_valid_i = keep_is_contiguous(ouch_tx_keep) &&
                             tx_payload_bytes_i != 0 &&
                             tx_payload_bytes_i <= 61 &&
                             ouch_tx_last;
    assign tx_slot_available_i = !tx_valid_r || soup_tx_ready;
    assign login_ready = transport_connected && !session_active &&
                         !login_build_active_r &&
                         !login_format_active_r &&
                         !login_packet_pending_r &&
                         !sequence_parse_active_r;
    assign logout_ready = transport_connected && session_active &&
                          tx_slot_available_i &&
                          !login_packet_pending_r;
    assign ouch_tx_ready = transport_connected && session_active &&
                           tx_slot_available_i &&
                           !login_packet_pending_r && !logout_valid;
    assign tx_fire_i = ouch_tx_valid && ouch_tx_ready;
    assign logout_fire_i = logout_valid && logout_ready;
    assign login_in_progress = login_build_active_r ||
                               login_format_active_r ||
                               login_packet_pending_r ||
                               sequence_parse_active_r;

    assign soup_tx_valid = tx_valid_r;
    assign soup_tx_data = tx_data_r;
    assign soup_tx_keep = tx_keep_r;
    assign soup_tx_last = 1'b1;

    assign rx_beat_bytes_i = count_keep(soup_rx_keep);
    assign rx_keep_valid_i = keep_is_contiguous(soup_rx_keep) &&
                             rx_beat_bytes_i != 0;
    assign rx_packet_length_i = {soup_rx_data[7:0], soup_rx_data[15:8]};
    assign rx_total_bytes_i = {1'b0, rx_packet_length_i} + 17'd2;
    assign rx_payload_bytes_i =
        (rx_packet_length_i == 0) ? 16'd0 : rx_packet_length_i - 1'b1;
    assign rx_packet_type_i = soup_rx_data[23:16];
    assign ouch_slot_available_i = !ouch_valid_r || ouch_rx_ready;

    always_comb begin
        case (rx_state_r)
            RX_SECOND: soup_rx_ready = ouch_slot_available_i;
            default: begin
                if (rx_packet_type_i == 8'h53 && session_active &&
                    soup_rx_last) begin
                    soup_rx_ready = ouch_slot_available_i;
                end else begin
                    soup_rx_ready = 1'b1;
                end
            end
        endcase
    end
    assign rx_fire_i = soup_rx_valid && soup_rx_ready;

    assign ouch_rx_valid = ouch_valid_r;
    assign ouch_rx_data = ouch_data_r;
    assign ouch_rx_keep = ouch_keep_r;
    assign ouch_rx_last = 1'b1;

    always_ff @(posedge clk) begin
        logic [511:0] framed_data;
        logic [511:0] completed_data;
        logic [15:0] framed_length;
        logic control_well_formed;
        logic first_beat_well_formed;
        logic second_beat_well_formed;
        logic [7:0] parse_char;
        logic [3:0] parse_digit;
        logic [63:0] parse_value_next;
        logic parse_bad_next;
        logic parse_seen_next;
        logic [79:0] bcd_adjusted;
        logic [79:0] bcd_next;
        logic [3:0] bcd_digit;

        if (rst) begin
            rx_state_r                 <= RX_IDLE;
            tx_valid_r                 <= 1'b0;
            tx_data_r                  <= '0;
            tx_keep_r                  <= '0;
            ouch_valid_r               <= 1'b0;
            ouch_data_r                <= '0;
            ouch_keep_r                <= '0;
            partial_ouch_data_r        <= '0;
            partial_payload_bytes_r    <= '0;
            partial_second_bytes_r     <= '0;
            watchdog_r                 <= '0;
            tx_idle_r                  <= '0;
            login_build_active_r       <= 1'b0;
            login_format_active_r      <= 1'b0;
            login_packet_pending_r     <= 1'b0;
            login_shift_count_r        <= '0;
            login_binary_r             <= '0;
            login_bcd_r                <= '0;
            login_format_index_r       <= '0;
            login_format_seen_nonzero_r <= 1'b0;
            login_data_r               <= '0;
            sequence_parse_active_r    <= 1'b0;
            sequence_parse_index_r     <= '0;
            sequence_ascii_r           <= '0;
            sequence_parse_value_r     <= '0;
            sequence_parse_seen_digit_r <= 1'b0;
            sequence_parse_bad_r       <= 1'b0;
            session_active             <= 1'b0;
            session_fault              <= 1'b0;
            current_session            <= '0;
            next_sequence              <= 64'd1;
            login_request_count        <= '0;
            login_accepted_count       <= '0;
            login_rejected_count       <= '0;
            logout_request_count       <= '0;
            end_session_count          <= '0;
            heartbeat_count            <= '0;
            client_heartbeat_count     <= '0;
            sequenced_packet_count     <= '0;
            inactive_data_count        <= '0;
            malformed_packet_count     <= '0;
            unsupported_packet_count   <= '0;
            watchdog_timeout_count     <= '0;
            tx_unsequenced_count       <= '0;
            tx_malformed_count         <= '0;
            sequence_parse_error_count <= '0;
        end else begin
            session_fault <= 1'b0;
            if (tx_valid_r && soup_tx_ready) begin
                tx_valid_r <= 1'b0;
                tx_idle_r <= '0;
            end
            if (ouch_valid_r && ouch_rx_ready) ouch_valid_r <= 1'b0;

            if (!transport_connected) begin
                if (session_active) session_fault <= 1'b1;
                session_active <= 1'b0;
                watchdog_r <= '0;
                tx_idle_r <= '0;
                tx_valid_r <= 1'b0;
                login_build_active_r <= 1'b0;
                login_format_active_r <= 1'b0;
                login_packet_pending_r <= 1'b0;
                sequence_parse_active_r <= 1'b0;
            end else begin
                if (session_active && WATCHDOG_CYCLES > 0) begin
                    if (watchdog_r >= WATCHDOG_CYCLES - 1) begin
                        watchdog_r <= '0;
                        session_active <= 1'b0;
                        session_fault <= 1'b1;
                        watchdog_timeout_count <=
                            increment_saturating(watchdog_timeout_count);
                    end else begin
                        watchdog_r <= watchdog_r + 1'b1;
                    end
                end else begin
                    watchdog_r <= '0;
                end

                if (session_active && CLIENT_HEARTBEAT_CYCLES > 0) begin
                    if (tx_idle_r < CLIENT_HEARTBEAT_CYCLES - 1)
                        tx_idle_r <= tx_idle_r + 1'b1;
                end else if (!session_active) begin
                    tx_idle_r <= '0;
                end

                if (login_valid && login_ready) begin
                    login_data_r <= '0;
                    login_data_r[7:0] <= 8'd0;
                    login_data_r[15:8] <= 8'd47;
                    login_data_r[23:16] <= 8'h4c;
                    for (int i = 0; i < 6; i++)
                        login_data_r[(3+i)*8 +: 8] <=
                            login_username[i*8 +: 8];
                    for (int i = 0; i < 10; i++) begin
                        login_data_r[(9+i)*8 +: 8] <=
                            login_password[i*8 +: 8];
                        login_data_r[(19+i)*8 +: 8] <=
                            requested_session[i*8 +: 8];
                        login_data_r[(29+i)*8 +: 8] <= 8'h20;
                        login_data_r[(39+i)*8 +: 8] <= 8'h20;
                    end
                    login_shift_count_r <= '0;
                    login_binary_r <= requested_sequence;
                    login_bcd_r <= '0;
                    login_build_active_r <= 1'b1;
                    login_format_active_r <= 1'b0;
                end

                if (login_build_active_r) begin
                    bcd_adjusted = login_bcd_r;
                    for (int i = 0; i < 20; i++) begin
                        if (login_bcd_r[i*4 +: 4] >= 5)
                            bcd_adjusted[i*4 +: 4] =
                                login_bcd_r[i*4 +: 4] + 4'd3;
                    end
                    bcd_next = {bcd_adjusted[78:0], login_binary_r[63]};
                    login_bcd_r <= bcd_next;
                    login_binary_r <= login_binary_r << 1;
                    if (login_shift_count_r == 6'd63) begin
                        login_build_active_r <= 1'b0;
                        login_format_active_r <= 1'b1;
                        login_format_index_r <= '0;
                        login_format_seen_nonzero_r <= 1'b0;
                    end else begin
                        login_shift_count_r <= login_shift_count_r + 1'b1;
                    end
                end

                if (login_format_active_r) begin
                    bcd_digit = login_bcd_r[
                        (19-login_format_index_r)*4 +: 4];
                    if (bcd_digit != 0) begin
                        login_data_r[(29+login_format_index_r)*8 +: 8] <=
                            8'h30 + bcd_digit;
                        login_format_seen_nonzero_r <= 1'b1;
                    end else begin
                        login_data_r[(29+login_format_index_r)*8 +: 8] <=
                            (login_format_seen_nonzero_r ||
                             login_format_index_r == 5'd19) ?
                            8'h30 : 8'h20;
                    end
                    if (login_format_index_r == 5'd19) begin
                        login_format_active_r <= 1'b0;
                        login_packet_pending_r <= 1'b1;
                    end else begin
                        login_format_index_r <=
                            login_format_index_r + 1'b1;
                    end
                end

                if (sequence_parse_active_r) begin
                    parse_char = sequence_ascii_r[
                        sequence_parse_index_r*8 +: 8];
                    parse_value_next = sequence_parse_value_r;
                    parse_bad_next = sequence_parse_bad_r;
                    parse_seen_next = sequence_parse_seen_digit_r;
                    parse_digit = 4'd0;
                    if (parse_char >= 8'h30 && parse_char <= 8'h39) begin
                        parse_digit = parse_char - 8'h30;
                        parse_seen_next = 1'b1;
                        if (sequence_parse_value_r >
                            64'd1844674407370955161 ||
                            (sequence_parse_value_r ==
                             64'd1844674407370955161 && parse_digit > 5)) begin
                            parse_bad_next = 1'b1;
                        end else begin
                            parse_value_next =
                                (sequence_parse_value_r << 3) +
                                (sequence_parse_value_r << 1) + parse_digit;
                        end
                    end else if (parse_char != 8'h20 ||
                                 sequence_parse_seen_digit_r) begin
                        parse_bad_next = 1'b1;
                    end

                    sequence_parse_value_r <= parse_value_next;
                    sequence_parse_seen_digit_r <= parse_seen_next;
                    sequence_parse_bad_r <= parse_bad_next;
                    if (sequence_parse_index_r == 5'd19) begin
                        sequence_parse_active_r <= 1'b0;
                        if (!parse_bad_next && parse_seen_next) begin
                            next_sequence <= parse_value_next;
                            session_active <= 1'b1;
                            watchdog_r <= '0;
                            tx_idle_r <= '0;
                            login_accepted_count <= increment_saturating(
                                login_accepted_count);
                        end else begin
                            session_active <= 1'b0;
                            session_fault <= 1'b1;
                            malformed_packet_count <= increment_saturating(
                                malformed_packet_count);
                            sequence_parse_error_count <= increment_saturating(
                                sequence_parse_error_count);
                        end
                    end else begin
                        sequence_parse_index_r <=
                            sequence_parse_index_r + 1'b1;
                    end
                end

                if (tx_slot_available_i) begin
                    if (logout_fire_i) begin
                        tx_data_r <= '0;
                        tx_data_r[7:0] <= 8'd0;
                        tx_data_r[15:8] <= 8'd1;
                        tx_data_r[23:16] <= 8'h4f;
                        tx_keep_r <= keep_mask(7'd3);
                        tx_valid_r <= 1'b1;
                        session_active <= 1'b0;
                        watchdog_r <= '0;
                        tx_idle_r <= '0;
                        logout_request_count <= increment_saturating(
                            logout_request_count);
                    end else if (login_packet_pending_r) begin
                        tx_data_r <= login_data_r;
                        tx_keep_r <= keep_mask(7'd49);
                        tx_valid_r <= 1'b1;
                        login_packet_pending_r <= 1'b0;
                        tx_idle_r <= '0;
                        login_request_count <= increment_saturating(
                            login_request_count);
                    end else if (tx_fire_i) begin
                        if (tx_keep_valid_i) begin
                            framed_data = ouch_tx_data << 24;
                            framed_length = {9'd0, tx_payload_bytes_i} + 16'd1;
                            framed_data[7:0] = framed_length[15:8];
                            framed_data[15:8] = framed_length[7:0];
                            framed_data[23:16] = 8'h55;
                            tx_data_r <= framed_data;
                            tx_keep_r <= keep_mask(tx_payload_bytes_i + 7'd3);
                            tx_valid_r <= 1'b1;
                            tx_idle_r <= '0;
                            tx_unsequenced_count <= increment_saturating(
                                tx_unsequenced_count);
                        end else begin
                            tx_malformed_count <= increment_saturating(
                                tx_malformed_count);
                        end
                    end else if (session_active &&
                                 CLIENT_HEARTBEAT_CYCLES > 0 &&
                                 tx_idle_r >= CLIENT_HEARTBEAT_CYCLES - 1) begin
                        tx_data_r <= '0;
                        tx_data_r[7:0] <= 8'd0;
                        tx_data_r[15:8] <= 8'd1;
                        tx_data_r[23:16] <= 8'h52;
                        tx_keep_r <= keep_mask(7'd3);
                        tx_valid_r <= 1'b1;
                        tx_idle_r <= '0;
                        client_heartbeat_count <= increment_saturating(
                            client_heartbeat_count);
                    end
                end
            end

            if (rx_fire_i) begin
                case (rx_state_r)
                    RX_IDLE: begin
                        control_well_formed = rx_keep_valid_i && soup_rx_last &&
                            rx_packet_length_i >= 1 &&
                            rx_total_bytes_i <= 64 &&
                            rx_beat_bytes_i == rx_total_bytes_i;

                        case (rx_packet_type_i)
                            8'h41: begin // Login Accepted
                                if (control_well_formed &&
                                    rx_packet_length_i == 16'd31 &&
                                    transport_connected &&
                                    !sequence_parse_active_r) begin
                                    for (int i = 0; i < 10; i++)
                                        current_session[i*8 +: 8] <=
                                            soup_rx_data[(3+i)*8 +: 8];
                                    for (int i = 0; i < 20; i++)
                                        sequence_ascii_r[i*8 +: 8] <=
                                            soup_rx_data[(13+i)*8 +: 8];
                                    sequence_parse_index_r <= '0;
                                    sequence_parse_value_r <= '0;
                                    sequence_parse_seen_digit_r <= 1'b0;
                                    sequence_parse_bad_r <= 1'b0;
                                    sequence_parse_active_r <= 1'b1;
                                    session_active <= 1'b0;
                                end else begin
                                    malformed_packet_count <=
                                        increment_saturating(malformed_packet_count);
                                    if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                                end
                            end
                            8'h4a: begin // Login Rejected
                                if (control_well_formed &&
                                    rx_packet_length_i == 16'd2) begin
                                    session_active <= 1'b0;
                                    session_fault <= 1'b1;
                                    watchdog_r <= '0;
                                    login_rejected_count <= increment_saturating(
                                        login_rejected_count);
                                end else begin
                                    malformed_packet_count <=
                                        increment_saturating(malformed_packet_count);
                                    if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                                end
                            end
                            8'h48: begin // Server Heartbeat
                                if (control_well_formed &&
                                    rx_packet_length_i == 16'd1) begin
                                    watchdog_r <= '0;
                                    heartbeat_count <= increment_saturating(
                                        heartbeat_count);
                                end else begin
                                    malformed_packet_count <=
                                        increment_saturating(malformed_packet_count);
                                    if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                                end
                            end
                            8'h5a: begin // End Of Session
                                if (control_well_formed &&
                                    rx_packet_length_i == 16'd1) begin
                                    session_active <= 1'b0;
                                    session_fault <= 1'b1;
                                    watchdog_r <= '0;
                                    end_session_count <= increment_saturating(
                                        end_session_count);
                                end else begin
                                    malformed_packet_count <=
                                        increment_saturating(malformed_packet_count);
                                    if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                                end
                            end
                            8'h53: begin // Sequenced Data
                                first_beat_well_formed = rx_keep_valid_i &&
                                    rx_packet_length_i >= 2 &&
                                    rx_payload_bytes_i <= 64;
                                if (!session_active) begin
                                    inactive_data_count <= increment_saturating(
                                        inactive_data_count);
                                    session_fault <= 1'b1;
                                    if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                                end else if (!first_beat_well_formed) begin
                                    malformed_packet_count <= increment_saturating(
                                        malformed_packet_count);
                                    if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                                end else if (soup_rx_last) begin
                                    if (rx_total_bytes_i <= 64 &&
                                        rx_beat_bytes_i == rx_total_bytes_i) begin
                                        ouch_data_r <= soup_rx_data >> 24;
                                        ouch_keep_r <= keep_mask(
                                            rx_payload_bytes_i[6:0]);
                                        ouch_valid_r <= 1'b1;
                                        watchdog_r <= '0;
                                        next_sequence <= increment_sequence(
                                            next_sequence);
                                        sequenced_packet_count <=
                                            increment_saturating(
                                                sequenced_packet_count);
                                    end else begin
                                        malformed_packet_count <=
                                            increment_saturating(
                                                malformed_packet_count);
                                    end
                                end else if (soup_rx_keep ==
                                             64'hffff_ffff_ffff_ffff &&
                                             rx_total_bytes_i > 64 &&
                                             rx_total_bytes_i <= 67) begin
                                    partial_ouch_data_r <= soup_rx_data >> 24;
                                    partial_payload_bytes_r <=
                                        rx_payload_bytes_i[6:0];
                                    partial_second_bytes_r <=
                                        rx_total_bytes_i[6:0] - 7'd64;
                                    rx_state_r <= RX_SECOND;
                                end else begin
                                    malformed_packet_count <= increment_saturating(
                                        malformed_packet_count);
                                    rx_state_r <= RX_DRAIN;
                                end
                            end
                            default: begin
                                unsupported_packet_count <= increment_saturating(
                                    unsupported_packet_count);
                                if (!soup_rx_last) rx_state_r <= RX_DRAIN;
                            end
                        endcase
                    end

                    RX_SECOND: begin
                        second_beat_well_formed = soup_rx_last &&
                            rx_keep_valid_i &&
                            rx_beat_bytes_i == partial_second_bytes_r;
                        if (second_beat_well_formed) begin
                            completed_data = partial_ouch_data_r;
                            for (int i = 0; i < 3; i++) begin
                                if (i < partial_second_bytes_r)
                                    completed_data[(61+i)*8 +: 8] =
                                        soup_rx_data[i*8 +: 8];
                            end
                            ouch_data_r <= completed_data;
                            ouch_keep_r <= keep_mask(partial_payload_bytes_r);
                            ouch_valid_r <= 1'b1;
                            watchdog_r <= '0;
                            next_sequence <= increment_sequence(next_sequence);
                            sequenced_packet_count <= increment_saturating(
                                sequenced_packet_count);
                            rx_state_r <= RX_IDLE;
                        end else begin
                            malformed_packet_count <= increment_saturating(
                                malformed_packet_count);
                            if (soup_rx_last) rx_state_r <= RX_IDLE;
                            else rx_state_r <= RX_DRAIN;
                        end
                    end

                    default: begin // RX_DRAIN
                        if (soup_rx_last) rx_state_r <= RX_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
