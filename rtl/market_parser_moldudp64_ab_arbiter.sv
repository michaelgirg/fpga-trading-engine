`default_nettype none
// =============================================================================
// Module: market_parser_moldudp64_ab_arbiter
// =============================================================================
// Packet-atomic redundant-feed merger. Each input must begin a packet with a
// complete MoldUDP64 header at HEADER_BYTE_OFFSET. Upstream packet buffers hold
// the first beat until selected, allowing this block to wait briefly for the
// expected sequence on the other feed without storing another packet copy.
module market_parser_moldudp64_ab_arbiter #(
    parameter int HEADER_BYTE_OFFSET = 0,
    parameter int MAX_SKEW_CYCLES = 32,
    parameter bit NORMALIZE_SESSION = 1'b1,
    parameter logic [79:0] MERGED_SESSION_ID = 80'h4d455247454420202020
) (
    input  wire logic         clk,
    input  wire logic         rst,
    input  wire logic         rearm,

    input  wire logic         s_axis_a_tvalid,
    output logic              s_axis_a_tready,
    input  wire logic [511:0] s_axis_a_tdata,
    input  wire logic [ 63:0] s_axis_a_tkeep,
    input  wire logic         s_axis_a_tlast,
    input  wire logic         s_axis_a_tuser_bad_frame,

    input  wire logic         s_axis_b_tvalid,
    output logic              s_axis_b_tready,
    input  wire logic [511:0] s_axis_b_tdata,
    input  wire logic [ 63:0] s_axis_b_tkeep,
    input  wire logic         s_axis_b_tlast,
    input  wire logic         s_axis_b_tuser_bad_frame,

    output logic              m_axis_tvalid,
    input  wire logic         m_axis_tready,
    output logic [511:0]      m_axis_tdata,
    output logic [ 63:0]      m_axis_tkeep,
    output logic              m_axis_tlast,
    output logic              m_axis_tuser_bad_frame,

    output logic              sequence_initialized,
    output logic [63:0]       expected_sequence,
    output logic              active_source,
    output logic              merge_fault,
    output logic              gap_event,
    output logic [31:0]       selected_a_packet_count,
    output logic [31:0]       selected_b_packet_count,
    output logic [31:0]       duplicate_a_packet_count,
    output logic [31:0]       duplicate_b_packet_count,
    output logic [31:0]       malformed_a_packet_count,
    output logic [31:0]       malformed_b_packet_count,
    output logic [31:0]       failover_count,
    output logic [31:0]       gap_count,
    output logic [31:0]       divergence_count,
    output logic [31:0]       session_change_a_count,
    output logic [31:0]       session_change_b_count
);
    typedef enum logic [2:0] {
        STATE_IDLE   = 3'd0,
        STATE_FWD_A  = 3'd1,
        STATE_FWD_B  = 3'd2,
        STATE_DROP_A = 3'd3,
        STATE_DROP_B = 3'd4,
        STATE_FAULT  = 3'd5
    } state_t;

    state_t state_r;
    logic packet_first_r;
    logic prefer_b_r;
    logic last_source_valid_r;
    logic [31:0] skew_wait_r;
    logic a_session_valid_r;
    logic b_session_valid_r;
    logic [79:0] a_session_r;
    logic [79:0] b_session_r;
    logic last_packet_valid_r;
    logic [63:0] last_packet_sequence_r;
    logic [15:0] last_packet_count_r;

    logic a_header_valid_i;
    logic b_header_valid_i;
    logic [63:0] a_sequence_i;
    logic [63:0] b_sequence_i;
    logic [15:0] a_message_count_i;
    logic [15:0] b_message_count_i;
    logic [79:0] a_session_i;
    logic [79:0] b_session_i;
    logic output_fire_i;

    initial begin
        if (HEADER_BYTE_OFFSET < 0 || HEADER_BYTE_OFFSET + 20 > 64)
            $fatal(1, "MoldUDP64 header must fit in the first 512-bit beat");
        if (MAX_SKEW_CYCLES < 1)
            $fatal(1, "MAX_SKEW_CYCLES must be at least 1");
    end

    function automatic logic [31:0] increment_saturating(
        input logic [31:0] value
    );
        increment_saturating =
            (value == 32'hffff_ffff) ? value : value + 1'b1;
    endfunction

    function automatic logic keep_range_valid(
        input logic [63:0] keep,
        input int first_byte,
        input int byte_count
    );
        logic valid;
        valid = 1'b1;
        for (int i = 0; i < byte_count; i++) begin
            if (!keep[first_byte + i]) valid = 1'b0;
        end
        keep_range_valid = valid;
    endfunction

    function automatic logic [63:0] extract_sequence(
        input logic [511:0] data
    );
        extract_sequence = {
            data[(HEADER_BYTE_OFFSET+10)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+11)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+12)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+13)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+14)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+15)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+16)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+17)*8 +: 8]
        };
    endfunction

    function automatic logic [15:0] extract_message_count(
        input logic [511:0] data
    );
        extract_message_count = {
            data[(HEADER_BYTE_OFFSET+18)*8 +: 8],
            data[(HEADER_BYTE_OFFSET+19)*8 +: 8]
        };
    endfunction

    assign a_header_valid_i = s_axis_a_tvalid &&
                              !s_axis_a_tuser_bad_frame &&
                              keep_range_valid(s_axis_a_tkeep,
                                               HEADER_BYTE_OFFSET, 20);
    assign b_header_valid_i = s_axis_b_tvalid &&
                              !s_axis_b_tuser_bad_frame &&
                              keep_range_valid(s_axis_b_tkeep,
                                               HEADER_BYTE_OFFSET, 20);
    assign a_sequence_i = extract_sequence(s_axis_a_tdata);
    assign b_sequence_i = extract_sequence(s_axis_b_tdata);
    assign a_message_count_i = extract_message_count(s_axis_a_tdata);
    assign b_message_count_i = extract_message_count(s_axis_b_tdata);
    assign a_session_i = s_axis_a_tdata[HEADER_BYTE_OFFSET*8 +: 80];
    assign b_session_i = s_axis_b_tdata[HEADER_BYTE_OFFSET*8 +: 80];
    assign output_fire_i = m_axis_tvalid && m_axis_tready;

    assign sequence_initialized = last_source_valid_r;

    always_comb begin
        s_axis_a_tready = 1'b0;
        s_axis_b_tready = 1'b0;
        m_axis_tvalid = 1'b0;
        m_axis_tdata = '0;
        m_axis_tkeep = '0;
        m_axis_tlast = 1'b0;
        m_axis_tuser_bad_frame = 1'b0;

        case (state_r)
            STATE_FWD_A: begin
                m_axis_tvalid = s_axis_a_tvalid;
                m_axis_tdata = s_axis_a_tdata;
                m_axis_tkeep = s_axis_a_tkeep;
                m_axis_tlast = s_axis_a_tlast;
                m_axis_tuser_bad_frame = s_axis_a_tuser_bad_frame;
                s_axis_a_tready = m_axis_tready;
                if (NORMALIZE_SESSION && packet_first_r)
                    m_axis_tdata[HEADER_BYTE_OFFSET*8 +: 80] =
                        MERGED_SESSION_ID;
            end
            STATE_FWD_B: begin
                m_axis_tvalid = s_axis_b_tvalid;
                m_axis_tdata = s_axis_b_tdata;
                m_axis_tkeep = s_axis_b_tkeep;
                m_axis_tlast = s_axis_b_tlast;
                m_axis_tuser_bad_frame = s_axis_b_tuser_bad_frame;
                s_axis_b_tready = m_axis_tready;
                if (NORMALIZE_SESSION && packet_first_r)
                    m_axis_tdata[HEADER_BYTE_OFFSET*8 +: 80] =
                        MERGED_SESSION_ID;
            end
            STATE_DROP_A: s_axis_a_tready = 1'b1;
            STATE_DROP_B: s_axis_b_tready = 1'b1;
            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        logic choose_a;
        logic choose_b;
        logic [63:0] selected_sequence;
        logic [15:0] selected_count;
        logic [79:0] selected_session;

        if (rst) begin
            state_r <= STATE_IDLE;
            packet_first_r <= 1'b0;
            prefer_b_r <= 1'b0;
            last_source_valid_r <= 1'b0;
            expected_sequence <= '0;
            active_source <= 1'b0;
            merge_fault <= 1'b0;
            gap_event <= 1'b0;
            skew_wait_r <= '0;
            a_session_valid_r <= 1'b0;
            b_session_valid_r <= 1'b0;
            a_session_r <= '0;
            b_session_r <= '0;
            last_packet_valid_r <= 1'b0;
            last_packet_sequence_r <= '0;
            last_packet_count_r <= '0;
            selected_a_packet_count <= '0;
            selected_b_packet_count <= '0;
            duplicate_a_packet_count <= '0;
            duplicate_b_packet_count <= '0;
            malformed_a_packet_count <= '0;
            malformed_b_packet_count <= '0;
            failover_count <= '0;
            gap_count <= '0;
            divergence_count <= '0;
            session_change_a_count <= '0;
            session_change_b_count <= '0;
        end else begin
            gap_event <= 1'b0;
            choose_a = 1'b0;
            choose_b = 1'b0;
            selected_sequence = '0;
            selected_count = '0;
            selected_session = '0;

            if (rearm) begin
                merge_fault <= 1'b0;
                last_source_valid_r <= 1'b0;
                last_packet_valid_r <= 1'b0;
                skew_wait_r <= '0;
                packet_first_r <= 1'b0;
                case (state_r)
                    STATE_FWD_A, STATE_DROP_A: state_r <= STATE_DROP_A;
                    STATE_FWD_B, STATE_DROP_B: state_r <= STATE_DROP_B;
                    default: state_r <= STATE_IDLE;
                endcase
            end else begin
                case (state_r)
                    STATE_IDLE: begin
                        packet_first_r <= 1'b0;

                        if (a_header_valid_i && last_packet_valid_r &&
                            a_sequence_i == last_packet_sequence_r &&
                            a_message_count_i == last_packet_count_r) begin
                            duplicate_a_packet_count <= increment_saturating(
                                duplicate_a_packet_count);
                            packet_first_r <= 1'b1;
                            state_r <= STATE_DROP_A;
                        end else if (b_header_valid_i && last_packet_valid_r &&
                                     b_sequence_i == last_packet_sequence_r &&
                                     b_message_count_i == last_packet_count_r) begin
                            duplicate_b_packet_count <= increment_saturating(
                                duplicate_b_packet_count);
                            packet_first_r <= 1'b1;
                            state_r <= STATE_DROP_B;
                        end else if (!last_source_valid_r) begin
                            if (a_header_valid_i && b_header_valid_i &&
                                a_sequence_i == b_sequence_i &&
                                a_message_count_i != b_message_count_i) begin
                                merge_fault <= 1'b1;
                                divergence_count <= increment_saturating(
                                    divergence_count);
                                state_r <= STATE_FAULT;
                            end else if (a_header_valid_i && b_header_valid_i) begin
                                if (a_sequence_i < b_sequence_i)
                                    choose_a = 1'b1;
                                else if (b_sequence_i < a_sequence_i)
                                    choose_b = 1'b1;
                                else if (prefer_b_r)
                                    choose_b = 1'b1;
                                else
                                    choose_a = 1'b1;
                            end else if (a_header_valid_i) begin
                                choose_a = 1'b1;
                            end else if (b_header_valid_i) begin
                                choose_b = 1'b1;
                            end else if (s_axis_a_tvalid) begin
                                malformed_a_packet_count <= increment_saturating(
                                    malformed_a_packet_count);
                                packet_first_r <= 1'b1;
                                state_r <= STATE_DROP_A;
                            end else if (s_axis_b_tvalid) begin
                                malformed_b_packet_count <= increment_saturating(
                                    malformed_b_packet_count);
                                packet_first_r <= 1'b1;
                                state_r <= STATE_DROP_B;
                            end
                        end else if (a_header_valid_i && b_header_valid_i &&
                                     a_sequence_i == expected_sequence &&
                                     b_sequence_i == expected_sequence &&
                                     a_message_count_i != b_message_count_i) begin
                            merge_fault <= 1'b1;
                            divergence_count <= increment_saturating(
                                divergence_count);
                            state_r <= STATE_FAULT;
                        end else if (a_header_valid_i &&
                                     a_sequence_i == expected_sequence &&
                                     b_header_valid_i &&
                                     b_sequence_i == expected_sequence) begin
                            if (prefer_b_r) choose_b = 1'b1;
                            else choose_a = 1'b1;
                        end else if (a_header_valid_i &&
                                     a_sequence_i == expected_sequence) begin
                            choose_a = 1'b1;
                        end else if (b_header_valid_i &&
                                     b_sequence_i == expected_sequence) begin
                            choose_b = 1'b1;
                        end else if (a_header_valid_i &&
                                     a_sequence_i < expected_sequence) begin
                            duplicate_a_packet_count <= increment_saturating(
                                duplicate_a_packet_count);
                            packet_first_r <= 1'b1;
                            state_r <= STATE_DROP_A;
                        end else if (b_header_valid_i &&
                                     b_sequence_i < expected_sequence) begin
                            duplicate_b_packet_count <= increment_saturating(
                                duplicate_b_packet_count);
                            packet_first_r <= 1'b1;
                            state_r <= STATE_DROP_B;
                        end else if (s_axis_a_tvalid && !a_header_valid_i) begin
                            malformed_a_packet_count <= increment_saturating(
                                malformed_a_packet_count);
                            packet_first_r <= 1'b1;
                            state_r <= STATE_DROP_A;
                        end else if (s_axis_b_tvalid && !b_header_valid_i) begin
                            malformed_b_packet_count <= increment_saturating(
                                malformed_b_packet_count);
                            packet_first_r <= 1'b1;
                            state_r <= STATE_DROP_B;
                        end else if (s_axis_a_tvalid || s_axis_b_tvalid) begin
                            if (skew_wait_r >= MAX_SKEW_CYCLES - 1) begin
                                merge_fault <= 1'b1;
                                gap_event <= 1'b1;
                                gap_count <= increment_saturating(gap_count);
                                skew_wait_r <= '0;
                                state_r <= STATE_FAULT;
                            end else begin
                                skew_wait_r <= skew_wait_r + 1'b1;
                            end
                        end else begin
                            skew_wait_r <= '0;
                        end

                        if (choose_a || choose_b) begin
                            packet_first_r <= 1'b1;
                            skew_wait_r <= '0;
                            state_r <= choose_a ? STATE_FWD_A : STATE_FWD_B;
                        end
                    end

                    STATE_FWD_A, STATE_FWD_B: begin
                        if (output_fire_i) begin
                            if (packet_first_r) begin
                                if (state_r == STATE_FWD_A) begin
                                    selected_sequence = a_sequence_i;
                                    selected_count = a_message_count_i;
                                    selected_session = a_session_i;
                                    selected_a_packet_count <= increment_saturating(
                                        selected_a_packet_count);
                                    if (a_session_valid_r &&
                                        a_session_r != selected_session)
                                        session_change_a_count <=
                                            increment_saturating(
                                                session_change_a_count);
                                    a_session_r <= selected_session;
                                    a_session_valid_r <= 1'b1;
                                    prefer_b_r <= 1'b1;
                                    if (last_source_valid_r && active_source)
                                        failover_count <= increment_saturating(
                                            failover_count);
                                    active_source <= 1'b0;
                                end else begin
                                    selected_sequence = b_sequence_i;
                                    selected_count = b_message_count_i;
                                    selected_session = b_session_i;
                                    selected_b_packet_count <= increment_saturating(
                                        selected_b_packet_count);
                                    if (b_session_valid_r &&
                                        b_session_r != selected_session)
                                        session_change_b_count <=
                                            increment_saturating(
                                                session_change_b_count);
                                    b_session_r <= selected_session;
                                    b_session_valid_r <= 1'b1;
                                    prefer_b_r <= 1'b0;
                                    if (last_source_valid_r && !active_source)
                                        failover_count <= increment_saturating(
                                            failover_count);
                                    active_source <= 1'b1;
                                end

                                if (selected_count == 16'hffff) begin
                                    last_source_valid_r <= 1'b0;
                                end else begin
                                    expected_sequence <= selected_sequence +
                                        64'(selected_count);
                                    last_source_valid_r <= 1'b1;
                                end
                                last_packet_valid_r <= 1'b1;
                                last_packet_sequence_r <= selected_sequence;
                                last_packet_count_r <= selected_count;
                                packet_first_r <= 1'b0;
                            end

                            if (m_axis_tlast) begin
                                packet_first_r <= 1'b0;
                                state_r <= STATE_IDLE;
                            end
                        end
                    end

                    STATE_DROP_A: begin
                        if (s_axis_a_tvalid) begin
                            if (packet_first_r && a_header_valid_i) begin
                                if (a_session_valid_r &&
                                    a_session_r != a_session_i)
                                    session_change_a_count <=
                                        increment_saturating(
                                            session_change_a_count);
                                a_session_r <= a_session_i;
                                a_session_valid_r <= 1'b1;
                            end
                            packet_first_r <= 1'b0;
                            if (s_axis_a_tlast) state_r <= STATE_IDLE;
                        end
                    end

                    STATE_DROP_B: begin
                        if (s_axis_b_tvalid) begin
                            if (packet_first_r && b_header_valid_i) begin
                                if (b_session_valid_r &&
                                    b_session_r != b_session_i)
                                    session_change_b_count <=
                                        increment_saturating(
                                            session_change_b_count);
                                b_session_r <= b_session_i;
                                b_session_valid_r <= 1'b1;
                            end
                            packet_first_r <= 1'b0;
                            if (s_axis_b_tlast) state_r <= STATE_IDLE;
                        end
                    end

                    default: begin // STATE_FAULT
                        state_r <= STATE_FAULT;
                    end
                endcase
            end
        end
    end

endmodule
`default_nettype wire
