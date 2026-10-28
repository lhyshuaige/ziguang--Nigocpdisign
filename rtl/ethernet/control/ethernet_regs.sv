`timescale 1ns/1ps
`default_nettype none
// AXI-Lite 32-bit CSR and two 256-byte control mailboxes. Never a CPU image path.
module ethernet_regs(
 input wire clk,reset,flush,
 input wire [11:0] s_awaddr,input wire s_awvalid,output wire s_awready,
 input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
 output reg [1:0] s_bresp,output reg s_bvalid,input wire s_bready,
 input wire [11:0] s_araddr,input wire s_arvalid,output wire s_arready,
 output reg [31:0] s_rdata,output reg [1:0] s_rresp,output reg s_rvalid,input wire s_rready,
 output reg enable,output reg soft_reset,output reg [143:0] config_shadow,
 output reg config_commit,input wire config_busy,config_done,
 output reg [15:0] control_port,data_port,
 input wire [31:0] phy_info,phy_id,input wire [191:0] statistics,
 input wire [7:0] events,input wire mailbox_drop,output wire irq,
 input wire [79:0] rx_desc,input wire rx_desc_valid,output wire rx_desc_ready,
 input wire [31:0] rx_data,input wire [3:0] rx_keep,input wire rx_valid,output wire rx_ready,input wire rx_last,
 output wire [79:0] tx_desc,output wire tx_desc_valid,input wire tx_desc_ready,
 output wire [31:0] tx_data,output wire [3:0] tx_keep,output wire tx_valid,input wire tx_ready,output wire tx_last
);
 reg aw_pending,w_pending;reg [11:0] aw;reg [31:0] wd;reg [3:0] ws;
 wire [5:0] a24_tx_write_addr_source=aw[7:2];
  wire [(6)-1:0] a24_tx_write_addr;
  genvar a24_tx_addr_bit;
  generate for(a24_tx_addr_bit=0;a24_tx_addr_bit<(6);a24_tx_addr_bit=a24_tx_addr_bit+1)begin:g_a24_tx_addr
    if(a24_tx_addr_bit==3)begin:g_pad
      ethernet_addr_micro_hold_pad #(.STAGES(4)) timingHoldA21_pad(.data_in(a24_tx_write_addr_source[a24_tx_addr_bit]),.data_out(a24_tx_write_addr[a24_tx_addr_bit]));
    end else assign a24_tx_write_addr[a24_tx_addr_bit]=a24_tx_write_addr_source[a24_tx_addr_bit];
  end endgenerate
 reg read_pending;reg [1:0] read_memory;
 reg [7:0] irq_pending,irq_mask;reg [31:0] tx_ip,tx_ports,tx_length;
 reg [31:0] tx_mem[0:63],rx_mem[0:63];reg [79:0] tx_header,rx_header;
 reg [1:0] tx_state;reg [6:0] tx_index,rx_index;reg [15:0] tx_remaining;
 reg rx_full,rx_receiving;reg [31:0] mailbox_drops;
 wire write_fire=aw_pending && w_pending && !s_bvalid;
 wire clear_irq=write_fire && aw==12'h00c;
 wire [7:0] clear_bits=clear_irq && ws[0]?wd[7:0]:8'd0;
 wire rx_complete=rx_valid && rx_ready && rx_last;
 assign irq=|(irq_pending & irq_mask);
 assign s_awready=!aw_pending;assign s_wready=!w_pending;assign s_arready=!s_rvalid && !read_pending;
 assign rx_desc_ready=!rx_full && !rx_receiving;assign rx_ready=rx_receiving;
 assign tx_desc=tx_header;assign tx_desc_valid=tx_state==1;
 assign tx_valid=tx_state==2;assign tx_data=tx_mem[tx_index[5:0]];
 assign tx_keep=tx_remaining>=4?4'hf:tx_remaining==3?4'h7:tx_remaining==2?4'h3:4'h1;
 assign tx_last=tx_remaining<=4;
 function [31:0] merge;
  input [31:0] old_value,new_value;input [3:0] strobe;integer b;
  begin for(b=0;b<4;b=b+1)merge[b*8+:8]=strobe[b]?new_value[b*8+:8]:old_value[b*8+:8];end
 endfunction
 // Explicit memory ports keep the broad CSR mux outside RAM-read inference.
 // Byte writes avoid a third TX RAM read port for read-modify-write.
 wire accept_read=s_arvalid && s_arready;
 wire read_tx=accept_read && s_araddr>=12'h200 && s_araddr<12'h300 && s_araddr[1:0]==0;
 wire read_rx=accept_read && s_araddr>=12'h300 && s_araddr<12'h400 && s_araddr[1:0]==0;
 wire write_tx=write_fire && aw>=12'h200 && aw<12'h300 && aw[1:0]==0 && tx_state==0;
 reg [31:0] tx_read_data,rx_read_data;
 integer byte_lane;
 always @(posedge clk)begin
  if(!reset && write_tx)begin
   for(byte_lane=0;byte_lane<4;byte_lane=byte_lane+1)
    if(ws[byte_lane])tx_mem[a24_tx_write_addr][byte_lane*8+:8]<=wd[byte_lane*8+:8];
  end
  if(!reset && rx_valid && rx_ready && rx_index<64)rx_mem[rx_index[5:0]]<=rx_data;
  if(read_tx)tx_read_data<=tx_mem[s_araddr[7:2]];
  if(read_rx)rx_read_data<=rx_mem[s_araddr[7:2]];
 end
 reg [31:0] read_value;reg read_ok;
 always @* begin
  read_ok=s_araddr[1:0]==0;read_value=0;
  case(s_araddr)
   12'h000:read_value=32'h4e455431;
   12'h004:read_value={31'd0,enable};
   12'h008:read_value={23'd0,config_busy,3'd0,!flush,phy_info[0],tx_state!=0,rx_full,enable};
   12'h00c:read_value={24'd0,irq_pending};12'h010:read_value={24'd0,irq_mask};
   12'h014:read_value=phy_id;
   12'h018:read_value=phy_info;
   12'h020:read_value=config_shadow[31:0];12'h024:read_value={16'd0,config_shadow[47:32]};
   12'h028:read_value=config_shadow[79:48];12'h02c:read_value=config_shadow[143:112];12'h030:read_value=config_shadow[111:80];
   12'h038:read_value={control_port,data_port};12'h03c:read_value={31'd0,config_busy};
   12'h080:read_value=statistics[31:0];12'h084:read_value=statistics[63:32];12'h088:read_value=statistics[95:64];
   12'h08c:read_value=statistics[127:96];12'h090:read_value=statistics[159:128];12'h094:read_value=statistics[191:160];
   12'h100:read_value={30'd0,rx_receiving,rx_full};12'h104:read_value=rx_header[31:0];
   12'h108:read_value=rx_header[63:32];12'h10c:read_value={16'd0,rx_header[79:64]};
   12'h110:read_value=mailbox_drops;
   12'h140:read_value=tx_length;12'h144:read_value=tx_ip;12'h148:read_value=tx_ports;12'h14c:read_value={30'd0,tx_state};
   default:if(!(s_araddr>=12'h200 && s_araddr<12'h400))read_ok=0;
  endcase
 end
 always @(posedge clk)begin
  if(reset)begin
   aw_pending<=0;w_pending<=0;aw<=0;wd<=0;ws<=0;s_bvalid<=0;s_bresp<=0;s_rvalid<=0;s_rdata<=0;s_rresp<=0;read_pending<=0;read_memory<=0;
   enable<=0;soft_reset<=0;config_commit<=0;config_shadow<={32'hffffff00,32'hc0a80101,32'hc0a80132,48'h020000000032};
   control_port<=5001;data_port<=5000;irq_pending<=0;irq_mask<=0;
   tx_ip<=32'hc0a80164;tx_ports<={16'd5001,16'd5001};tx_length<=0;tx_state<=0;tx_index<=0;tx_remaining<=0;tx_header<=0;
   rx_full<=0;rx_receiving<=0;rx_index<=0;rx_header<=0;mailbox_drops<=0;
  end else begin
   soft_reset<=0;config_commit<=0;
   if(mailbox_drop)mailbox_drops<=mailbox_drops+1'b1;
   irq_pending<=(irq_pending & ~clear_bits) | events | {1'b0,config_done,5'd0,rx_complete};
   if(s_awvalid && s_awready)begin aw<=s_awaddr;aw_pending<=1;end
   if(s_wvalid && s_wready)begin wd<=s_wdata;ws<=s_wstrb;w_pending<=1;end
   if(s_bvalid && s_bready)s_bvalid<=0;
   if(s_rvalid && s_rready)s_rvalid<=0;
   if(accept_read)begin
    read_pending<=1;read_memory<=read_rx?2'd2:read_tx?2'd1:2'd0;
    s_rdata<=read_value;s_rresp<=read_ok?0:2;
   end
   if(read_pending)begin
    read_pending<=0;s_rvalid<=1;
    if(read_memory==2)s_rdata<=rx_read_data;else if(read_memory==1)s_rdata<=tx_read_data;
   end
   if(write_fire)begin
    aw_pending<=0;w_pending<=0;s_bvalid<=1;s_bresp<=0;
    if(aw[1:0]!=0)s_bresp<=2;
    else case(aw)
     12'h004:if(ws[0])begin enable<=wd[0];soft_reset<=wd[1];end
     12'h00c:begin end
     12'h010:if(ws[0])irq_mask<=wd[7:0];
     12'h020:config_shadow[31:0]<=merge(config_shadow[31:0],wd,ws);
     12'h024:begin if(ws[0])config_shadow[39:32]<=wd[7:0];if(ws[1])config_shadow[47:40]<=wd[15:8];end
     12'h028:config_shadow[79:48]<=merge(config_shadow[79:48],wd,ws);
     12'h02c:config_shadow[143:112]<=merge(config_shadow[143:112],wd,ws);
     12'h030:config_shadow[111:80]<=merge(config_shadow[111:80],wd,ws);
     12'h038:if(!enable)begin
        if(ws[0])data_port[7:0]<=wd[7:0];if(ws[1])data_port[15:8]<=wd[15:8];
        if(ws[2])control_port[7:0]<=wd[23:16];if(ws[3])control_port[15:8]<=wd[31:24];
       end else s_bresp<=2;
     12'h03c:if(ws[0] && wd[0])begin if(!config_busy)config_commit<=1;else s_bresp<=2;end
     12'h114:if(ws[0] && wd[0])rx_full<=0;
     12'h140:tx_length<=merge(tx_length,wd,ws);
     12'h144:tx_ip<=merge(tx_ip,wd,ws);
     12'h148:tx_ports<=merge(tx_ports,wd,ws);
     12'h14c:if(ws[0] && wd[0])begin
       if(tx_state==0 && tx_length>0 && tx_length<=256 && enable && !flush)begin
        tx_header<={tx_length[15:0],tx_ports,tx_ip};tx_state<=1;tx_index<=0;tx_remaining<=tx_length[15:0];
       end else s_bresp<=2;
     end
     default:if(!write_tx)s_bresp<=2;
    endcase
   end
   if(rx_desc_valid && rx_desc_ready)begin rx_header<=rx_desc;rx_receiving<=1;rx_index<=0;end
   if(rx_valid && rx_ready)begin
    rx_index<=rx_index+1'b1;
    if(rx_last)begin rx_receiving<=0;if(rx_index<64)rx_full<=1;else mailbox_drops<=mailbox_drops+1'b1;end
   end
   if(tx_state==1 && tx_desc_ready)tx_state<=2;
   if(tx_valid && tx_ready)begin
    if(tx_last)tx_state<=0;
    else begin tx_index<=tx_index+1'b1;tx_remaining<=tx_remaining-16'd4;end
   end
   if(flush)begin tx_state<=0;rx_receiving<=0;end
  end
 end
endmodule
`default_nettype wire

// An even number of kept LUT inversions is a cycle-neutral identity.
// Actual minimum delay must be checked in the routed fast-corner STA.
module ethernet_addr_micro_hold_pad #(parameter WIDTH=1, STAGES=2)(
  input wire [WIDTH-1:0] data_in, output wire [WIDTH-1:0] data_out);
  (* syn_keep=1 *) wire [WIDTH*(STAGES+1)-1:0] chain;
  assign chain[0+:WIDTH]=data_in;
  assign data_out=chain[WIDTH*STAGES+:WIDTH];
  genvar stage,bit_index;
  generate for(stage=0;stage<STAGES;stage=stage+1)begin:delay_stage
    for(bit_index=0;bit_index<WIDTH;bit_index=bit_index+1)begin:delay_bit
      (* syn_keep=1,syn_preserve=1 *) GTP_LUT1 #(.INIT(2'b01)) invert(
        .I0(chain[stage*WIDTH+bit_index]),.Z(chain[(stage+1)*WIDTH+bit_index]));
    end
  end endgenerate
endmodule
