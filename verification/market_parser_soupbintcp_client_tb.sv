`timescale 1ns / 1ps
`default_nettype none

module market_parser_soupbintcp_client_tb;
    localparam time HALF = 1ns;
    logic clk = 1'b0;
    logic rst;
    logic transport_connected;
    logic login_valid;
    logic login_ready;
    logic [47:0] login_username;
    logic [79:0] login_password;
    logic [79:0] requested_session;
    logic [63:0] requested_sequence;
    logic logout_valid;
    logic logout_ready;
    logic ouch_tx_valid;
    logic ouch_tx_ready;
    logic [511:0] ouch_tx_data;
    logic [63:0] ouch_tx_keep;
    logic ouch_tx_last;
    logic soup_tx_valid;
    logic soup_tx_ready;
    logic [511:0] soup_tx_data;
    logic [63:0] soup_tx_keep;
    logic soup_tx_last;
    logic soup_rx_valid;
    logic soup_rx_ready;
    logic [511:0] soup_rx_data;
    logic [63:0] soup_rx_keep;
    logic soup_rx_last;
    logic ouch_rx_valid;
    logic ouch_rx_ready;
    logic [511:0] ouch_rx_data;
    logic [63:0] ouch_rx_keep;
    logic ouch_rx_last;
    logic session_active;
    logic session_fault;
    logic login_in_progress;
    logic [79:0] current_session;
    logic [63:0] next_sequence;
    logic [31:0] login_request_count;
    logic [31:0] login_accepted_count;
    logic [31:0] login_rejected_count;
    logic [31:0] logout_request_count;
    logic [31:0] end_session_count;
    logic [31:0] heartbeat_count;
    logic [31:0] client_heartbeat_count;
    logic [31:0] sequenced_packet_count;
    logic [31:0] inactive_data_count;
    logic [31:0] malformed_packet_count;
    logic [31:0] unsupported_packet_count;
    logic [31:0] watchdog_timeout_count;
    logic [31:0] tx_unsequenced_count;
    logic [31:0] tx_malformed_count;
    logic [31:0] sequence_parse_error_count;
    int failed;

    always #HALF clk = ~clk;

    market_parser_soupbintcp_client #(
        .WATCHDOG_CYCLES(40), .CLIENT_HEARTBEAT_CYCLES(8)
    ) dut (.*);

    task automatic check(input bit condition, input string message);
        if (condition) $display("PASS: %s", message);
        else begin $display("FAIL: %s", message); failed++; end
    endtask

    function automatic logic [63:0] mask(input int count);
        if (count >= 64) mask = 64'hffff_ffff_ffff_ffff;
        else mask = (64'h1 << count) - 1'b1;
    endfunction

    task automatic send_soup_beat(
        input logic [511:0] data,
        input logic [63:0] keep,
        input logic last
    );
        @(negedge clk);
        soup_rx_valid = 1'b1;
        soup_rx_data = data;
        soup_rx_keep = keep;
        soup_rx_last = last;
        while (!soup_rx_ready) @(negedge clk);
        @(negedge clk);
        soup_rx_valid = 1'b0;
    endtask

    task automatic send_login_accepted(
        input logic [79:0] session_id,
        input logic [63:0] sequence_value
    );
        logic [511:0] frame;
        logic [63:0] work;
        frame = '0;
        frame[15:8] = 8'd31;
        frame[23:16] = "A";
        for (int i = 0; i < 10; i++) begin
            frame[(3+i)*8 +: 8] = session_id[i*8 +: 8];
            frame[(13+i)*8 +: 8] = " ";
            frame[(23+i)*8 +: 8] = " ";
        end
        work = sequence_value;
        for (int i = 19; i >= 0; i--) begin
            if (work != 0) begin
                frame[(13+i)*8 +: 8] = "0" + (work % 10);
                work = work / 10;
            end else if (i == 19) begin
                frame[(13+i)*8 +: 8] = "0";
            end
        end
        send_soup_beat(frame, mask(33), 1'b1);
    endtask

    task automatic send_control(input logic [7:0] packet_type);
        logic [511:0] frame;
        frame = '0;
        frame[15:8] = 8'd1;
        frame[23:16] = packet_type;
        send_soup_beat(frame, mask(3), 1'b1);
    endtask

    initial begin
        logic [511:0] frame;
        logic [511:0] payload;
        logic [511:0] held;
        logic [79:0] session_id;
        int wait_cycles;

        failed = 0;
        rst = 1'b1;
        transport_connected = 1'b1;
        login_valid = 1'b0;
        login_username = '0;
        login_password = '0;
        requested_session = {10{8'h20}};
        requested_sequence = 64'd1;
        logout_valid = 1'b0;
        ouch_tx_valid = 1'b0;
        ouch_tx_data = '0;
        ouch_tx_keep = '0;
        ouch_tx_last = 1'b0;
        soup_tx_ready = 1'b0;
        soup_rx_valid = 1'b0;
        soup_rx_data = '0;
        soup_rx_keep = '0;
        soup_rx_last = 1'b0;
        ouch_rx_ready = 1'b0;
        login_username[0*8 +: 8] = "T";
        login_username[1*8 +: 8] = "R";
        login_username[2*8 +: 8] = "D";
        login_username[3*8 +: 8] = "R";
        login_username[4*8 +: 8] = "0";
        login_username[5*8 +: 8] = "1";
        for (int i = 0; i < 10; i++)
            login_password[i*8 +: 8] = "A" + i;
        session_id = '0;
        for (int i = 0; i < 10; i++) session_id[i*8 +: 8] = "0" + i;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        @(negedge clk);
        login_valid = 1'b1;
        while (!login_ready) @(negedge clk);
        @(negedge clk);
        login_valid = 1'b0;
        while (!soup_tx_valid) @(negedge clk);
        check(soup_tx_data[7:0] == 8'd0 &&
              soup_tx_data[15:8] == 8'd47 &&
              soup_tx_data[23:16] == "L" &&
              soup_tx_data[3*8 +: 48] == login_username &&
              soup_tx_data[9*8 +: 80] == login_password &&
              soup_tx_data[19*8 +: 80] == requested_session &&
              soup_tx_data[48*8 +: 8] == "1" &&
              soup_tx_keep == mask(49),
              "client emits an exact 49-byte Login Request");
        held = soup_tx_data;
        repeat (2) begin
            @(negedge clk);
            check(soup_tx_valid && soup_tx_data == held,
                  "Login Request remains stable under backpressure");
        end
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        send_login_accepted(session_id, 64'd41);
        wait_cycles = 0;
        while (!session_active && wait_cycles < 30) begin
            @(negedge clk);
            wait_cycles++;
        end
        check(session_active && current_session == session_id &&
              next_sequence == 64'd41 && login_accepted_count == 1,
              "Login Accepted captures session and parses next sequence");

        payload = '0;
        for (int i = 0; i < 47; i++) payload[i*8 +: 8] = i;
        @(negedge clk);
        ouch_tx_valid = 1'b1;
        ouch_tx_data = payload;
        ouch_tx_keep = mask(47);
        ouch_tx_last = 1'b1;
        while (!ouch_tx_ready) @(negedge clk);
        @(negedge clk);
        ouch_tx_valid = 1'b0;
        while (!soup_tx_valid) @(negedge clk);
        check(soup_tx_data[15:8] == 8'd48 &&
              soup_tx_data[23:16] == "U" &&
              soup_tx_data[511:24] == payload[487:0] &&
              soup_tx_keep == mask(50) && soup_tx_last,
              "outbound OUCH payload receives exact Unsequenced framing");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        payload = '0;
        for (int i = 0; i < 31; i++) payload[i*8 +: 8] = 8'h80 + i;
        frame = payload << 24;
        frame[15:8] = 8'd32;
        frame[23:16] = "S";
        send_soup_beat(frame, mask(34), 1'b1);
        while (!ouch_rx_valid) @(negedge clk);
        check(ouch_rx_data[247:0] == payload[247:0] &&
              ouch_rx_keep == mask(31) && next_sequence == 64'd42,
              "single-beat Sequenced Data advances next sequence");
        ouch_rx_ready = 1'b1;
        @(negedge clk);
        ouch_rx_ready = 1'b0;

        payload = '0;
        for (int i = 0; i < 64; i++) payload[i*8 +: 8] = i + 8'h20;
        frame = payload << 24;
        frame[15:8] = 8'd65;
        frame[23:16] = "S";
        send_soup_beat(frame, 64'hffff_ffff_ffff_ffff, 1'b0);
        frame = '0;
        frame[7:0] = payload[61*8 +: 8];
        frame[15:8] = payload[62*8 +: 8];
        frame[23:16] = payload[63*8 +: 8];
        send_soup_beat(frame, mask(3), 1'b1);
        while (!ouch_rx_valid) @(negedge clk);
        check(ouch_rx_data == payload && next_sequence == 64'd43,
              "two-beat Sequenced Data reconstructs payload and advances once");
        ouch_rx_ready = 1'b1;
        @(negedge clk);
        ouch_rx_ready = 1'b0;

        soup_tx_ready = 1'b0;
        while (!soup_tx_valid) @(negedge clk);
        check(soup_tx_data[23:16] == "R" && soup_tx_keep == mask(3) &&
              client_heartbeat_count == 1,
              "idle active session emits a Client Heartbeat");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        @(negedge clk);
        logout_valid = 1'b1;
        while (!logout_ready) @(negedge clk);
        @(negedge clk);
        logout_valid = 1'b0;
        check(soup_tx_valid && soup_tx_data[23:16] == "O" &&
              !session_active && logout_request_count == 1,
              "Logout Request is framed and deactivates trading");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;

        requested_session = current_session;
        requested_sequence = next_sequence;
        @(negedge clk);
        login_valid = 1'b1;
        while (!login_ready) @(negedge clk);
        @(negedge clk);
        login_valid = 1'b0;
        while (!soup_tx_valid) @(negedge clk);
        check(soup_tx_data[19*8 +: 80] == session_id &&
              soup_tx_data[47*8 +: 8] == "4" &&
              soup_tx_data[48*8 +: 8] == "3",
              "reconnect Login Request uses stored session and next sequence");
        soup_tx_ready = 1'b1;
        @(negedge clk);
        soup_tx_ready = 1'b0;
        send_login_accepted(session_id, 64'd43);
        wait_cycles = 0;
        while (!session_active && wait_cycles < 30) begin
            @(negedge clk);
            wait_cycles++;
        end
        check(session_active && login_request_count == 2 &&
              login_accepted_count == 2,
              "reconnect handshake restores the session");

        send_control("H");
        check(heartbeat_count == 1,
              "Server Heartbeat is distinguished from client heartbeat");
        send_control("Q");
        check(unsupported_packet_count == 1,
              "unknown Soup packet type is counted and dropped");

        repeat (41) @(negedge clk);
        check(!session_active && watchdog_timeout_count == 1,
              "silent receive path expires fail-closed despite TX heartbeats");

        transport_connected = 1'b0;
        @(negedge clk);
        check(!login_ready && !session_active,
              "transport loss blocks login and trading");

        check(tx_unsequenced_count == 1 &&
              sequenced_packet_count == 2 &&
              sequence_parse_error_count == 0,
              "session, transmit, and sequence counters are exact");

        $display("Tests failed: %0d", failed);
        $finish;
    end
endmodule
`default_nettype wire
