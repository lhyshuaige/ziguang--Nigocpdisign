`timescale 1ns/1ps
`default_nettype none
// Reset MUST be asserted at both ends for link loss/config changes. Each end
// releases synchronously. Descriptor: {payload_bytes16,source_port16,dest_port16,IP32}.
module ethernet_packet_cdc #(
    parameter integer S_WIDTH=32,M_WIDTH=8,DEPTH=4096,TIMEOUT_CYCLES=65536
)(
    input wire s_clk,s_reset,m_clk,m_reset,
    input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
    input wire [S_WIDTH-1:0] s_data,input wire [S_WIDTH/8-1:0] s_keep,
    input wire s_valid,output wire s_ready,input wire s_last,s_bad,
    output wire [79:0] m_desc,output wire m_desc_valid,input wire m_desc_ready,
    output wire [M_WIDTH-1:0] m_data,output wire [M_WIDTH/8-1:0] m_keep,
    output wire m_valid,input wire m_ready,output wire m_last,m_bad,
    output wire dropped,overflow
);
    wire [S_WIDTH-1:0] a_data;wire [S_WIDTH/8-1:0] a_keep;
    wire a_valid,a_ready,a_last,a_bad;
    wire [M_WIDTH-1:0] b_data;wire [M_WIDTH/8-1:0] b_keep;
    wire b_valid,b_ready,b_last,b_bad;
    ethernet_packet_record_tx #(.DATA_WIDTH(S_WIDTH),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_record(
        .clk(s_clk),.reset(s_reset),.s_desc(s_desc),.s_desc_valid(s_desc_valid),.s_desc_ready(s_desc_ready),
        .s_data(s_data),.s_keep(s_keep),.s_valid(s_valid),.s_ready(s_ready),.s_last(s_last),.s_bad(s_bad),
        .m_data(a_data),.m_keep(a_keep),.m_valid(a_valid),.m_ready(a_ready),.m_last(a_last),.m_bad(a_bad),.dropped(dropped));
    axis_async_fifo_adapter #(.DEPTH(DEPTH),.S_DATA_WIDTH(S_WIDTH),.S_KEEP_ENABLE(1),.S_KEEP_WIDTH(S_WIDTH/8),
        .M_DATA_WIDTH(M_WIDTH),.M_KEEP_ENABLE(1),.M_KEEP_WIDTH(M_WIDTH/8),
        .ID_ENABLE(0),.DEST_ENABLE(0),.USER_ENABLE(1),.USER_WIDTH(1),.FRAME_FIFO(1),
        .USER_BAD_FRAME_VALUE(1),.USER_BAD_FRAME_MASK(1),.DROP_OVERSIZE_FRAME(1),.DROP_BAD_FRAME(1),.DROP_WHEN_FULL(0)) u_fifo(
        .s_clk(s_clk),.s_rst(s_reset),.m_clk(m_clk),.m_rst(m_reset),
        .s_axis_tdata(a_data),.s_axis_tkeep(a_keep),.s_axis_tvalid(a_valid),.s_axis_tready(a_ready),
        .s_axis_tlast(a_last),.s_axis_tid(8'd0),.s_axis_tdest(8'd0),.s_axis_tuser(a_bad),
        .m_axis_tdata(b_data),.m_axis_tkeep(b_keep),.m_axis_tvalid(b_valid),.m_axis_tready(b_ready),
        .m_axis_tlast(b_last),.m_axis_tuser(b_bad),.s_pause_req(1'b0),.m_pause_req(1'b0),.s_status_overflow(overflow));
    ethernet_packet_record_rx #(.DATA_WIDTH(M_WIDTH)) u_unpack(
        .clk(m_clk),.reset(m_reset),.s_data(b_data),.s_keep(b_keep),.s_valid(b_valid),.s_ready(b_ready),.s_last(b_last),.s_bad(b_bad),
        .m_desc(m_desc),.m_desc_valid(m_desc_valid),.m_desc_ready(m_desc_ready),
        .m_data(m_data),.m_keep(m_keep),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),.m_bad(m_bad));
endmodule
`default_nettype wire
