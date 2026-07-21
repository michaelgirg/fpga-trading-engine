`default_nettype none
// =============================================================================
// Module: market_parser_axi_lite_regs
// =============================================================================
// AXI-Lite readable control/status register block for the market parser.
//
// Counter clear is implemented with software-visible baselines. The datapath
// counters keep running, while register reads return raw_counter - baseline.
module market_parser_axi_lite_regs #(
    parameter int ADDR_WIDTH = 12,
    parameter logic [31:0] BUILD_ID = 32'h4d50_5253,
    parameter int EVENT_FIFO_DEPTH = 16,
    parameter logic [31:0] FEED_TIMEOUT_CYCLES_DEFAULT = 32'd0
) (
    input  wire logic                   clk,
    input  wire logic                   rst,

    input  wire logic [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire logic                   s_axi_awvalid,
    output logic                        s_axi_awready,
    input  wire logic [31:0]            s_axi_wdata,
    input  wire logic [ 3:0]            s_axi_wstrb,
    input  wire logic                   s_axi_wvalid,
    output logic                        s_axi_wready,
    output logic [ 1:0]                 s_axi_bresp,
    output logic                        s_axi_bvalid,
    input  wire logic                   s_axi_bready,
    input  wire logic [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire logic                   s_axi_arvalid,
    output logic                        s_axi_arready,
    output logic [31:0]                 s_axi_rdata,
    output logic [ 1:0]                 s_axi_rresp,
    output logic                        s_axi_rvalid,
    input  wire logic                   s_axi_rready,

    input  wire logic [31:0]            packet_count,
    input  wire logic [31:0]            descriptor_count,
    input  wire logic [31:0]            event_count,
    input  wire logic [31:0]            extractor_error_count,
    input  wire logic [31:0]            bad_frame_count,
    input  wire logic [15:0]            event_fifo_level,
    input  wire logic [31:0]            event_fifo_write_count,
    input  wire logic [31:0]            event_fifo_read_count,
    input  wire logic [31:0]            event_fifo_backpressure_count,
    input  wire logic                   ingress_backpressure_active,
    input  wire logic                   event_out_valid,
    input  wire logic [ 7:0]            error_flags_in,
    input  wire logic                   feed_healthy,
    input  wire logic                   feed_rebuilding,
    input  wire logic                   feed_rebuild_ready,
    input  wire logic [31:0]            feed_gap_count,
    input  wire logic [31:0]            feed_suppressed_event_count,
    input  wire logic [31:0]            feed_idle_cycles,
    input  wire logic [31:0]            feed_timeout_count,
    input  wire logic [31:0]            feed_activation_reject_count,
    input  wire logic [31:0]            feed_session_change_count,
    input  wire logic [31:0]            feed_end_of_session_count,
    input  wire logic [31:0]            cmac_axis_accepted_packet_count,
    input  wire logic [31:0]            cmac_axis_overflow_packet_count,
    input  wire logic [31:0]            cmac_axis_dropped_beat_count,
    input  wire logic [15:0]            cmac_axis_fifo_level,
    input  wire logic [15:0]            cmac_axis_fifo_high_watermark,

    output logic                        parser_enable,
    output logic                        clear_counters_pulse,
    output logic                        feed_recover_pulse,
    output logic                        feed_activate_pulse,
    output logic [31:0]                 feed_timeout_cycles_config
);
    localparam logic [11:0] REG_CONTROL          = 12'h000;
    localparam logic [11:0] REG_STATUS           = 12'h004;
    localparam logic [11:0] REG_BUILD_ID         = 12'h008;
    localparam logic [11:0] REG_PACKET_COUNT     = 12'h010;
    localparam logic [11:0] REG_DESCRIPTOR_COUNT = 12'h014;
    localparam logic [11:0] REG_EVENT_COUNT      = 12'h018;
    localparam logic [11:0] REG_ERROR_COUNT      = 12'h01c;
    localparam logic [11:0] REG_ERROR_FLAGS      = 12'h030;
    localparam logic [11:0] REG_BAD_FRAME_COUNT  = 12'h04c;
    localparam logic [11:0] REG_EVENT_FIFO_STAT  = 12'h080;
    localparam logic [11:0] REG_EVENT_FIFO_WR    = 12'h0a4;
    localparam logic [11:0] REG_EVENT_FIFO_RD    = 12'h0a8;
    localparam logic [11:0] REG_EVENT_FIFO_BP    = 12'h0ac;
    localparam logic [11:0] REG_FEED_STATUS      = 12'h0b0;
    localparam logic [11:0] REG_FEED_GAP_COUNT   = 12'h0b4;
    localparam logic [11:0] REG_FEED_SUPPRESSED  = 12'h0b8;
    localparam logic [11:0] REG_CMAC_AXIS_FIFO   = 12'h0bc;
    localparam logic [11:0] REG_CMAC_AXIS_ACCEPT = 12'h0c0;
    localparam logic [11:0] REG_CMAC_AXIS_OVFL   = 12'h0c4;
    localparam logic [11:0] REG_CMAC_AXIS_DROP   = 12'h0c8;
    localparam logic [11:0] REG_FEED_IDLE_CYCLES = 12'h0cc;
    localparam logic [11:0] REG_FEED_TIMEOUT_CFG = 12'h0d0;
    localparam logic [11:0] REG_FEED_TIMEOUT_CNT = 12'h0d4;
    localparam logic [11:0] REG_FEED_ACT_REJECT  = 12'h0d8;
    localparam logic [11:0] REG_FEED_SESSION_CHANGE = 12'h0dc;
    localparam logic [11:0] REG_FEED_END_OF_SESSION = 12'h0e0;

    logic [ADDR_WIDTH-1:0] awaddr_r;
    logic [31:0]           wdata_r;
    logic [ 3:0]           wstrb_r;
    logic                  aw_hold_r;
    logic                  w_hold_r;
    logic                  bvalid_r;
    logic                  rvalid_r;
    logic [31:0]           rdata_r;

    logic                  parser_enable_r;
    logic [ 7:0]           sticky_error_flags_r;
    logic [31:0]           packet_count_base_r;
    logic [31:0]           descriptor_count_base_r;
    logic [31:0]           event_count_base_r;
    logic [31:0]           extractor_error_count_base_r;
    logic [31:0]           bad_frame_count_base_r;
    logic [31:0]           event_fifo_write_count_base_r;
    logic [31:0]           event_fifo_read_count_base_r;
    logic [31:0]           event_fifo_backpressure_count_base_r;
    logic [31:0]           feed_gap_count_base_r;
    logic [31:0]           feed_suppressed_event_count_base_r;
    logic [31:0]           feed_timeout_count_base_r;
    logic [31:0]           feed_activation_reject_count_base_r;
    logic [31:0]           feed_session_change_count_base_r;
    logic [31:0]           feed_end_of_session_count_base_r;
    logic [31:0]           cmac_axis_accepted_packet_count_base_r;
    logic [31:0]           cmac_axis_overflow_packet_count_base_r;
    logic [31:0]           cmac_axis_dropped_beat_count_base_r;
    logic                  clear_counters_pulse_r;
    logic                  feed_recover_pulse_r;
    logic                  feed_activate_pulse_r;
    logic [31:0]           feed_timeout_cycles_r;

    assign s_axi_awready = !aw_hold_r && !bvalid_r;
    assign s_axi_wready  = !w_hold_r && !bvalid_r;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_arready = !rvalid_r;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;

    assign parser_enable       = parser_enable_r;
    assign clear_counters_pulse = clear_counters_pulse_r;
    assign feed_recover_pulse   = feed_recover_pulse_r;
    assign feed_activate_pulse  = feed_activate_pulse_r;
    assign feed_timeout_cycles_config = feed_timeout_cycles_r;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [ 3:0] strobe
    );
        logic [31:0] merged;
        merged = old_value;
        for (int i = 0; i < 4; i++) begin
            if (strobe[i]) merged[i*8 +: 8] = new_value[i*8 +: 8];
        end
        apply_wstrb = merged;
    endfunction

    function automatic logic [31:0] read_reg(input logic [ADDR_WIDTH-1:0] addr);
        logic [11:0] reg_addr;
        logic        fifo_empty;
        logic        fifo_full;

        reg_addr   = 12'(addr) & 12'hffc;
        fifo_empty = (event_fifo_level == 16'd0);
        fifo_full  = (int'(event_fifo_level) >= EVENT_FIFO_DEPTH);

        case (reg_addr)
            REG_CONTROL: begin
                read_reg = {28'd0, 3'b000, parser_enable_r};
            end
            REG_STATUS: begin
                read_reg = {
                    20'd0,
                    feed_end_of_session_count != feed_end_of_session_count_base_r,
                    feed_session_change_count != feed_session_change_count_base_r,
                    feed_activation_reject_count != feed_activation_reject_count_base_r,
                    feed_rebuilding,
                    feed_timeout_count != feed_timeout_count_base_r,
                    cmac_axis_overflow_packet_count != cmac_axis_overflow_packet_count_base_r,
                    feed_healthy,
                    event_out_valid,
                    fifo_full,
                    !fifo_empty,
                    ingress_backpressure_active,
                    parser_enable_r
                };
            end
            REG_BUILD_ID: begin
                read_reg = BUILD_ID;
            end
            REG_PACKET_COUNT: begin
                read_reg = packet_count - packet_count_base_r;
            end
            REG_DESCRIPTOR_COUNT: begin
                read_reg = descriptor_count - descriptor_count_base_r;
            end
            REG_EVENT_COUNT: begin
                read_reg = event_count - event_count_base_r;
            end
            REG_ERROR_COUNT: begin
                read_reg = extractor_error_count - extractor_error_count_base_r;
            end
            REG_ERROR_FLAGS: begin
                read_reg = {24'd0, sticky_error_flags_r};
            end
            REG_BAD_FRAME_COUNT: begin
                read_reg = bad_frame_count - bad_frame_count_base_r;
            end
            REG_EVENT_FIFO_STAT: begin
                read_reg = {event_fifo_level, 14'd0, fifo_full, fifo_empty};
            end
            REG_EVENT_FIFO_WR: begin
                read_reg = event_fifo_write_count - event_fifo_write_count_base_r;
            end
            REG_EVENT_FIFO_RD: begin
                read_reg = event_fifo_read_count - event_fifo_read_count_base_r;
            end
            REG_EVENT_FIFO_BP: begin
                read_reg = event_fifo_backpressure_count - event_fifo_backpressure_count_base_r;
            end
            REG_FEED_STATUS: begin
                read_reg = {
                    25'd0,
                    feed_end_of_session_count != feed_end_of_session_count_base_r,
                    feed_session_change_count != feed_session_change_count_base_r,
                    feed_activation_reject_count != feed_activation_reject_count_base_r,
                    feed_rebuild_ready,
                    feed_rebuilding,
                    feed_timeout_count != feed_timeout_count_base_r,
                    feed_healthy
                };
            end
            REG_FEED_GAP_COUNT: begin
                read_reg = feed_gap_count - feed_gap_count_base_r;
            end
            REG_FEED_SUPPRESSED: begin
                read_reg = feed_suppressed_event_count - feed_suppressed_event_count_base_r;
            end
            REG_CMAC_AXIS_FIFO: begin
                read_reg = {cmac_axis_fifo_high_watermark, cmac_axis_fifo_level};
            end
            REG_CMAC_AXIS_ACCEPT: begin
                read_reg = cmac_axis_accepted_packet_count - cmac_axis_accepted_packet_count_base_r;
            end
            REG_CMAC_AXIS_OVFL: begin
                read_reg = cmac_axis_overflow_packet_count - cmac_axis_overflow_packet_count_base_r;
            end
            REG_CMAC_AXIS_DROP: begin
                read_reg = cmac_axis_dropped_beat_count - cmac_axis_dropped_beat_count_base_r;
            end
            REG_FEED_IDLE_CYCLES: begin
                read_reg = feed_idle_cycles;
            end
            REG_FEED_TIMEOUT_CFG: begin
                read_reg = feed_timeout_cycles_r;
            end
            REG_FEED_TIMEOUT_CNT: begin
                read_reg = feed_timeout_count - feed_timeout_count_base_r;
            end
            REG_FEED_ACT_REJECT: begin
                read_reg = feed_activation_reject_count -
                           feed_activation_reject_count_base_r;
            end
            REG_FEED_SESSION_CHANGE: begin
                read_reg = feed_session_change_count - feed_session_change_count_base_r;
            end
            REG_FEED_END_OF_SESSION: begin
                read_reg = feed_end_of_session_count - feed_end_of_session_count_base_r;
            end
            default: begin
                read_reg = 32'h0000_0000;
            end
        endcase
    endfunction

    always_ff @(posedge clk) begin
        logic [11:0] write_addr;
        logic [31:0] control_next;
        logic [ 7:0] sticky_next;
        logic        write_fire;
        logic        do_clear;
        logic        do_feed_recover;
        logic        do_feed_activate;

        if (rst) begin
            awaddr_r                              <= '0;
            wdata_r                               <= '0;
            wstrb_r                               <= '0;
            aw_hold_r                             <= 1'b0;
            w_hold_r                              <= 1'b0;
            bvalid_r                              <= 1'b0;
            rvalid_r                              <= 1'b0;
            rdata_r                               <= '0;
            parser_enable_r                       <= 1'b1;
            sticky_error_flags_r                  <= '0;
            packet_count_base_r                   <= '0;
            descriptor_count_base_r               <= '0;
            event_count_base_r                    <= '0;
            extractor_error_count_base_r          <= '0;
            bad_frame_count_base_r                <= '0;
            event_fifo_write_count_base_r         <= '0;
            event_fifo_read_count_base_r          <= '0;
            event_fifo_backpressure_count_base_r  <= '0;
            feed_gap_count_base_r                 <= '0;
            feed_suppressed_event_count_base_r    <= '0;
            feed_timeout_count_base_r             <= '0;
            feed_activation_reject_count_base_r   <= '0;
            feed_session_change_count_base_r      <= '0;
            feed_end_of_session_count_base_r      <= '0;
            cmac_axis_accepted_packet_count_base_r <= '0;
            cmac_axis_overflow_packet_count_base_r <= '0;
            cmac_axis_dropped_beat_count_base_r    <= '0;
            clear_counters_pulse_r                <= 1'b0;
            feed_recover_pulse_r                  <= 1'b0;
            feed_activate_pulse_r                 <= 1'b0;
            feed_timeout_cycles_r                 <= FEED_TIMEOUT_CYCLES_DEFAULT;
        end else begin
            write_fire = aw_hold_r && w_hold_r && !bvalid_r;
            do_clear   = 1'b0;
            do_feed_recover = 1'b0;
            do_feed_activate = 1'b0;
            sticky_next = sticky_error_flags_r | error_flags_in;
            clear_counters_pulse_r <= 1'b0;
            feed_recover_pulse_r   <= 1'b0;
            feed_activate_pulse_r  <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_r  <= s_axi_awaddr;
                aw_hold_r <= 1'b1;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                wdata_r  <= s_axi_wdata;
                wstrb_r  <= s_axi_wstrb;
                w_hold_r <= 1'b1;
            end

            if (write_fire) begin
                write_addr = 12'(awaddr_r) & 12'hffc;
                if (write_addr == REG_CONTROL) begin
                    control_next = apply_wstrb({28'd0, 3'b000, parser_enable_r}, wdata_r, wstrb_r);
                    parser_enable_r <= control_next[0];
                    do_clear = control_next[1];
                    do_feed_recover = control_next[2];
                    do_feed_activate = control_next[3];
                end else if (write_addr == REG_ERROR_FLAGS) begin
                    sticky_next = sticky_next & ~wdata_r[7:0];
                end else if (write_addr == REG_FEED_TIMEOUT_CFG) begin
                    feed_timeout_cycles_r <= apply_wstrb(
                        feed_timeout_cycles_r,
                        wdata_r,
                        wstrb_r
                    );
                end

                aw_hold_r <= 1'b0;
                w_hold_r  <= 1'b0;
                bvalid_r  <= 1'b1;
            end

            if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                rdata_r  <= read_reg(s_axi_araddr);
                rvalid_r <= 1'b1;
            end else if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end

            if (do_clear) begin
                packet_count_base_r                  <= packet_count;
                descriptor_count_base_r              <= descriptor_count;
                event_count_base_r                   <= event_count;
                extractor_error_count_base_r         <= extractor_error_count;
                bad_frame_count_base_r               <= bad_frame_count;
                event_fifo_write_count_base_r        <= event_fifo_write_count;
                event_fifo_read_count_base_r         <= event_fifo_read_count;
                event_fifo_backpressure_count_base_r <= event_fifo_backpressure_count;
                feed_gap_count_base_r                 <= feed_gap_count;
                feed_suppressed_event_count_base_r    <= feed_suppressed_event_count;
                feed_timeout_count_base_r             <= feed_timeout_count;
                feed_activation_reject_count_base_r   <= feed_activation_reject_count;
                feed_session_change_count_base_r      <= feed_session_change_count;
                feed_end_of_session_count_base_r      <= feed_end_of_session_count;
                cmac_axis_accepted_packet_count_base_r <= cmac_axis_accepted_packet_count;
                cmac_axis_overflow_packet_count_base_r <= cmac_axis_overflow_packet_count;
                cmac_axis_dropped_beat_count_base_r    <= cmac_axis_dropped_beat_count;
                sticky_error_flags_r                 <= '0;
                clear_counters_pulse_r               <= 1'b1;
            end else begin
                sticky_error_flags_r <= sticky_next;
            end

            if (do_feed_recover) begin
                feed_recover_pulse_r <= 1'b1;
            end
            if (do_feed_activate) begin
                feed_activate_pulse_r <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
