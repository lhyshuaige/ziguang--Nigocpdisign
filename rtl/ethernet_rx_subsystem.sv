`timescale 1ns/1ps
`default_nettype none
// Optional sys100 application endpoint. Ethernet and existing DMA remain external.
module ethernet_rx_subsystem #(parameter TIMEOUT_CYCLES=10000000)(
 input wire clk,reset,network_ready,
 input wire [11:0] s_awaddr,input wire s_awvalid,output wire s_awready,
 input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
 output wire [1:0] s_bresp,output wire s_bvalid,input wire s_bready,
 input wire [11:0] s_araddr,input wire s_arvalid,output wire s_arready,
 output wire [31:0] s_rdata,output wire [1:0] s_rresp,output wire s_rvalid,input wire s_rready,
 output wire irq,busy,dma_claim,input wire dma_grant,
 output wire dma_start,output wire [1:0] dma_mode,
 output wire [31:0] dma_base,dma_stride,output wire [15:0] dma_width,dma_height,
 input wire [31:0] dma_status,input wire dma_done_irq,dma_error_irq,
 input wire dma_awvalid,dma_awready,dma_wvalid,dma_bvalid,dma_bready,
 output wire [31:0] dma_tdata,output wire [3:0] dma_tkeep,
 output wire dma_tvalid,input wire dma_tready,output wire dma_tlast,dma_tuser,
 input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
 input wire [31:0] s_data,input wire [3:0] s_keep,input wire s_valid,
 output wire s_ready,input wire s_last,s_bad
);
 wire arm_valid,arm_ready,cancel,cfg_rgb565;
 wire [31:0] cfg_base0,cfg_base1,cfg_capacity,cfg_stride,cfg_id,cfg_peer_ip;
 wire [15:0] cfg_width,cfg_height;
 wire frame_done,frame_error,config_error,ownership_error,frame_valid,frame_slot,frame_rgb565;
 wire [3:0] buffer_states;
 wire [31:0] expected_offset,frames_ok,frames_bad,packets_ok,packets_bad,frame_base,frame_id,frame_stride;
 wire [15:0] frame_width,frame_height;
 wire frame_take,release_valid,release_slot;
 ethernet_rx_regs regs(
  .clk(clk),.reset(reset),.network_ready(network_ready),
  .s_awaddr(s_awaddr),.s_awvalid(s_awvalid),.s_awready(s_awready),.s_wdata(s_wdata),.s_wstrb(s_wstrb),
  .s_wvalid(s_wvalid),.s_wready(s_wready),.s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
  .s_araddr(s_araddr),.s_arvalid(s_arvalid),.s_arready(s_arready),.s_rdata(s_rdata),.s_rresp(s_rresp),.s_rvalid(s_rvalid),.s_rready(s_rready),
  .arm_valid(arm_valid),.arm_ready(arm_ready),.cancel(cancel),
  .cfg_base0(cfg_base0),.cfg_base1(cfg_base1),.cfg_capacity(cfg_capacity),.cfg_stride(cfg_stride),.cfg_id(cfg_id),.cfg_peer_ip(cfg_peer_ip),
  .cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_rgb565(cfg_rgb565),
  .busy(busy),.frame_done(frame_done),.frame_error(frame_error),.config_error(config_error),.ownership_error(ownership_error),
  .buffer_states(buffer_states),.expected_offset(expected_offset),.frames_ok(frames_ok),.frames_bad(frames_bad),.packets_ok(packets_ok),.packets_bad(packets_bad),
  .frame_valid(frame_valid),.frame_slot(frame_slot),.frame_base(frame_base),.frame_id(frame_id),.frame_stride(frame_stride),
  .frame_width(frame_width),.frame_height(frame_height),.frame_rgb565(frame_rgb565),
  .frame_take(frame_take),.release_valid(release_valid),.release_slot(release_slot),.irq(irq));
 ethernet_rx_frame_reassembler #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) rx(
  .clk(clk),.reset(reset),.network_ready(network_ready),.cancel(cancel),
  .arm_valid(arm_valid),.arm_ready(arm_ready),
  .cfg_base0(cfg_base0),.cfg_base1(cfg_base1),.cfg_capacity(cfg_capacity),.cfg_stride(cfg_stride),.cfg_id(cfg_id),.cfg_peer_ip(cfg_peer_ip),
  .cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_rgb565(cfg_rgb565),
  .dma_claim(dma_claim),.dma_grant(dma_grant),.dma_start(dma_start),.dma_mode(dma_mode),.dma_base(dma_base),.dma_stride(dma_stride),.dma_width(dma_width),.dma_height(dma_height),
  .dma_status(dma_status),.dma_done_irq(dma_done_irq),.dma_error_irq(dma_error_irq),
  .dma_awvalid(dma_awvalid),.dma_awready(dma_awready),.dma_wvalid(dma_wvalid),.dma_bvalid(dma_bvalid),.dma_bready(dma_bready),
  .dma_tdata(dma_tdata),.dma_tkeep(dma_tkeep),.dma_tvalid(dma_tvalid),.dma_tready(dma_tready),.dma_tlast(dma_tlast),.dma_tuser(dma_tuser),
  .s_desc(s_desc),.s_desc_valid(s_desc_valid),.s_desc_ready(s_desc_ready),.s_data(s_data),.s_keep(s_keep),.s_valid(s_valid),.s_ready(s_ready),.s_last(s_last),.s_bad(s_bad),
  .frame_valid(frame_valid),.frame_take(frame_take),.frame_slot(frame_slot),.frame_base(frame_base),.frame_id(frame_id),.frame_stride(frame_stride),
  .frame_width(frame_width),.frame_height(frame_height),.frame_rgb565(frame_rgb565),.release_valid(release_valid),.release_slot(release_slot),
  .busy(busy),.buffer_states(buffer_states),.frame_done(frame_done),.frame_error(frame_error),.config_error(config_error),
  .expected_offset(expected_offset),.frames_ok(frames_ok),.frames_bad(frames_bad),.packets_ok(packets_ok),.packets_bad(packets_bad),.ownership_error(ownership_error));
endmodule
`default_nettype wire
