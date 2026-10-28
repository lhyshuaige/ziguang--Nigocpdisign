`timescale 1ns/1ps
`default_nettype none
// Portable single-port 1Gb/s subsystem. DDR access is ONLY through existing DMA.
// sys_clk=100MHz, net_clk=125MHz, rx_clk=PHY clock. No SoC/CPU internals changed.
module ethernet_top(
 input wire sys_clk,sys_reset,net_clk,net_reset,rx_clk,rx_reset,
 input wire phy_ready,input wire [31:0] phy_info,phy_id,
 input wire [7:0] gmii_rxd,input wire gmii_rx_dv,gmii_rx_er,
 output wire [7:0] gmii_txd,output wire gmii_tx_en,gmii_tx_er,
 input wire [11:0] s_axil_awaddr,input wire s_axil_awvalid,output wire s_axil_awready,
 input wire [31:0] s_axil_wdata,input wire [3:0] s_axil_wstrb,input wire s_axil_wvalid,output wire s_axil_wready,
 output wire [1:0] s_axil_bresp,output wire s_axil_bvalid,input wire s_axil_bready,
 input wire [11:0] s_axil_araddr,input wire s_axil_arvalid,output wire s_axil_arready,
 output wire [31:0] s_axil_rdata,output wire [1:0] s_axil_rresp,output wire s_axil_rvalid,input wire s_axil_rready,
 output wire irq,ready,
 input wire [79:0] s_tx_desc,input wire s_tx_desc_valid,output wire s_tx_desc_ready,
 input wire [31:0] s_tx_tdata,input wire [3:0] s_tx_tkeep,input wire s_tx_tvalid,output wire s_tx_tready,input wire s_tx_tlast,s_tx_tuser,
 output wire [79:0] m_rx_desc,output wire m_rx_desc_valid,input wire m_rx_desc_ready,
 output wire [31:0] m_rx_tdata,output wire [3:0] m_rx_tkeep,output wire m_rx_tvalid,input wire m_rx_tready,output wire m_rx_tlast,m_rx_tuser
);
 wire enable,soft_reset,config_commit,config_busy,config_done,config_pending;
 wire [143:0] config_shadow,net_config;wire [15:0] control_port,data_port;
 wire [191:0] statistics;wire [7:0] events;
 reg [5:0] flush_timer;wire flush_request=!enable || !phy_ready || flush_timer!=0 || config_busy;
 wire sys_flush,net_flush,rx_flush;
 ethernet_reset_sync u_sys_flush(.clk(sys_clk),.async_reset(sys_reset || flush_request),.reset(sys_flush));
 ethernet_reset_sync u_net_flush(.clk(net_clk),.async_reset(net_reset || flush_request),.reset(net_flush));
 ethernet_reset_sync u_rx_flush(.clk(rx_clk),.async_reset(rx_reset || flush_request),.reset(rx_flush));
 assign ready=!sys_flush;
 always @(posedge sys_clk)begin
  if(sys_reset)flush_timer<=0;else if(soft_reset)flush_timer<=63;else if(flush_timer!=0)flush_timer<=flush_timer-1'b1;
 end
 reg [2:0] config_wait;
 always @(posedge net_clk)begin
  if(net_reset || !config_pending)config_wait<=0;else if(config_wait!=7)config_wait<=config_wait+1'b1;
 end
 ethernet_config_cdc u_config(.s_clk(sys_clk),.s_reset(sys_reset),.s_config(config_shadow),.commit(config_commit),
  .busy(config_busy),.done(config_done),.m_clk(net_clk),.m_reset(net_reset),.m_config(net_config),.pending(config_pending),.apply(config_wait==7));
 wire [79:0] cpu_tx_desc,cpu_rx_desc,arb_desc,net_tx_desc,net_rx_desc,host_rx_desc;
 wire cpu_tx_dv,cpu_tx_dr,cpu_rx_dv,cpu_rx_dr,arb_dv,arb_dr,net_tx_dv,net_tx_dr,net_rx_dv,net_rx_dr,host_rx_dv,host_rx_dr;
 wire [31:0] cpu_tx_data,cpu_rx_data,arb_data,host_rx_data;wire [3:0] cpu_tx_keep,cpu_rx_keep,arb_keep,host_rx_keep;
 wire cpu_tx_valid,cpu_tx_ready,cpu_tx_last,cpu_rx_valid,cpu_rx_ready,cpu_rx_last,arb_valid,arb_ready,arb_last,arb_bad;
 wire host_rx_valid,host_rx_ready,host_rx_last,host_rx_bad;
 wire [7:0] net_tx_data,net_rx_data;wire net_tx_valid,net_tx_ready,net_tx_last,net_tx_bad,net_rx_valid,net_rx_ready,net_rx_last,net_rx_bad;
 wire tx_record_drop,tx_record_overflow,rx_record_drop,rx_record_overflow,router_drop,control_drop,rx_packet_done;
 ethernet_regs u_regs(
  .clk(sys_clk),.reset(sys_reset),.flush(sys_flush),
  .s_awaddr(s_axil_awaddr),.s_awvalid(s_axil_awvalid),.s_awready(s_axil_awready),.s_wdata(s_axil_wdata),.s_wstrb(s_axil_wstrb),.s_wvalid(s_axil_wvalid),.s_wready(s_axil_wready),
  .s_bresp(s_axil_bresp),.s_bvalid(s_axil_bvalid),.s_bready(s_axil_bready),.s_araddr(s_axil_araddr),.s_arvalid(s_axil_arvalid),.s_arready(s_axil_arready),.s_rdata(s_axil_rdata),.s_rresp(s_axil_rresp),.s_rvalid(s_axil_rvalid),.s_rready(s_axil_rready),
  .enable(enable),.soft_reset(soft_reset),.config_shadow(config_shadow),.config_commit(config_commit),.config_busy(config_busy),.config_done(config_done),
  .control_port(control_port),.data_port(data_port),.phy_info(phy_info),.phy_id(phy_id),.statistics(statistics),.events(events),.mailbox_drop(control_drop),.irq(irq),
  .rx_desc(cpu_rx_desc),.rx_desc_valid(cpu_rx_dv),.rx_desc_ready(cpu_rx_dr),.rx_data(cpu_rx_data),.rx_keep(cpu_rx_keep),.rx_valid(cpu_rx_valid),.rx_ready(cpu_rx_ready),.rx_last(cpu_rx_last),
  .tx_desc(cpu_tx_desc),.tx_desc_valid(cpu_tx_dv),.tx_desc_ready(cpu_tx_dr),.tx_data(cpu_tx_data),.tx_keep(cpu_tx_keep),.tx_valid(cpu_tx_valid),.tx_ready(cpu_tx_ready),.tx_last(cpu_tx_last));
 ethernet_packet_arbiter u_tx_arb(.clk(sys_clk),.reset(sys_flush),
  .a_desc(s_tx_desc),.a_desc_valid(s_tx_desc_valid && ready),.a_desc_ready(s_tx_desc_ready),.a_data(s_tx_tdata),.a_keep(s_tx_tkeep),.a_valid(s_tx_tvalid),.a_ready(s_tx_tready),.a_last(s_tx_tlast),.a_bad(s_tx_tuser),
  .b_desc(cpu_tx_desc),.b_desc_valid(cpu_tx_dv),.b_desc_ready(cpu_tx_dr),.b_data(cpu_tx_data),.b_keep(cpu_tx_keep),.b_valid(cpu_tx_valid),.b_ready(cpu_tx_ready),.b_last(cpu_tx_last),.b_bad(1'b0),
  .m_desc(arb_desc),.m_desc_valid(arb_dv),.m_desc_ready(arb_dr),.m_data(arb_data),.m_keep(arb_keep),.m_valid(arb_valid),.m_ready(arb_ready),.m_last(arb_last),.m_bad(arb_bad));
 ethernet_packet_cdc u_tx_cdc(.s_clk(sys_clk),.s_reset(sys_flush),.m_clk(net_clk),.m_reset(net_flush),
  .s_desc(arb_desc),.s_desc_valid(arb_dv),.s_desc_ready(arb_dr),.s_data(arb_data),.s_keep(arb_keep),.s_valid(arb_valid),.s_ready(arb_ready),.s_last(arb_last),.s_bad(arb_bad),
  .m_desc(net_tx_desc),.m_desc_valid(net_tx_dv),.m_desc_ready(net_tx_dr),.m_data(net_tx_data),.m_keep(),.m_valid(net_tx_valid),.m_ready(net_tx_ready),.m_last(net_tx_last),.m_bad(net_tx_bad),.dropped(tx_record_drop),.overflow(tx_record_overflow));
 ethernet_packet_cdc #(.S_WIDTH(8),.M_WIDTH(32)) u_rx_cdc(.s_clk(net_clk),.s_reset(net_flush),.m_clk(sys_clk),.m_reset(sys_flush),
  .s_desc(net_rx_desc),.s_desc_valid(net_rx_dv),.s_desc_ready(net_rx_dr),.s_data(net_rx_data),.s_keep(1'b1),.s_valid(net_rx_valid),.s_ready(net_rx_ready),.s_last(net_rx_last),.s_bad(net_rx_bad),
  .m_desc(host_rx_desc),.m_desc_valid(host_rx_dv),.m_desc_ready(host_rx_dr),.m_data(host_rx_data),.m_keep(host_rx_keep),.m_valid(host_rx_valid),.m_ready(host_rx_ready),.m_last(host_rx_last),.m_bad(host_rx_bad),.dropped(rx_record_drop),.overflow(rx_record_overflow));
 ethernet_rx_router u_router(.clk(sys_clk),.reset(sys_flush),.control_port(control_port),.data_port(data_port),
  .s_desc(host_rx_desc),.s_desc_valid(host_rx_dv),.s_desc_ready(host_rx_dr),.s_data(host_rx_data),.s_keep(host_rx_keep),.s_valid(host_rx_valid),.s_ready(host_rx_ready),.s_last(host_rx_last),.s_bad(host_rx_bad),
  .cpu_desc(cpu_rx_desc),.cpu_desc_valid(cpu_rx_dv),.cpu_desc_ready(cpu_rx_dr),.cpu_data(cpu_rx_data),.cpu_keep(cpu_rx_keep),.cpu_valid(cpu_rx_valid),.cpu_ready(cpu_rx_ready),.cpu_last(cpu_rx_last),
  .dma_desc(m_rx_desc),.dma_desc_valid(m_rx_desc_valid),.dma_desc_ready(m_rx_desc_ready),.dma_data(m_rx_tdata),.dma_keep(m_rx_tkeep),.dma_valid(m_rx_tvalid),.dma_ready(m_rx_tready),.dma_last(m_rx_tlast),.dma_bad(m_rx_tuser),.dropped(router_drop),.control_dropped(control_drop),.packet_done(rx_packet_done));
 wire [7:0] mac_rx_data,mac_tx_data;wire mac_rx_keep,mac_rx_valid,mac_rx_ready,mac_rx_last,mac_rx_bad,mac_tx_valid,mac_tx_ready,mac_tx_last,mac_tx_bad;
 wire tx_underflow,tx_overflow,tx_bad,tx_good,rx_bad,rx_fcs,rx_overflow,rx_fifo_bad,rx_good,udp_rejected,arp_failed,ip_bad;
 ethernet_udp_stack u_stack(.clk(net_clk),.reset(net_flush),.local_mac(net_config[47:0]),.local_ip(net_config[79:48]),.gateway_ip(net_config[111:80]),.subnet_mask(net_config[143:112]),
  .s_eth_data(mac_rx_data),.s_eth_valid(mac_rx_valid),.s_eth_ready(mac_rx_ready),.s_eth_last(mac_rx_last),.s_eth_bad(mac_rx_bad),
  .m_eth_data(mac_tx_data),.m_eth_valid(mac_tx_valid),.m_eth_ready(mac_tx_ready),.m_eth_last(mac_tx_last),.m_eth_bad(mac_tx_bad),
  .s_desc(net_tx_desc),.s_desc_valid(net_tx_dv),.s_desc_ready(net_tx_dr),.s_data(net_tx_data),.s_valid(net_tx_valid),.s_ready(net_tx_ready),.s_last(net_tx_last),.s_bad(net_tx_bad),
  .m_desc(net_rx_desc),.m_desc_valid(net_rx_dv),.m_desc_ready(net_rx_dr),.m_data(net_rx_data),.m_valid(net_rx_valid),.m_ready(net_rx_ready),.m_last(net_rx_last),.m_bad(net_rx_bad),.rejected(udp_rejected),.arp_failed(arp_failed),.ip_bad(ip_bad));
 ethernet_mac_wrapper u_mac(.tx_clk(net_clk),.tx_reset(net_flush),.rx_clk(rx_clk),.rx_reset(rx_flush),.logic_clk(net_clk),.logic_reset(net_flush),.tx_enable(1'b1),.rx_enable(1'b1),
  .s_axis_tdata(mac_tx_data),.s_axis_tvalid(mac_tx_valid),.s_axis_tlast(mac_tx_last),.s_axis_tuser(mac_tx_bad),.s_axis_tready(mac_tx_ready),
  .m_axis_tdata(mac_rx_data),.m_axis_tkeep(mac_rx_keep),.m_axis_tvalid(mac_rx_valid),.m_axis_tlast(mac_rx_last),.m_axis_tuser(mac_rx_bad),.m_axis_tready(mac_rx_ready),
  .gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),.gmii_tx_er(gmii_tx_er),.gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),
  .tx_underflow(tx_underflow),.tx_overflow(tx_overflow),.tx_bad_frame(tx_bad),.tx_good_frame(tx_good),.rx_bad_frame(rx_bad),.rx_bad_fcs(rx_fcs),.rx_overflow(rx_overflow),.rx_fifo_bad_frame(rx_fifo_bad),.rx_good_frame(rx_good));
 ethernet_stats_cdc u_stats(.net_clk(net_clk),.net_reset(net_reset),.events({arp_failed,ip_bad,udp_rejected,rx_overflow,tx_good,rx_good}),.sys_clk(sys_clk),.sys_reset(sys_reset),.statistics(statistics));
 reg [191:0] previous_stats;reg previous_link;
 always @(posedge sys_clk)begin if(sys_reset)begin previous_stats<=0;previous_link<=0;end else begin previous_stats<=statistics;previous_link<=phy_ready;end end
 assign events={1'b0,1'b0,previous_link!=phy_ready,statistics[191:64]!=previous_stats[191:64],tx_record_drop || tx_record_overflow || router_drop,
                rx_packet_done,statistics[63:32]!=previous_stats[63:32],1'b0};
endmodule
`default_nettype wire
