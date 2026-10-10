`timescale 1ns/1ps

// Integrated AI/DMA contention test: CSR -> engines -> four-master fabric ->
// AXI4/HMIC adapter -> a small DDR behavior model.  CPU I/D ports are tied
// idle here; the CPU path is covered separately by pgl50h_soc_ddr_path_tb.
module pgl50h_soc_axi_contention_tb;
  localparam integer DW = 256;
  localparam integer AW = 28;

  reg clk, reset, init_done;
  always #5 clk = ~clk;

  reg cmd_valid, cmd_write;
  reg [31:0] cmd_addr, cmd_wdata;
  reg [3:0] cmd_wstrb;
  wire cmd_ready, rsp_valid, rsp_error;
  wire [31:0] rsp_rdata;
  reg [7:0] keys;
  wire [7:0] leds;
  wire timer_irq;
  wire [63:0] mtime;

  wire ai_start;
  wire [31:0] ai_control, ai_src_addr, ai_dst_addr, ai_length, ai_channels, ai_scale;
  wire [31:0] ai_status;
  wire ai_done_irq, ai_error_irq;
  wire dma_start;
  wire [31:0] dma_control, dma_src_addr, dma_dst_addr, dma_length, dma_stride;
  wire [31:0] dma_status;
  wire dma_done_irq, dma_error_irq;
  wire [5:0] irq_enable, irq_clear, irq_pending;
  wire external_irq;

  wire [3:0] m2_awid, m2_awlen, m2_bid, m2_arid, m2_arlen, m2_rid;
  wire [31:0] m2_awaddr, m2_araddr, m2_wstrb;
  wire [DW-1:0] m2_wdata, m2_rdata;
  wire m2_awvalid, m2_awready, m2_wvalid, m2_wready, m2_wlast, m2_bvalid, m2_bready;
  wire m2_arvalid, m2_arready, m2_rvalid, m2_rready, m2_rlast;
  wire [1:0] m2_bresp, m2_rresp;

  wire [3:0] m3_awid, m3_awlen, m3_bid, m3_arid, m3_arlen, m3_rid;
  wire [31:0] m3_awaddr, m3_araddr, m3_wstrb;
  wire [DW-1:0] m3_wdata, m3_rdata;
  wire m3_awvalid, m3_awready, m3_wvalid, m3_wready, m3_wlast, m3_bvalid, m3_bready;
  wire m3_arvalid, m3_arready, m3_rvalid, m3_rready, m3_rlast;
  wire [1:0] m3_bresp, m3_rresp;

  wire [3:0] f_awid, f_awlen, f_bid, f_arid, f_arlen, f_rid;
  wire [31:0] f_awaddr, f_araddr, f_wstrb;
  wire [DW-1:0] f_wdata, f_rdata;
  wire f_awvalid, f_awready, f_wvalid, f_wready, f_wlast, f_bvalid, f_bready;
  wire f_arvalid, f_arready, f_rvalid, f_rready, f_rlast;
  wire [1:0] f_bresp, f_rresp;
  wire [7:0] perf0, perf1, perf2, perf3;

  wire [AW-1:0] axi_awaddr, axi_araddr;
  wire axi_awuser_ap, axi_awvalid, axi_wready, axi_aruser_ap, axi_arvalid, axi_arready;
  wire [3:0] axi_awuser_id, axi_awlen, axi_wusero_id, axi_aruser_id, axi_arlen;
  reg  [3:0] axi_rid;
  wire [DW-1:0] axi_wdata;
  reg  [DW-1:0] axi_rdata;
  wire [DW/8-1:0] axi_wstrb;
  wire axi_awready, axi_wusero_last;
  reg axi_rvalid, axi_rlast;

  reg [DW-1:0] ddr_mem [0:511];
  reg [AW-1:0] read_pending_addr;
  reg [3:0] read_pending_id;
  reg read_pending;
  integer i, cycles, ar_count, aw_count;

  pgl50h_csr_fabric u_csr (
    .clk(clk), .reset(reset), .cmd_valid(cmd_valid), .cmd_write(cmd_write), .cmd_addr(cmd_addr),
    .cmd_wdata(cmd_wdata), .cmd_wstrb(cmd_wstrb), .cmd_ready(cmd_ready), .rsp_valid(rsp_valid),
    .rsp_rdata(rsp_rdata), .rsp_error(rsp_error), .keys(keys), .leds(leds), .timer_irq(timer_irq), .mtime_value(mtime),
    .ai_status(ai_status), .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr), .ai_dst_addr(ai_dst_addr),
    .ai_length(ai_length), .ai_channels(ai_channels), .ai_scale(ai_scale), .dma_status(dma_status), .dma_start(dma_start),
    .dma_control(dma_control), .dma_src_addr(dma_src_addr), .dma_dst_addr(dma_dst_addr), .dma_length(dma_length), .dma_stride(dma_stride),
    .qspi_status(32'h0), .qspi_rxdata(32'h0), .qspi_control(), .qspi_txdata(), .irq_enable(irq_enable), .irq_clear(irq_clear), .irq_pending(irq_pending)
  );

  pgl50h_ai_engine u_ai (
    .clk(clk), .reset(reset), .start(ai_start), .control(ai_control), .src_addr(ai_src_addr), .dst_addr(ai_dst_addr), .length(ai_length), .channels(ai_channels), .scale(ai_scale), .status(ai_status), .done_irq(ai_done_irq), .error_irq(ai_error_irq),
    .m_awid(m2_awid), .m_awaddr(m2_awaddr), .m_awlen(m2_awlen), .m_awvalid(m2_awvalid), .m_awready(m2_awready), .m_wdata(m2_wdata), .m_wstrb(m2_wstrb), .m_wlast(m2_wlast), .m_wvalid(m2_wvalid), .m_wready(m2_wready), .m_bid(m2_bid), .m_bresp(m2_bresp), .m_bvalid(m2_bvalid), .m_bready(m2_bready), .m_arid(m2_arid), .m_araddr(m2_araddr), .m_arlen(m2_arlen), .m_arvalid(m2_arvalid), .m_arready(m2_arready), .m_rid(m2_rid), .m_rdata(m2_rdata), .m_rresp(m2_rresp), .m_rlast(m2_rlast), .m_rvalid(m2_rvalid), .m_rready(m2_rready)
  );

  pgl50h_camera_dma u_dma (
    .clk(clk), .reset(reset), .start(dma_start), .control(dma_control), .src_addr(dma_src_addr), .dst_addr(dma_dst_addr), .length(dma_length), .stride(dma_stride), .status(dma_status), .done_irq(dma_done_irq), .error_irq(dma_error_irq), .pixel_valid(1'b0), .pixel_ready(), .pixel_data(32'h0), .pixel_sof(1'b0), .pixel_eol(1'b0),
    .m_awid(m3_awid), .m_awaddr(m3_awaddr), .m_awlen(m3_awlen), .m_awvalid(m3_awvalid), .m_awready(m3_awready), .m_wdata(m3_wdata), .m_wstrb(m3_wstrb), .m_wlast(m3_wlast), .m_wvalid(m3_wvalid), .m_wready(m3_wready), .m_bid(m3_bid), .m_bresp(m3_bresp), .m_bvalid(m3_bvalid), .m_bready(m3_bready), .m_arid(m3_arid), .m_araddr(m3_araddr), .m_arlen(m3_arlen), .m_arvalid(m3_arvalid), .m_arready(m3_arready), .m_rid(m3_rid), .m_rdata(m3_rdata), .m_rresp(m3_rresp), .m_rlast(m3_rlast), .m_rvalid(m3_rvalid), .m_rready(m3_rready)
  );

  pgl50h_interrupt_aggregator u_irq (
    .clk(clk), .reset(reset), .timer_irq(timer_irq), .ai_done_irq(ai_done_irq), .ai_error_irq(ai_error_irq), .dma_done_irq(dma_done_irq), .dma_error_irq(dma_error_irq), .qspi_irq(1'b0), .enable(irq_enable), .clear(irq_clear), .pending(irq_pending), .irq(external_irq)
  );

  pgl50h_axi4_mem_fabric u_fabric (
    .clk(clk), .reset(reset), .init_done(init_done),
    .m0_awid(4'h0), .m0_awaddr(32'h0), .m0_awlen(4'h0), .m0_awvalid(1'b0), .m0_awready(), .m0_wdata(256'h0), .m0_wstrb(32'h0), .m0_wlast(1'b1), .m0_wvalid(1'b0), .m0_wready(), .m0_bid(), .m0_bresp(), .m0_bvalid(), .m0_bready(1'b1), .m0_arid(4'h0), .m0_araddr(32'h0), .m0_arlen(4'h0), .m0_arvalid(1'b0), .m0_arready(), .m0_rid(), .m0_rdata(), .m0_rresp(), .m0_rlast(), .m0_rvalid(), .m0_rready(1'b1),
    .m1_awid(4'h0), .m1_awaddr(32'h0), .m1_awlen(4'h0), .m1_awvalid(1'b0), .m1_awready(), .m1_wdata(256'h0), .m1_wstrb(32'h0), .m1_wlast(1'b1), .m1_wvalid(1'b0), .m1_wready(), .m1_bid(), .m1_bresp(), .m1_bvalid(), .m1_bready(1'b1), .m1_arid(4'h0), .m1_araddr(32'h0), .m1_arlen(4'h0), .m1_arvalid(1'b0), .m1_arready(), .m1_rid(), .m1_rdata(), .m1_rresp(), .m1_rlast(), .m1_rvalid(), .m1_rready(1'b1),
    .m2_awid(m2_awid), .m2_awaddr(m2_awaddr), .m2_awlen(m2_awlen), .m2_awvalid(m2_awvalid), .m2_awready(m2_awready), .m2_wdata(m2_wdata), .m2_wstrb(m2_wstrb), .m2_wlast(m2_wlast), .m2_wvalid(m2_wvalid), .m2_wready(m2_wready), .m2_bid(m2_bid), .m2_bresp(m2_bresp), .m2_bvalid(m2_bvalid), .m2_bready(m2_bready), .m2_arid(m2_arid), .m2_araddr(m2_araddr), .m2_arlen(m2_arlen), .m2_arvalid(m2_arvalid), .m2_arready(m2_arready), .m2_rid(m2_rid), .m2_rdata(m2_rdata), .m2_rresp(m2_rresp), .m2_rlast(m2_rlast), .m2_rvalid(m2_rvalid), .m2_rready(m2_rready),
    .m3_awid(m3_awid), .m3_awaddr(m3_awaddr), .m3_awlen(m3_awlen), .m3_awvalid(m3_awvalid), .m3_awready(m3_awready), .m3_wdata(m3_wdata), .m3_wstrb(m3_wstrb), .m3_wlast(m3_wlast), .m3_wvalid(m3_wvalid), .m3_wready(m3_wready), .m3_bid(m3_bid), .m3_bresp(m3_bresp), .m3_bvalid(m3_bvalid), .m3_bready(m3_bready), .m3_arid(m3_arid), .m3_araddr(m3_araddr), .m3_arlen(m3_arlen), .m3_arvalid(m3_arvalid), .m3_arready(m3_arready), .m3_rid(m3_rid), .m3_rdata(m3_rdata), .m3_rresp(m3_rresp), .m3_rlast(m3_rlast), .m3_rvalid(m3_rvalid), .m3_rready(m3_rready),
    .d_awid(f_awid), .d_awaddr(f_awaddr), .d_awlen(f_awlen), .d_awvalid(f_awvalid), .d_awready(f_awready), .d_wdata(f_wdata), .d_wstrb(f_wstrb), .d_wlast(f_wlast), .d_wvalid(f_wvalid), .d_wready(f_wready), .d_bid(f_bid), .d_bresp(f_bresp), .d_bvalid(f_bvalid), .d_bready(f_bready), .d_arid(f_arid), .d_araddr(f_araddr), .d_arlen(f_arlen), .d_arvalid(f_arvalid), .d_arready(f_arready), .d_rid(f_rid), .d_rdata(f_rdata), .d_rresp(f_rresp), .d_rlast(f_rlast), .d_rvalid(f_rvalid), .d_rready(f_rready), .perf_max_wait0(perf0), .perf_max_wait1(perf1), .perf_max_wait2(perf2), .perf_max_wait3(perf3)
  );

  pgl50h_axi4_hmic_adapter #(.AXI_ADDR_WIDTH(32), .HMIC_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW), .ID_WIDTH(4), .CPU_MEM_BASE(32'h8000_0000), .HMIC_ADDR_SHIFT(3)) u_hmic (
    .clk(clk), .reset(reset), .init_done(init_done), .s_axi_awid(f_awid), .s_axi_awaddr(f_awaddr), .s_axi_awlen(f_awlen), .s_axi_awvalid(f_awvalid), .s_axi_awready(f_awready), .s_axi_wdata(f_wdata), .s_axi_wstrb(f_wstrb), .s_axi_wlast(f_wlast), .s_axi_wvalid(f_wvalid), .s_axi_wready(f_wready), .s_axi_bid(f_bid), .s_axi_bresp(f_bresp), .s_axi_bvalid(f_bvalid), .s_axi_bready(f_bready), .s_axi_arid(f_arid), .s_axi_araddr(f_araddr), .s_axi_arlen(f_arlen), .s_axi_arvalid(f_arvalid), .s_axi_arready(f_arready), .s_axi_rid(f_rid), .s_axi_rdata(f_rdata), .s_axi_rresp(f_rresp), .s_axi_rlast(f_rlast), .s_axi_rvalid(f_rvalid), .s_axi_rready(f_rready), .axi_awaddr(axi_awaddr), .axi_awuser_ap(axi_awuser_ap), .axi_awuser_id(axi_awuser_id), .axi_awlen(axi_awlen), .axi_awready(axi_awready), .axi_awvalid(axi_awvalid), .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wready(axi_wready), .axi_wusero_id(axi_wusero_id), .axi_wusero_last(axi_wusero_last), .axi_araddr(axi_araddr), .axi_aruser_ap(axi_aruser_ap), .axi_aruser_id(axi_aruser_id), .axi_arlen(axi_arlen), .axi_arready(axi_arready), .axi_arvalid(axi_arvalid), .axi_rdata(axi_rdata), .axi_rid(axi_rid), .axi_rlast(axi_rlast), .axi_rvalid(axi_rvalid)
  );

  assign axi_awready = 1'b1;
  assign axi_wready = 1'b1;
  assign axi_arready = !read_pending && !axi_rvalid;
  assign axi_wusero_id = axi_awuser_id;
  assign axi_wusero_last = 1'b1;

  always @(posedge clk) begin
    cycles = cycles + 1;
    axi_rvalid <= 1'b0;
    if (axi_arvalid && axi_arready) begin
      ar_count = ar_count + 1;
      read_pending_addr <= axi_araddr;
      read_pending_id <= axi_aruser_id;
      read_pending <= 1'b1;
    end
    if (read_pending) begin
      axi_rdata <= ddr_mem[read_pending_addr[10:2]];
      axi_rid <= read_pending_id;
      axi_rlast <= 1'b1;
      axi_rvalid <= 1'b1;
      read_pending <= 1'b0;
    end
    if (axi_awvalid && axi_awready && axi_wready) begin
      aw_count = aw_count + 1;
      for (i = 0; i < DW/8; i = i + 1)
        if (axi_wstrb[i]) ddr_mem[axi_awaddr[10:2]][i*8 +: 8] <= axi_wdata[i*8 +: 8];
    end
  end

  task automatic csr_write(input [31:0] address, input [31:0] data);
    begin
      @(negedge clk);
      while (!cmd_ready) @(negedge clk);
      cmd_valid = 1'b1; cmd_write = 1'b1; cmd_addr = address; cmd_wdata = data; cmd_wstrb = 4'hf;
      @(posedge clk);
      @(negedge clk); cmd_valid = 1'b0; cmd_write = 1'b0; cmd_wstrb = 0;
      while (!rsp_valid) @(posedge clk);
      if (rsp_error) $fatal(1, "unexpected CSR error at %h", address);
    end
  endtask

  initial begin
    clk = 0; reset = 1; init_done = 0; cmd_valid = 0; cmd_write = 0; cmd_addr = 0; cmd_wdata = 0; cmd_wstrb = 0; keys = 0;
    read_pending = 0; axi_rvalid = 0; axi_rdata = 0; axi_rid = 0; axi_rlast = 1'b1; cycles = 0; ar_count = 0; aw_count = 0;
    for (i = 0; i < 512; i = i + 1) ddr_mem[i] = 0;
    ddr_mem[9'h080] = 256'h0000_0000_0000_0000_0000_0000_0807_0605_0403_0201;
    ddr_mem[9'h081] = 256'h0000_0000_0000_0000_0000_0000_0000_0000;
    ddr_mem[9'h100] = 256'h2222_000f_2222_000e_2222_000d_2222_000c_2222_000b_2222_000a_2222_0009_2222_0008;
    ddr_mem[9'h101] = 256'h3333_000f_3333_000e_3333_000d_3333_000c_3333_000b_3333_000a_3333_0009_3333_0008;
    repeat (3) @(posedge clk);
    reset = 0; init_done = 1;
    csr_write(32'h1000_0024, 32'h0000_001a); // AI done/error + DMA done/error
    csr_write(32'h1001_0008, 32'h8000_1000);
    csr_write(32'h1001_000c, 32'h8000_3000);
    csr_write(32'h1001_0010, 32'd64);
    csr_write(32'h1001_0000, 32'h1);
    csr_write(32'h1001_1008, 32'h8000_2000);
    csr_write(32'h1001_100c, 32'h8000_4000);
    csr_write(32'h1001_1010, 32'd64);
    csr_write(32'h1001_1000, 32'h1);
    while ((!ai_done_irq && !dma_done_irq) || ai_status[0] || dma_status[0]) begin
      @(posedge clk);
      if (cycles > 1000) $fatal(1, "integrated contention timeout");
    end
    repeat (4) @(posedge clk);
    if (ai_status[2] || dma_status[2] || !ai_status[1] || !dma_status[1]) $fatal(1, "engine error status AI=%h DMA=%h", ai_status, dma_status);
    if (ddr_mem[9'h180][31:0] !== 32'd100) $fatal(1, "AI writeback mismatch: %h", ddr_mem[9'h180][31:0]);
    if (ddr_mem[9'h200] !== ddr_mem[9'h100] || ddr_mem[9'h201] !== ddr_mem[9'h101]) $fatal(1, "DMA copy mismatch");
    if (!irq_pending[1] || !irq_pending[3] || !external_irq) $fatal(1, "completion IRQ aggregation failed: %b", irq_pending);
    if (ar_count < 4 || aw_count < 2) $fatal(1, "fabric metrics invalid ar=%0d aw=%0d", ar_count, aw_count);
    $display("PGL50H integrated AXI AI/DMA contention PASS (AR=%0d AW=%0d perf2=%0d perf3=%0d)", ar_count, aw_count, perf2, perf3);
    $finish;
  end
endmodule
