`timescale 1ns/1ps
`default_nettype none
// Two 4KiB slaves. One outstanding write and read independently. W may arrive
// before AW; it is backpressured until the accepted AW selects its destination.
module ethernet_axil_split(
 input wire clk,reset,
 input wire [12:0] s_awaddr,input wire s_awvalid,output wire s_awready,
 input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
 output wire [1:0] s_bresp,output wire s_bvalid,input wire s_bready,
 input wire [12:0] s_araddr,input wire s_arvalid,output wire s_arready,
 output wire [31:0] s_rdata,output wire [1:0] s_rresp,output wire s_rvalid,input wire s_rready,
 output wire [11:0] m0_awaddr,output wire m0_awvalid,input wire m0_awready,
 output wire [31:0] m0_wdata,output wire [3:0] m0_wstrb,output wire m0_wvalid,input wire m0_wready,
 input wire [1:0] m0_bresp,input wire m0_bvalid,output wire m0_bready,
 output wire [11:0] m0_araddr,output wire m0_arvalid,input wire m0_arready,
 input wire [31:0] m0_rdata,input wire [1:0] m0_rresp,input wire m0_rvalid,output wire m0_rready,
 output wire [11:0] m1_awaddr,output wire m1_awvalid,input wire m1_awready,
 output wire [31:0] m1_wdata,output wire [3:0] m1_wstrb,output wire m1_wvalid,input wire m1_wready,
 input wire [1:0] m1_bresp,input wire m1_bvalid,output wire m1_bready,
 output wire [11:0] m1_araddr,output wire m1_arvalid,input wire m1_arready,
 input wire [31:0] m1_rdata,input wire [1:0] m1_rresp,input wire m1_rvalid,output wire m1_rready
);
 reg write_busy,write_sel,write_data_done,read_busy,read_sel;
 assign m0_awaddr=s_awaddr[11:0];assign m1_awaddr=s_awaddr[11:0];
 assign m0_awvalid=s_awvalid && !reset && !write_busy && !s_awaddr[12];
 assign m1_awvalid=s_awvalid && !reset && !write_busy && s_awaddr[12];
 assign s_awready=!reset && !write_busy && (s_awaddr[12]?m1_awready:m0_awready);
 assign m0_wdata=s_wdata;assign m1_wdata=s_wdata;assign m0_wstrb=s_wstrb;assign m1_wstrb=s_wstrb;
 assign m0_wvalid=s_wvalid && !reset && write_busy && !write_data_done && !write_sel;
 assign m1_wvalid=s_wvalid && !reset && write_busy && !write_data_done && write_sel;
 assign s_wready=!reset && write_busy && !write_data_done && (write_sel?m1_wready:m0_wready);
 assign s_bresp=write_sel?m1_bresp:m0_bresp;
 assign s_bvalid=!reset && write_busy && write_data_done && (write_sel?m1_bvalid:m0_bvalid);
 assign m0_bready=s_bready && !reset && write_busy && write_data_done && !write_sel;
 assign m1_bready=s_bready && !reset && write_busy && write_data_done && write_sel;
 assign m0_araddr=s_araddr[11:0];assign m1_araddr=s_araddr[11:0];
 assign m0_arvalid=s_arvalid && !reset && !read_busy && !s_araddr[12];
 assign m1_arvalid=s_arvalid && !reset && !read_busy && s_araddr[12];
 assign s_arready=!reset && !read_busy && (s_araddr[12]?m1_arready:m0_arready);
 assign s_rdata=read_sel?m1_rdata:m0_rdata;assign s_rresp=read_sel?m1_rresp:m0_rresp;
 assign s_rvalid=!reset && read_busy && (read_sel?m1_rvalid:m0_rvalid);
 assign m0_rready=s_rready && !reset && read_busy && !read_sel;
 assign m1_rready=s_rready && !reset && read_busy && read_sel;
 always @(posedge clk)begin
  if(reset)begin write_busy<=0;write_sel<=0;write_data_done<=0;read_busy<=0;read_sel<=0;end
  else begin
   if(s_awvalid && s_awready)begin write_busy<=1;write_sel<=s_awaddr[12];write_data_done<=0;end
   if(s_wvalid && s_wready)write_data_done<=1;
   if(s_bvalid && s_bready)begin write_busy<=0;write_data_done<=0;end
   if(s_arvalid && s_arready)begin read_busy<=1;read_sel<=s_araddr[12];end
   if(s_rvalid && s_rready)read_busy<=0;
  end
 end
endmodule
`default_nettype wire
