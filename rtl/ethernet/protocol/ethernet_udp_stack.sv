`timescale 1ns/1ps
`default_nettype none
module ethernet_udp_stack(
 input wire clk,reset,
 input wire [47:0] local_mac,input wire [31:0] local_ip,gateway_ip,subnet_mask,
 input wire [7:0] s_eth_data,input wire s_eth_valid,output wire s_eth_ready,input wire s_eth_last,s_eth_bad,
 output wire [7:0] m_eth_data,output wire m_eth_valid,input wire m_eth_ready,output wire m_eth_last,m_eth_bad,
 input wire [79:0] s_desc,input wire s_desc_valid,output wire s_desc_ready,
 input wire [7:0] s_data,input wire s_valid,output wire s_ready,input wire s_last,s_bad,
 output wire [79:0] m_desc,output wire m_desc_valid,input wire m_desc_ready,
 output wire [7:0] m_data,output wire m_valid,input wire m_ready,output wire m_last,m_bad,
 output wire rejected,arp_failed,ip_bad
);
wire  s_eth_hdr_valid;
wire  s_eth_hdr_ready;
wire [47:0] s_eth_dest_mac;
wire [47:0] s_eth_src_mac;
wire [15:0] s_eth_type;
wire [7:0] s_eth_payload_axis_tdata;
wire  s_eth_payload_axis_tvalid;
wire  s_eth_payload_axis_tready;
wire  s_eth_payload_axis_tlast;
wire  s_eth_payload_axis_tuser;
wire  m_eth_hdr_valid;
wire  m_eth_hdr_ready;
wire [47:0] m_eth_dest_mac;
wire [47:0] m_eth_src_mac;
wire [15:0] m_eth_type;
wire [7:0] m_eth_payload_axis_tdata;
wire  m_eth_payload_axis_tvalid;
wire  m_eth_payload_axis_tready;
wire  m_eth_payload_axis_tlast;
wire  m_eth_payload_axis_tuser;
wire  s_ip_hdr_valid;
wire  s_ip_hdr_ready;
wire [5:0] s_ip_dscp;
wire [1:0] s_ip_ecn;
wire [15:0] s_ip_length;
wire [7:0] s_ip_ttl;
wire [7:0] s_ip_protocol;
wire [31:0] s_ip_source_ip;
wire [31:0] s_ip_dest_ip;
wire [7:0] s_ip_payload_axis_tdata;
wire  s_ip_payload_axis_tvalid;
wire  s_ip_payload_axis_tready;
wire  s_ip_payload_axis_tlast;
wire  s_ip_payload_axis_tuser;
wire  m_ip_hdr_valid;
wire  m_ip_hdr_ready;
wire [47:0] m_ip_eth_dest_mac;
wire [47:0] m_ip_eth_src_mac;
wire [15:0] m_ip_eth_type;
wire [3:0] m_ip_version;
wire [3:0] m_ip_ihl;
wire [5:0] m_ip_dscp;
wire [1:0] m_ip_ecn;
wire [15:0] m_ip_length;
wire [15:0] m_ip_identification;
wire [2:0] m_ip_flags;
wire [12:0] m_ip_fragment_offset;
wire [7:0] m_ip_ttl;
wire [7:0] m_ip_protocol;
wire [15:0] m_ip_header_checksum;
wire [31:0] m_ip_source_ip;
wire [31:0] m_ip_dest_ip;
wire [7:0] m_ip_payload_axis_tdata;
wire  m_ip_payload_axis_tvalid;
wire  m_ip_payload_axis_tready;
wire  m_ip_payload_axis_tlast;
wire  m_ip_payload_axis_tuser;
wire  s_udp_hdr_valid;
wire  s_udp_hdr_ready;
wire [5:0] s_udp_ip_dscp;
wire [1:0] s_udp_ip_ecn;
wire [7:0] s_udp_ip_ttl;
wire [31:0] s_udp_ip_source_ip;
wire [31:0] s_udp_ip_dest_ip;
wire [15:0] s_udp_source_port;
wire [15:0] s_udp_dest_port;
wire [15:0] s_udp_length;
wire [15:0] s_udp_checksum;
wire [7:0] s_udp_payload_axis_tdata;
wire  s_udp_payload_axis_tvalid;
wire  s_udp_payload_axis_tready;
wire  s_udp_payload_axis_tlast;
wire  s_udp_payload_axis_tuser;
wire  m_udp_hdr_valid;
wire  m_udp_hdr_ready;
wire [47:0] m_udp_eth_dest_mac;
wire [47:0] m_udp_eth_src_mac;
wire [15:0] m_udp_eth_type;
wire [3:0] m_udp_ip_version;
wire [3:0] m_udp_ip_ihl;
wire [5:0] m_udp_ip_dscp;
wire [1:0] m_udp_ip_ecn;
wire [15:0] m_udp_ip_length;
wire [15:0] m_udp_ip_identification;
wire [2:0] m_udp_ip_flags;
wire [12:0] m_udp_ip_fragment_offset;
wire [7:0] m_udp_ip_ttl;
wire [7:0] m_udp_ip_protocol;
wire [15:0] m_udp_ip_header_checksum;
wire [31:0] m_udp_ip_source_ip;
wire [31:0] m_udp_ip_dest_ip;
wire [15:0] m_udp_source_port;
wire [15:0] m_udp_dest_port;
wire [15:0] m_udp_length;
wire [15:0] m_udp_checksum;
wire [7:0] m_udp_payload_axis_tdata;
wire  m_udp_payload_axis_tvalid;
wire  m_udp_payload_axis_tready;
wire  m_udp_payload_axis_tlast;
wire  m_udp_payload_axis_tuser;
wire  ip_rx_busy;
wire  ip_tx_busy;
wire  udp_rx_busy;
wire  udp_tx_busy;
wire  ip_rx_error_header_early_termination;
wire  ip_rx_error_payload_early_termination;
wire  ip_rx_error_invalid_header;
wire  ip_rx_error_invalid_checksum;
wire  ip_tx_error_payload_early_termination;
wire  ip_tx_error_arp_failed;
wire  udp_rx_error_header_early_termination;
wire  udp_rx_error_payload_early_termination;
wire  udp_tx_error_payload_early_termination;
udp_complete #(.ARP_CACHE_ADDR_WIDTH(4),.ARP_REQUEST_RETRY_INTERVAL(1250000),.ARP_REQUEST_TIMEOUT(12500000)) u_protocol(
.clk(clk),
.rst(reset),
.s_eth_hdr_valid(s_eth_hdr_valid),
.s_eth_hdr_ready(s_eth_hdr_ready),
.s_eth_dest_mac(s_eth_dest_mac),
.s_eth_src_mac(s_eth_src_mac),
.s_eth_type(s_eth_type),
.s_eth_payload_axis_tdata(s_eth_payload_axis_tdata),
.s_eth_payload_axis_tvalid(s_eth_payload_axis_tvalid),
.s_eth_payload_axis_tready(s_eth_payload_axis_tready),
.s_eth_payload_axis_tlast(s_eth_payload_axis_tlast),
.s_eth_payload_axis_tuser(s_eth_payload_axis_tuser),
.m_eth_hdr_valid(m_eth_hdr_valid),
.m_eth_hdr_ready(m_eth_hdr_ready),
.m_eth_dest_mac(m_eth_dest_mac),
.m_eth_src_mac(m_eth_src_mac),
.m_eth_type(m_eth_type),
.m_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
.m_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
.m_eth_payload_axis_tready(m_eth_payload_axis_tready),
.m_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
.m_eth_payload_axis_tuser(m_eth_payload_axis_tuser),
.s_ip_hdr_valid(s_ip_hdr_valid),
.s_ip_hdr_ready(s_ip_hdr_ready),
.s_ip_dscp(s_ip_dscp),
.s_ip_ecn(s_ip_ecn),
.s_ip_length(s_ip_length),
.s_ip_ttl(s_ip_ttl),
.s_ip_protocol(s_ip_protocol),
.s_ip_source_ip(s_ip_source_ip),
.s_ip_dest_ip(s_ip_dest_ip),
.s_ip_payload_axis_tdata(s_ip_payload_axis_tdata),
.s_ip_payload_axis_tvalid(s_ip_payload_axis_tvalid),
.s_ip_payload_axis_tready(s_ip_payload_axis_tready),
.s_ip_payload_axis_tlast(s_ip_payload_axis_tlast),
.s_ip_payload_axis_tuser(s_ip_payload_axis_tuser),
.m_ip_hdr_valid(m_ip_hdr_valid),
.m_ip_hdr_ready(m_ip_hdr_ready),
.m_ip_eth_dest_mac(m_ip_eth_dest_mac),
.m_ip_eth_src_mac(m_ip_eth_src_mac),
.m_ip_eth_type(m_ip_eth_type),
.m_ip_version(m_ip_version),
.m_ip_ihl(m_ip_ihl),
.m_ip_dscp(m_ip_dscp),
.m_ip_ecn(m_ip_ecn),
.m_ip_length(m_ip_length),
.m_ip_identification(m_ip_identification),
.m_ip_flags(m_ip_flags),
.m_ip_fragment_offset(m_ip_fragment_offset),
.m_ip_ttl(m_ip_ttl),
.m_ip_protocol(m_ip_protocol),
.m_ip_header_checksum(m_ip_header_checksum),
.m_ip_source_ip(m_ip_source_ip),
.m_ip_dest_ip(m_ip_dest_ip),
.m_ip_payload_axis_tdata(m_ip_payload_axis_tdata),
.m_ip_payload_axis_tvalid(m_ip_payload_axis_tvalid),
.m_ip_payload_axis_tready(m_ip_payload_axis_tready),
.m_ip_payload_axis_tlast(m_ip_payload_axis_tlast),
.m_ip_payload_axis_tuser(m_ip_payload_axis_tuser),
.s_udp_hdr_valid(s_udp_hdr_valid),
.s_udp_hdr_ready(s_udp_hdr_ready),
.s_udp_ip_dscp(s_udp_ip_dscp),
.s_udp_ip_ecn(s_udp_ip_ecn),
.s_udp_ip_ttl(s_udp_ip_ttl),
.s_udp_ip_source_ip(s_udp_ip_source_ip),
.s_udp_ip_dest_ip(s_udp_ip_dest_ip),
.s_udp_source_port(s_udp_source_port),
.s_udp_dest_port(s_udp_dest_port),
.s_udp_length(s_udp_length),
.s_udp_checksum(s_udp_checksum),
.s_udp_payload_axis_tdata(s_udp_payload_axis_tdata),
.s_udp_payload_axis_tvalid(s_udp_payload_axis_tvalid),
.s_udp_payload_axis_tready(s_udp_payload_axis_tready),
.s_udp_payload_axis_tlast(s_udp_payload_axis_tlast),
.s_udp_payload_axis_tuser(s_udp_payload_axis_tuser),
.m_udp_hdr_valid(m_udp_hdr_valid),
.m_udp_hdr_ready(m_udp_hdr_ready),
.m_udp_eth_dest_mac(m_udp_eth_dest_mac),
.m_udp_eth_src_mac(m_udp_eth_src_mac),
.m_udp_eth_type(m_udp_eth_type),
.m_udp_ip_version(m_udp_ip_version),
.m_udp_ip_ihl(m_udp_ip_ihl),
.m_udp_ip_dscp(m_udp_ip_dscp),
.m_udp_ip_ecn(m_udp_ip_ecn),
.m_udp_ip_length(m_udp_ip_length),
.m_udp_ip_identification(m_udp_ip_identification),
.m_udp_ip_flags(m_udp_ip_flags),
.m_udp_ip_fragment_offset(m_udp_ip_fragment_offset),
.m_udp_ip_ttl(m_udp_ip_ttl),
.m_udp_ip_protocol(m_udp_ip_protocol),
.m_udp_ip_header_checksum(m_udp_ip_header_checksum),
.m_udp_ip_source_ip(m_udp_ip_source_ip),
.m_udp_ip_dest_ip(m_udp_ip_dest_ip),
.m_udp_source_port(m_udp_source_port),
.m_udp_dest_port(m_udp_dest_port),
.m_udp_length(m_udp_length),
.m_udp_checksum(m_udp_checksum),
.m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
.m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
.m_udp_payload_axis_tready(m_udp_payload_axis_tready),
.m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
.m_udp_payload_axis_tuser(m_udp_payload_axis_tuser),
.ip_rx_busy(ip_rx_busy),
.ip_tx_busy(ip_tx_busy),
.udp_rx_busy(udp_rx_busy),
.udp_tx_busy(udp_tx_busy),
.ip_rx_error_header_early_termination(ip_rx_error_header_early_termination),
.ip_rx_error_payload_early_termination(ip_rx_error_payload_early_termination),
.ip_rx_error_invalid_header(ip_rx_error_invalid_header),
.ip_rx_error_invalid_checksum(ip_rx_error_invalid_checksum),
.ip_tx_error_payload_early_termination(ip_tx_error_payload_early_termination),
.ip_tx_error_arp_failed(ip_tx_error_arp_failed),
.udp_rx_error_header_early_termination(udp_rx_error_header_early_termination),
.udp_rx_error_payload_early_termination(udp_rx_error_payload_early_termination),
.udp_tx_error_payload_early_termination(udp_tx_error_payload_early_termination),
.local_mac(local_mac),
.local_ip(local_ip),
.gateway_ip(gateway_ip),
.subnet_mask(subnet_mask),
.clear_arp_cache(1'b0));
eth_axis_rx u_eth_axis_rx(
.clk(clk),
.rst(reset),
.s_axis_tdata(s_eth_data),
.s_axis_tkeep(1'b1),
.s_axis_tvalid(s_eth_valid),
.s_axis_tready(s_eth_ready),
.s_axis_tlast(s_eth_last),
.s_axis_tuser(s_eth_bad),
.m_eth_hdr_valid(s_eth_hdr_valid),
.m_eth_hdr_ready(s_eth_hdr_ready),
.m_eth_dest_mac(s_eth_dest_mac),
.m_eth_src_mac(s_eth_src_mac),
.m_eth_type(s_eth_type),
.m_eth_payload_axis_tdata(s_eth_payload_axis_tdata),
.m_eth_payload_axis_tkeep(),
.m_eth_payload_axis_tvalid(s_eth_payload_axis_tvalid),
.m_eth_payload_axis_tready(s_eth_payload_axis_tready),
.m_eth_payload_axis_tlast(s_eth_payload_axis_tlast),
.m_eth_payload_axis_tuser(s_eth_payload_axis_tuser),
.busy(),
.error_header_early_termination());
eth_axis_tx u_eth_axis_tx(
.clk(clk),
.rst(reset),
.s_eth_hdr_valid(m_eth_hdr_valid),
.s_eth_hdr_ready(m_eth_hdr_ready),
.s_eth_dest_mac(m_eth_dest_mac),
.s_eth_src_mac(m_eth_src_mac),
.s_eth_type(m_eth_type),
.s_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
.s_eth_payload_axis_tkeep(1'b1),
.s_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
.s_eth_payload_axis_tready(m_eth_payload_axis_tready),
.s_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
.s_eth_payload_axis_tuser(m_eth_payload_axis_tuser),
.m_axis_tdata(m_eth_data),
.m_axis_tkeep(),
.m_axis_tvalid(m_eth_valid),
.m_axis_tready(m_eth_ready),
.m_axis_tlast(m_eth_last),
.m_axis_tuser(m_eth_bad),
.busy());
assign s_ip_hdr_valid=1'b0;
assign s_ip_dscp=6'd0;
assign s_ip_ecn=2'd0;
assign s_ip_length=16'd0;
assign s_ip_ttl=8'd0;
assign s_ip_protocol=8'd0;
assign s_ip_source_ip=32'd0;
assign s_ip_dest_ip=32'd0;
assign s_ip_payload_axis_tdata=8'd0;
assign s_ip_payload_axis_tvalid=1'b0;
assign s_ip_payload_axis_tlast=1'b0;
assign s_ip_payload_axis_tuser=1'b0;
assign m_ip_hdr_ready=1'b1;
assign m_ip_payload_axis_tready=1'b1;
assign s_udp_hdr_valid=s_desc_valid;
assign s_desc_ready=s_udp_hdr_ready;
assign s_udp_ip_dscp=6'd0;
assign s_udp_ip_ecn=2'd0;
assign s_udp_ip_ttl=8'd64;
assign s_udp_ip_source_ip=local_ip;
assign s_udp_ip_dest_ip=s_desc[31:0];
assign s_udp_source_port=s_desc[63:48];
assign s_udp_dest_port=s_desc[47:32];
assign s_udp_length=s_desc[79:64]+16'd8;
assign s_udp_checksum=16'd0;
assign s_udp_payload_axis_tdata=s_data;
assign s_udp_payload_axis_tvalid=s_valid;
assign s_ready=s_udp_payload_axis_tready;
assign s_udp_payload_axis_tlast=s_last;
assign s_udp_payload_axis_tuser=s_bad;
assign arp_failed=ip_tx_error_arp_failed;
assign ip_bad=ip_rx_error_invalid_header || ip_rx_error_invalid_checksum || udp_rx_error_header_early_termination || udp_rx_error_payload_early_termination;
ethernet_udp_rx_guard u_guard(
 .clk(clk),.reset(reset),.local_ip(local_ip),.local_mac(local_mac),.hdr_valid(m_udp_hdr_valid),.hdr_ready(m_udp_hdr_ready),
 .dest_mac(m_udp_eth_dest_mac),.version(m_udp_ip_version),.ihl(m_udp_ip_ihl),.flags(m_udp_ip_flags),.fragment_offset(m_udp_ip_fragment_offset),
 .source_ip(m_udp_ip_source_ip),.dest_ip(m_udp_ip_dest_ip),.ip_length(m_udp_ip_length),.source_port(m_udp_source_port),.dest_port(m_udp_dest_port),.udp_length(m_udp_length),.checksum(m_udp_checksum),
 .s_data(m_udp_payload_axis_tdata),.s_valid(m_udp_payload_axis_tvalid),.s_ready(m_udp_payload_axis_tready),.s_last(m_udp_payload_axis_tlast),.s_bad(m_udp_payload_axis_tuser),
 .m_desc(m_desc),.m_desc_valid(m_desc_valid),.m_desc_ready(m_desc_ready),.m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),.m_bad(m_bad),.rejected(rejected));
endmodule
`default_nettype wire
