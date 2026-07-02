`default_nettype none
// =============================================================================
// Module: market_parser_axis_register_slice
// =============================================================================
// One-deep ready/valid register slice for wide AXI4-Stream-like datapaths.
module market_parser_axis_register_slice #(
    parameter int DATA_WIDTH = 512,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  wire logic                  clk,
    input  wire logic                  rst,

    input  wire logic                  s_axis_tvalid,
    output logic                       s_axis_tready,
    input  wire logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire logic [KEEP_WIDTH-1:0] s_axis_tkeep,
    input  wire logic                  s_axis_tlast,
    input  wire logic                  s_axis_tuser_bad_frame,

    output logic                       m_axis_tvalid,
    input  wire logic                  m_axis_tready,
    output logic [DATA_WIDTH-1:0]      m_axis_tdata,
    output logic [KEEP_WIDTH-1:0]      m_axis_tkeep,
    output logic                       m_axis_tlast,
    output logic                       m_axis_tuser_bad_frame
);
    logic                  valid_r;
    logic [DATA_WIDTH-1:0] data_r;
    logic [KEEP_WIDTH-1:0] keep_r;
    logic                  last_r;
    logic                  bad_frame_r;

    assign s_axis_tready          = !valid_r || m_axis_tready;
    assign m_axis_tvalid          = valid_r;
    assign m_axis_tdata           = data_r;
    assign m_axis_tkeep           = keep_r;
    assign m_axis_tlast           = last_r;
    assign m_axis_tuser_bad_frame = bad_frame_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_r     <= 1'b0;
            data_r      <= '0;
            keep_r      <= '0;
            last_r      <= 1'b0;
            bad_frame_r <= 1'b0;
        end else if (s_axis_tready) begin
            valid_r <= s_axis_tvalid;
            if (s_axis_tvalid) begin
                data_r      <= s_axis_tdata;
                keep_r      <= s_axis_tkeep;
                last_r      <= s_axis_tlast;
                bad_frame_r <= s_axis_tuser_bad_frame;
            end
        end
    end

endmodule
`default_nettype wire
