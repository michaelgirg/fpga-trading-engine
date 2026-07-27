`timescale 1ns / 100ps
`default_nettype none

module market_parser_moldudp64_ab_arbiter_tb;
    localparam logic [79:0] MERGED_SESSION = 80'h4d455247454420202020;

    logic clk = 1'b0;
    logic rst;
    logic rearm;
    logic a_valid;
    logic a_ready;
    logic [511:0] a_data;
    logic [63:0] a_keep;
    logic a_last;
    logic a_bad;
    logic b_valid;
    logic b_ready;
    logic [511:0] b_data;
    logic [63:0] b_keep;
    logic b_last;
    logic b_bad;
    logic out_valid;
    logic out_ready;
    logic [511:0] out_data;
    logic [63:0] out_keep;
    logic out_last;
    logic out_bad;
    logic sequence_initialized;
    logic [63:0] expected_sequence;
    logic active_source;
    logic merge_fault;
    logic gap_event;
    logic [31:0] selected_a_packet_count;
    logic [31:0] selected_b_packet_count;
    logic [31:0] duplicate_a_packet_count;
    logic [31:0] duplicate_b_packet_count;
    logic [31:0] malformed_a_packet_count;
    logic [31:0] malformed_b_packet_count;
    logic [31:0] failover_count;
    logic [31:0] gap_count;
    logic [31:0] divergence_count;
    logic [31:0] session_change_a_count;
    logic [31:0] session_change_b_count;
    logic [63:0] observed_sequence [0:15];
    logic [15:0] observed_count [0:15];
    logic [79:0] observed_session [0:15];
    int observed_packets;
    int failed;

    always #1.551ns clk = ~clk;

    function automatic logic [511:0] make_header(
        input logic [79:0] session,
        input logic [63:0] seq_num,
        input logic [15:0] message_count,
        input logic [7:0] marker
    );
        logic [511:0] beat;
        beat = '0;
        beat[0 +: 80] = session;
        for (int i = 0; i < 8; i++)
            beat[(10+i)*8 +: 8] = seq_num[(7-i)*8 +: 8];
        beat[18*8 +: 8] = message_count[15:8];
        beat[19*8 +: 8] = message_count[7:0];
        beat[63*8 +: 8] = marker;
        make_header = beat;
    endfunction

    function automatic logic [63:0] get_sequence(input logic [511:0] beat);
        get_sequence = {
            beat[10*8 +: 8], beat[11*8 +: 8],
            beat[12*8 +: 8], beat[13*8 +: 8],
            beat[14*8 +: 8], beat[15*8 +: 8],
            beat[16*8 +: 8], beat[17*8 +: 8]
        };
    endfunction

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    task automatic send_a(
        input logic [79:0] session,
        input logic [63:0] seq_num,
        input logic [15:0] message_count,
        input logic [63:0] keep,
        input logic bad,
        input logic [7:0] marker
    );
        @(negedge clk);
        a_data = make_header(session, seq_num, message_count, marker);
        a_keep = keep;
        a_last = 1'b1;
        a_bad = bad;
        a_valid = 1'b1;
        do @(posedge clk); while (!a_ready);
        @(negedge clk);
        a_valid = 1'b0;
    endtask

    task automatic send_b(
        input logic [79:0] session,
        input logic [63:0] seq_num,
        input logic [15:0] message_count,
        input logic [63:0] keep,
        input logic bad,
        input logic [7:0] marker
    );
        @(negedge clk);
        b_data = make_header(session, seq_num, message_count, marker);
        b_keep = keep;
        b_last = 1'b1;
        b_bad = bad;
        b_valid = 1'b1;
        do @(posedge clk); while (!b_ready);
        @(negedge clk);
        b_valid = 1'b0;
    endtask

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            observed_sequence[observed_packets] = get_sequence(out_data);
            observed_count[observed_packets] = {
                out_data[18*8 +: 8], out_data[19*8 +: 8]
            };
            observed_session[observed_packets] = out_data[0 +: 80];
            observed_packets++;
        end
    end

    market_parser_moldudp64_ab_arbiter #(
        .HEADER_BYTE_OFFSET(0),
        .MAX_SKEW_CYCLES(4),
        .NORMALIZE_SESSION(1'b1),
        .MERGED_SESSION_ID(MERGED_SESSION)
    ) dut (
        .clk(clk), .rst(rst), .rearm(rearm),
        .s_axis_a_tvalid(a_valid), .s_axis_a_tready(a_ready),
        .s_axis_a_tdata(a_data), .s_axis_a_tkeep(a_keep),
        .s_axis_a_tlast(a_last), .s_axis_a_tuser_bad_frame(a_bad),
        .s_axis_b_tvalid(b_valid), .s_axis_b_tready(b_ready),
        .s_axis_b_tdata(b_data), .s_axis_b_tkeep(b_keep),
        .s_axis_b_tlast(b_last), .s_axis_b_tuser_bad_frame(b_bad),
        .m_axis_tvalid(out_valid), .m_axis_tready(out_ready),
        .m_axis_tdata(out_data), .m_axis_tkeep(out_keep),
        .m_axis_tlast(out_last), .m_axis_tuser_bad_frame(out_bad),
        .sequence_initialized(sequence_initialized),
        .expected_sequence(expected_sequence), .active_source(active_source),
        .merge_fault(merge_fault), .gap_event(gap_event),
        .selected_a_packet_count(selected_a_packet_count),
        .selected_b_packet_count(selected_b_packet_count),
        .duplicate_a_packet_count(duplicate_a_packet_count),
        .duplicate_b_packet_count(duplicate_b_packet_count),
        .malformed_a_packet_count(malformed_a_packet_count),
        .malformed_b_packet_count(malformed_b_packet_count),
        .failover_count(failover_count), .gap_count(gap_count),
        .divergence_count(divergence_count),
        .session_change_a_count(session_change_a_count),
        .session_change_b_count(session_change_b_count)
    );

    initial begin
        failed = 0;
        observed_packets = 0;
        rst = 1'b1;
        rearm = 1'b0;
        a_valid = 1'b0;
        a_data = '0;
        a_keep = '0;
        a_last = 1'b0;
        a_bad = 1'b0;
        b_valid = 1'b0;
        b_data = '0;
        b_keep = '0;
        b_last = 1'b0;
        b_bad = 1'b0;
        out_ready = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        fork
            send_a(80'h41414141414141414141, 64'd100, 16'd2,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'ha1);
            send_b(80'h42424242424242424242, 64'd100, 16'd2,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'hb1);
        join
        repeat (3) @(negedge clk);
        check(observed_packets == 1 && observed_sequence[0] == 64'd100 &&
              observed_count[0] == 16'd2,
              "simultaneous duplicate packets produce one ordered output");
        check(selected_a_packet_count == 1 && duplicate_b_packet_count == 1 &&
              expected_sequence == 64'd102,
              "redundant copy is dropped and expected sequence advances");
        check(observed_session[0] == MERGED_SESSION,
              "selected packet receives the normalized merged session ID");

        send_b(80'h42424242424242424242, 64'd102, 16'd1,
               64'hffff_ffff_ffff_ffff, 1'b0, 8'hb2);
        repeat (2) @(negedge clk);
        check(active_source && failover_count == 1 &&
              expected_sequence == 64'd103,
              "expected packet switches cleanly from feed A to feed B");

        fork
            send_a(80'h41414141414141414141, 64'd104, 16'd1,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'ha4);
            begin
                repeat (2) @(negedge clk);
                send_b(80'h42424242424242424242, 64'd103, 16'd1,
                       64'hffff_ffff_ffff_ffff, 1'b0, 8'hb3);
            end
        join
        repeat (3) @(negedge clk);
        check(observed_sequence[2] == 64'd103 &&
              observed_sequence[3] == 64'd104 && expected_sequence == 64'd105,
              "future packet waits while delayed expected packet arrives");
        check(failover_count == 2 && !active_source,
              "feed-switch telemetry records the return to feed A");

        out_ready = 1'b0;
        fork
            send_a(80'h41414141414141414141, 64'd105, 16'd1,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'ha5);
        join_none
        repeat (3) @(negedge clk);
        check(out_valid && !a_ready && out_data[63*8 +: 8] == 8'ha5,
              "downstream backpressure holds the selected packet stable");
        out_ready = 1'b1;
        wait fork;
        repeat (2) @(negedge clk);

        send_b(80'h42424242424242424242, 64'd106, 16'd1,
               64'h0000_0000_0000_ffff, 1'b0, 8'hbe);
        repeat (2) @(negedge clk);
        check(malformed_b_packet_count == 1 && expected_sequence == 64'd106,
              "short MoldUDP64 header is dropped without moving sequence");

        fork
            send_a(80'h4348414e474544414141, 64'd107, 16'd1,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'ha7);
        join_none
        repeat (7) @(negedge clk);
        check(merge_fault && gap_count == 1 && expected_sequence == 64'd106,
              "unrecovered sequence gap times out and fails closed");
        rearm = 1'b1;
        @(negedge clk);
        rearm = 1'b0;
        wait fork;
        repeat (3) @(negedge clk);
        check(!merge_fault && expected_sequence == 64'd108 &&
              session_change_a_count == 1,
              "operator rearm establishes a new baseline and tracks session change");

        fork
            send_a(80'h4348414e474544414141, 64'd108, 16'd0,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'ha0);
            send_b(80'h42424242424242424242, 64'd108, 16'd0,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'hb0);
        join
        repeat (3) @(negedge clk);
        check(expected_sequence == 64'd108 &&
              selected_a_packet_count + selected_b_packet_count == 7 &&
              duplicate_a_packet_count + duplicate_b_packet_count == 2,
              "redundant zero-count heartbeat is emitted once");

        fork
            send_a(80'h4348414e474544414141, 64'd108, 16'hffff,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'hae);
            send_b(80'h42424242424242424242, 64'd108, 16'hffff,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'hbe);
        join
        repeat (3) @(negedge clk);
        check(!sequence_initialized &&
              selected_a_packet_count + selected_b_packet_count == 8 &&
              duplicate_a_packet_count + duplicate_b_packet_count == 3,
              "redundant end-of-session marker is emitted once");

        rearm = 1'b1;
        @(negedge clk);
        rearm = 1'b0;

        fork
            send_a(80'h4348414e474544414141, 64'd300, 16'd1,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'ha8);
            send_b(80'h42424242424242424242, 64'd300, 16'd2,
                   64'hffff_ffff_ffff_ffff, 1'b0, 8'hb8);
        join_none
        repeat (4) @(negedge clk);
        check(merge_fault && divergence_count == 1 &&
              !sequence_initialized,
              "same-sequence metadata disagreement fails closed");
        check(selected_a_packet_count + selected_b_packet_count == 8 &&
              duplicate_a_packet_count + duplicate_b_packet_count == 3,
              "selection and duplicate telemetry matches the exercised traffic");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
