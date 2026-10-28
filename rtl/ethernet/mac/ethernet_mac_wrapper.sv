`timescale 1ns/1ps
`default_nettype none
// Standard-MTU, no PTP/pause, complete frame FIFOs. Wire RX cannot backpressure.
// cfg enables must be stable in their MAC clock domains; link reset/config CDC
// is owned by the integration block, not sampled directly across domains here.
module ethernet_mac_wrapper #(
    parameter integer TX_FIFO_DEPTH=2048,
    parameter integer RX_FIFO_DEPTH=2048
)(
    input wire tx_clk,tx_reset,rx_clk,rx_reset,logic_clk,logic_reset,
    input wire tx_enable,rx_enable,
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,s_axis_tlast,s_axis_tuser,
    output wire s_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire m_axis_tkeep,m_axis_tvalid,m_axis_tlast,m_axis_tuser,
    input wire m_axis_tready,
    output wire [7:0] gmii_txd,
    output wire gmii_tx_en,gmii_tx_er,
    input wire [7:0] gmii_rxd,
    input wire gmii_rx_dv,gmii_rx_er,
    output wire tx_underflow,tx_overflow,tx_bad_frame,tx_good_frame,
    output wire rx_bad_frame,rx_bad_fcs,rx_overflow,rx_fifo_bad_frame,rx_good_frame
);
    eth_mac_1g_fifo #(.AXIS_DATA_WIDTH(8),.AXIS_KEEP_ENABLE(0),.AXIS_KEEP_WIDTH(1),
        .ENABLE_PADDING(1),.MIN_FRAME_LENGTH(64),
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH),.RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .TX_FRAME_FIFO(1),.TX_DROP_OVERSIZE_FRAME(1),.TX_DROP_BAD_FRAME(1),.TX_DROP_WHEN_FULL(0),
        .RX_FRAME_FIFO(1),.RX_DROP_OVERSIZE_FRAME(1),.RX_DROP_BAD_FRAME(1),.RX_DROP_WHEN_FULL(1)) u_mac (
        .tx_clk(tx_clk),.tx_rst(tx_reset),.rx_clk(rx_clk),.rx_rst(rx_reset),
        .logic_clk(logic_clk),.logic_rst(logic_reset),
        .tx_axis_tdata(s_axis_tdata),.tx_axis_tkeep(1'b1),.tx_axis_tvalid(s_axis_tvalid),
        .tx_axis_tready(s_axis_tready),.tx_axis_tlast(s_axis_tlast),.tx_axis_tuser(s_axis_tuser),
        .rx_axis_tdata(m_axis_tdata),.rx_axis_tkeep(m_axis_tkeep),.rx_axis_tvalid(m_axis_tvalid),
        .rx_axis_tready(m_axis_tready),.rx_axis_tlast(m_axis_tlast),.rx_axis_tuser(m_axis_tuser),
        .gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),.gmii_tx_er(gmii_tx_er),
        .gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),
        .rx_clk_enable(1'b1),.tx_clk_enable(1'b1),.rx_mii_select(1'b0),.tx_mii_select(1'b0),
        .tx_error_underflow(tx_underflow),.tx_fifo_overflow(tx_overflow),
        .tx_fifo_bad_frame(tx_bad_frame),.tx_fifo_good_frame(tx_good_frame),
        .rx_error_bad_frame(rx_bad_frame),.rx_error_bad_fcs(rx_bad_fcs),
        .rx_fifo_overflow(rx_overflow),.rx_fifo_bad_frame(rx_fifo_bad_frame),.rx_fifo_good_frame(rx_good_frame),
        .cfg_ifg(8'd12),.cfg_tx_enable(tx_enable),.cfg_rx_enable(rx_enable));
endmodule
`default_nettype wire
