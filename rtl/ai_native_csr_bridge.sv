`timescale 1ns/1ps
`default_nettype none
// One captured native command -> one local CSR handshake -> one response pulse.
// The captured request stays stable while the descriptor queue is full.
module ai_native_csr_bridge (
 input wire clk,reset,ddr_ready,
 input wire cmd_valid,cmd_write,input wire [11:0] cmd_addr,
 input wire [31:0] cmd_wdata,input wire [3:0] cmd_wstrb,
 output wire cmd_ready,output reg rsp_valid,rsp_error,output reg [31:0] rsp_rdata,
 output wire csr_valid,csr_write,output wire [7:0] csr_addr,
 output wire [31:0] csr_wdata,input wire csr_ready,csr_error,
 input wire [31:0] csr_rdata
);
 reg active,write_q;
 reg [11:0] addr_q;
 reg [31:0] data_q;
 reg [3:0] strb_q;
 wire aligned=addr_q[1:0]==0 && addr_q[11:8]==0;
 wire write_address=(addr_q<=12'h054) || addr_q==12'h058 ||
                    addr_q==12'h05c || addr_q==12'h060 || addr_q==12'h080;
 wire read_address=(addr_q<=12'h060) || addr_q==12'h084 || addr_q==12'h088 ||
                   (addr_q>=12'h0a0 && addr_q<=12'h0cc) || addr_q==12'h0d0;
 wire invalid_address=!aligned || (write_q?!write_address:!read_address);
 wire no_write=write_q && strb_q==0;
 wire [31:0] byte_mask={{8{strb_q[3]}},{8{strb_q[2]}},{8{strb_q[1]}},{8{strb_q[0]}}};
 wire [31:0] masked_data=data_q & byte_mask;
 wire submit=write_q && addr_q==12'h080 && masked_data[0];
 assign cmd_ready=!reset && !active && !rsp_valid;
 assign csr_valid=!reset && active && !invalid_address && !no_write && (!submit || ddr_ready);
 assign csr_write=write_q;
 assign csr_addr=addr_q[7:0];
 // Staging/indexed parameter data support byte writes; doorbell bits are W1.
 assign csr_wdata=addr_q==12'h080 ? masked_data : ((csr_rdata & ~byte_mask)|masked_data);
 always @(posedge clk)begin
  if(reset)begin
   active<=0;write_q<=0;addr_q<=0;data_q<=0;strb_q<=0;
   rsp_valid<=0;rsp_error<=0;rsp_rdata<=0;
  end else begin
   rsp_valid<=0;
   if(cmd_valid && cmd_ready)begin
    active<=1;write_q<=cmd_write;addr_q<=cmd_addr;data_q<=cmd_wdata;strb_q<=cmd_wstrb;
   end
   if(active && (invalid_address || no_write || (csr_valid && csr_ready)))begin
    active<=0;rsp_valid<=1;
    rsp_error<=invalid_address || (!no_write && csr_error);
    rsp_rdata<=write_q?32'd0:csr_rdata;
   end
  end
 end
endmodule
`default_nettype wire
