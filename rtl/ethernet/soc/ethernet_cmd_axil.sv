`timescale 1ns/1ps
`default_nettype none
// One native CPU peripheral command becomes one AXI-Lite transaction.
// AW and W complete independently. Native responses are one-cycle pulses.
module ethernet_cmd_axil(
 input wire clk,reset,cmd_valid,cmd_write,
 input wire [12:0] cmd_addr,input wire [31:0] cmd_wdata,input wire [3:0] cmd_wstrb,
 output wire cmd_ready,output reg rsp_valid,rsp_error,output reg [31:0] rsp_rdata,
 output reg [12:0] m_awaddr,output reg m_awvalid,input wire m_awready,
 output reg [31:0] m_wdata,output reg [3:0] m_wstrb,output reg m_wvalid,input wire m_wready,
 input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
 output reg [12:0] m_araddr,output reg m_arvalid,input wire m_arready,
 input wire [31:0] m_rdata,input wire [1:0] m_rresp,input wire m_rvalid,output wire m_rready
);
 localparam [1:0] IDLE=0,WRITE=1,READ=2;
 reg [1:0] state;
 assign cmd_ready=!reset && state==IDLE && !rsp_valid;
 assign m_bready=!reset && state==WRITE && !m_awvalid && !m_wvalid;
 assign m_rready=!reset && state==READ && !m_arvalid;
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;rsp_valid<=0;rsp_error<=0;rsp_rdata<=0;
   m_awaddr<=0;m_awvalid<=0;m_wdata<=0;m_wstrb<=0;m_wvalid<=0;m_araddr<=0;m_arvalid<=0;
  end else begin
   rsp_valid<=0;
   if(m_awvalid && m_awready)m_awvalid<=0;
   if(m_wvalid && m_wready)m_wvalid<=0;
   if(m_arvalid && m_arready)m_arvalid<=0;
   if(cmd_valid && cmd_ready)begin
    if(cmd_addr[1:0]!=0)begin rsp_valid<=1;rsp_error<=1;rsp_rdata<=0;end
    else if(cmd_write)begin
     m_awaddr<=cmd_addr;m_awvalid<=1;m_wdata<=cmd_wdata;m_wstrb<=cmd_wstrb;m_wvalid<=1;state<=WRITE;
    end else begin m_araddr<=cmd_addr;m_arvalid<=1;state<=READ;end
   end
   if(m_bvalid && m_bready)begin rsp_valid<=1;rsp_error<=m_bresp!=0;rsp_rdata<=0;state<=IDLE;end
   if(m_rvalid && m_rready)begin rsp_valid<=1;rsp_error<=m_rresp!=0;rsp_rdata<=m_rdata;state<=IDLE;end
  end
 end
endmodule
`default_nettype wire
