// One production top: 32-bit CSR staging/doorbell and one 256-bit AXI master.
// CSR is a local ready/valid bus, not AXI-Lite. It needs a Nigo bus adapter.
module ai_accelerator_top (
  input wire clk,rst_n,
  input wire csr_valid,csr_write,
  input wire [7:0] csr_addr,
  input wire [31:0] csr_wdata,
  output wire csr_ready,
  output reg [31:0] csr_rdata,
  output wire csr_error,irq,
  output wire m_arvalid, input wire m_arready,
  output wire [3:0] m_arid, output wire [31:0] m_araddr,
  output wire [7:0] m_arlen, output wire [2:0] m_arsize,
  output wire [1:0] m_arburst,
  input wire m_rvalid, output wire m_rready, input wire [3:0] m_rid,
  input wire [255:0] m_rdata, input wire [1:0] m_rresp, input wire m_rlast,
  output wire m_awvalid, input wire m_awready,
  output wire [3:0] m_awid, output wire [31:0] m_awaddr,
  output wire [7:0] m_awlen, output wire [2:0] m_awsize,
  output wire [1:0] m_awburst,
  output wire m_wvalid, input wire m_wready, output wire [255:0] m_wdata,
  output wire [31:0] m_wstrb, output wire m_wlast,
  input wire m_bvalid, output wire m_bready, input wire [3:0] m_bid,
  input wire [1:0] m_bresp,
  output wire busy
);
  reg [31:0] staging[0:21];
  // Q24 is uploaded through a tiny indexed sideband window.  Legacy
  // descriptors never use it; a descriptor with bit 14 set snapshots these
  // values into the executor queue slot on submit.
  reg [31:0] q24_bias_staging[0:7];
  reg [31:0] q24_multiplier_staging[0:7];
  reg [4:0] q24_param_index;
  reg [7:0] q24_cfg;
  wire [255:0] q24_bias_bus;
  wire [255:0] q24_multiplier_bus;
  wire [703:0] descriptor;
  genvar g;
  generate for(g=0;g<22;g=g+1)begin: g_desc
    assign descriptor[g*32+:32]=staging[g];
  end endgenerate
  generate for(g=0;g<8;g=g+1)begin: g_q24_params
    assign q24_bias_bus[g*32+:32]=q24_bias_staging[g];
    assign q24_multiplier_bus[g*32+:32]=q24_multiplier_staging[g];
  end endgenerate
  wire done,error,cmd_ready;
  wire [63:0] reads,compute_cycles,busy_cycles,axi_wait,macs,overlap;
  wire [31:0] q24_scalar_stall;
  reg done_sticky,error_sticky;
  reg [31:0] completions;
  wire aligned=csr_addr[1:0]==0;
  wire submit=csr_valid&&csr_write&&aligned&&(csr_addr==8'h80)&&csr_wdata[0];
  assign csr_ready=!submit||cmd_ready;
  assign csr_error=csr_valid&&(!aligned ||
    (csr_write ? !(csr_addr<=8'h54 || (csr_addr>=8'h58 && csr_addr<=8'h60)
                   || csr_addr==8'h80)
               : !(csr_addr<=8'h54 || csr_addr==8'h84 || csr_addr==8'h88
                   || (csr_addr>=8'h58 && csr_addr<=8'h60)
                   || (csr_addr>=8'ha0 && csr_addr<=8'hcc) || csr_addr==8'hd0)));
  assign irq=done_sticky;
  integer i;
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
      for(i=0;i<22;i=i+1)staging[i]<=0;
      for(i=0;i<8;i=i+1)begin
        q24_bias_staging[i]<=0;
        q24_multiplier_staging[i]<=0;
      end
      q24_param_index<=0;
      q24_cfg<=0;
      done_sticky<=0;error_sticky<=0;completions<=0;
    end else begin
      if(csr_valid&&csr_ready&&csr_write&&!csr_error)begin
        if(csr_addr<=8'h54)staging[csr_addr[6:2]]<=csr_wdata;
        if(csr_addr==8'h58)q24_param_index<=csr_wdata[4:0];
        if(csr_addr==8'h5c)begin
          if(q24_param_index[4])
            q24_multiplier_staging[q24_param_index[2:0]]<=csr_wdata;
          else
            q24_bias_staging[q24_param_index[2:0]]<=csr_wdata;
          q24_param_index<=q24_param_index+1'b1;
        end
        if(csr_addr==8'h60)q24_cfg<=csr_wdata[7:0];
        if(csr_addr==8'h80)begin
          if(csr_wdata[1])done_sticky<=0;
          if(csr_wdata[2])error_sticky<=0;
        end
      end
      // A completion on the acknowledge cycle wins: no interrupt is lost.
      if(done)begin
        done_sticky<=1;
        if(error)error_sticky<=1;
        completions<=completions+1'b1;
      end
    end
  end
  always @* begin
    csr_rdata=0;
    if(aligned&&csr_addr<=8'h54)csr_rdata=staging[csr_addr[6:2]];
    else case(csr_addr)
      8'h58:csr_rdata={27'd0,q24_param_index};
      8'h5c:csr_rdata=q24_param_index[4] ?
        q24_multiplier_staging[q24_param_index[2:0]] :
        q24_bias_staging[q24_param_index[2:0]];
      8'h60:csr_rdata={24'd0,q24_cfg};
      8'h84:csr_rdata={28'd0,cmd_ready,error_sticky,done_sticky,busy};
      8'h88:csr_rdata=completions;
      8'ha0:csr_rdata=reads[31:0]; 8'ha4:csr_rdata=reads[63:32];
      8'ha8:csr_rdata=compute_cycles[31:0];8'hac:csr_rdata=compute_cycles[63:32];
      8'hb0:csr_rdata=busy_cycles[31:0];8'hb4:csr_rdata=busy_cycles[63:32];
      8'hb8:csr_rdata=axi_wait[31:0];8'hbc:csr_rdata=axi_wait[63:32];
      8'hc0:csr_rdata=macs[31:0];8'hc4:csr_rdata=macs[63:32];
      8'hc8:csr_rdata=overlap[31:0];8'hcc:csr_rdata=overlap[63:32];
      8'hd0:csr_rdata=q24_scalar_stall;
      default:begin end
    endcase
  end
  ai_stream_tile_executor_v2 executor_i(
    .clk(clk),.rst_n(rst_n),.cmd_valid(submit),
    .cmd_ready(cmd_ready),.cmd_desc(descriptor),
    .q24_param_valid(q24_cfg[0]),.q24_param_bias(q24_bias_bus),
    .q24_param_multiplier_q24(q24_multiplier_bus),
    .q24_param_relu(q24_cfg[1]),.q24_param_relu6(q24_cfg[2]),
    .q24_param_relu6_max(8'sd127),
    .m_arvalid(m_arvalid),
    .m_arready(m_arready),
    .m_arid(m_arid),
    .m_araddr(m_araddr),
    .m_arlen(m_arlen),
    .m_arsize(m_arsize),
    .m_arburst(m_arburst),
    .m_rvalid(m_rvalid),
    .m_rready(m_rready),
    .m_rid(m_rid),
    .m_rdata(m_rdata),
    .m_rresp(m_rresp),
    .m_rlast(m_rlast),
    .m_awvalid(m_awvalid),
    .m_awready(m_awready),
    .m_awid(m_awid),
    .m_awaddr(m_awaddr),
    .m_awlen(m_awlen),
    .m_awsize(m_awsize),
    .m_awburst(m_awburst),
    .m_wvalid(m_wvalid),
    .m_wready(m_wready),
    .m_wdata(m_wdata),
    .m_wstrb(m_wstrb),
    .m_wlast(m_wlast),
    .m_bvalid(m_bvalid),
    .m_bready(m_bready),
    .m_bid(m_bid),
    .m_bresp(m_bresp),
    .busy(busy),.done(done),.error(error),
    .perf_read_beats(reads),.perf_compute_cycles(compute_cycles),
    .perf_busy_cycles(busy_cycles),.perf_axi_wait_cycles(axi_wait),
    .perf_mac_count(macs),.perf_q24_scalar_stall_cycles(q24_scalar_stall),
    .perf_overlap_cycles(overlap)
  );
endmodule
