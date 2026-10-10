`timescale 1ns/1ps

// Four-master AXI4 memory-fabric contract test.  It checks initialization
// gating, round-robin service, continuous two-beat read delivery, and write
// response routing.  The first run is intentionally red while the fabric is
// still the old inert boundary.
module pgl50h_axi4_mem_fabric_tb;
  localparam integer DW = 256;
  localparam integer SW = DW / 8;

  reg clk;
  reg reset;
  reg init_done;

  reg [3:0] m0_awid, m1_awid, m2_awid, m3_awid;
  reg [31:0] m0_awaddr, m1_awaddr, m2_awaddr, m3_awaddr;
  reg [3:0] m0_awlen, m1_awlen, m2_awlen, m3_awlen;
  reg m0_awvalid, m1_awvalid, m2_awvalid, m3_awvalid;
  wire m0_awready, m1_awready, m2_awready, m3_awready;
  reg [DW-1:0] m0_wdata, m1_wdata, m2_wdata, m3_wdata;
  reg [SW-1:0] m0_wstrb, m1_wstrb, m2_wstrb, m3_wstrb;
  reg m0_wlast, m1_wlast, m2_wlast, m3_wlast;
  reg m0_wvalid, m1_wvalid, m2_wvalid, m3_wvalid;
  wire m0_wready, m1_wready, m2_wready, m3_wready;
  wire [3:0] m0_bid, m1_bid, m2_bid, m3_bid;
  wire [1:0] m0_bresp, m1_bresp, m2_bresp, m3_bresp;
  wire m0_bvalid, m1_bvalid, m2_bvalid, m3_bvalid;
  reg m0_bready, m1_bready, m2_bready, m3_bready;

  reg [3:0] m0_arid, m1_arid, m2_arid, m3_arid;
  reg [31:0] m0_araddr, m1_araddr, m2_araddr, m3_araddr;
  reg [3:0] m0_arlen, m1_arlen, m2_arlen, m3_arlen;
  reg m0_arvalid, m1_arvalid, m2_arvalid, m3_arvalid;
  wire m0_arready, m1_arready, m2_arready, m3_arready;
  wire [3:0] m0_rid, m1_rid, m2_rid, m3_rid;
  wire [DW-1:0] m0_rdata, m1_rdata, m2_rdata, m3_rdata;
  wire [1:0] m0_rresp, m1_rresp, m2_rresp, m3_rresp;
  wire m0_rlast, m1_rlast, m2_rlast, m3_rlast;
  wire m0_rvalid, m1_rvalid, m2_rvalid, m3_rvalid;
  reg m0_rready, m1_rready, m2_rready, m3_rready;

  wire [3:0] d_awid;
  wire [31:0] d_awaddr;
  wire [3:0] d_awlen;
  wire d_awvalid;
  reg d_awready;
  wire [DW-1:0] d_wdata;
  wire [SW-1:0] d_wstrb;
  wire d_wlast;
  wire d_wvalid;
  reg d_wready;
  reg [3:0] d_bid;
  reg [1:0] d_bresp;
  reg d_bvalid;
  wire d_bready;
  wire [3:0] d_arid;
  wire [31:0] d_araddr;
  wire [3:0] d_arlen;
  wire d_arvalid;
  reg d_arready;
  reg [3:0] d_rid;
  reg [DW-1:0] d_rdata;
  reg [1:0] d_rresp;
  reg d_rlast;
  reg d_rvalid;
  wire d_rready;
  wire [7:0] perf_max_wait0, perf_max_wait1, perf_max_wait2, perf_max_wait3;

  reg [DW-1:0] mem [0:63];
  reg rd_active;
  reg [31:0] rd_addr;
  reg [3:0] rd_left;
  reg [3:0] rd_id;
  reg wr_pending;
  reg [3:0] wr_id;
  integer i;
  integer ar_count;
  reg [31:0] ar_log [0:7];
  integer m0_words;
  integer m1_words;
  integer m2_words;
  integer m3_words;
  integer m0_last_cycle;
  integer m0_first_cycle;
  integer cycle_count;
  integer normal_ar_count;
  integer fair_cycle;
  integer fair_ar0, fair_ar1, fair_ar2, fair_ar3;
  integer fair_r0, fair_r1, fair_r2, fair_r3;

  always #5 clk = ~clk;

  pgl50h_axi4_mem_fabric #(
    .ADDR_WIDTH(32), .DATA_WIDTH(DW), .ID_WIDTH(4), .NUM_MASTERS(4)
  ) dut (
    .clk(clk), .reset(reset), .init_done(init_done),
    .m0_awid(m0_awid), .m0_awaddr(m0_awaddr), .m0_awlen(m0_awlen), .m0_awvalid(m0_awvalid), .m0_awready(m0_awready),
    .m0_wdata(m0_wdata), .m0_wstrb(m0_wstrb), .m0_wlast(m0_wlast), .m0_wvalid(m0_wvalid), .m0_wready(m0_wready),
    .m0_bid(m0_bid), .m0_bresp(m0_bresp), .m0_bvalid(m0_bvalid), .m0_bready(m0_bready),
    .m0_arid(m0_arid), .m0_araddr(m0_araddr), .m0_arlen(m0_arlen), .m0_arvalid(m0_arvalid), .m0_arready(m0_arready),
    .m0_rid(m0_rid), .m0_rdata(m0_rdata), .m0_rresp(m0_rresp), .m0_rlast(m0_rlast), .m0_rvalid(m0_rvalid), .m0_rready(m0_rready),
    .m1_awid(m1_awid), .m1_awaddr(m1_awaddr), .m1_awlen(m1_awlen), .m1_awvalid(m1_awvalid), .m1_awready(m1_awready),
    .m1_wdata(m1_wdata), .m1_wstrb(m1_wstrb), .m1_wlast(m1_wlast), .m1_wvalid(m1_wvalid), .m1_wready(m1_wready),
    .m1_bid(m1_bid), .m1_bresp(m1_bresp), .m1_bvalid(m1_bvalid), .m1_bready(m1_bready),
    .m1_arid(m1_arid), .m1_araddr(m1_araddr), .m1_arlen(m1_arlen), .m1_arvalid(m1_arvalid), .m1_arready(m1_arready),
    .m1_rid(m1_rid), .m1_rdata(m1_rdata), .m1_rresp(m1_rresp), .m1_rlast(m1_rlast), .m1_rvalid(m1_rvalid), .m1_rready(m1_rready),
    .m2_awid(m2_awid), .m2_awaddr(m2_awaddr), .m2_awlen(m2_awlen), .m2_awvalid(m2_awvalid), .m2_awready(m2_awready),
    .m2_wdata(m2_wdata), .m2_wstrb(m2_wstrb), .m2_wlast(m2_wlast), .m2_wvalid(m2_wvalid), .m2_wready(m2_wready),
    .m2_bid(m2_bid), .m2_bresp(m2_bresp), .m2_bvalid(m2_bvalid), .m2_bready(m2_bready),
    .m2_arid(m2_arid), .m2_araddr(m2_araddr), .m2_arlen(m2_arlen), .m2_arvalid(m2_arvalid), .m2_arready(m2_arready),
    .m2_rid(m2_rid), .m2_rdata(m2_rdata), .m2_rresp(m2_rresp), .m2_rlast(m2_rlast), .m2_rvalid(m2_rvalid), .m2_rready(m2_rready),
    .m3_awid(m3_awid), .m3_awaddr(m3_awaddr), .m3_awlen(m3_awlen), .m3_awvalid(m3_awvalid), .m3_awready(m3_awready),
    .m3_wdata(m3_wdata), .m3_wstrb(m3_wstrb), .m3_wlast(m3_wlast), .m3_wvalid(m3_wvalid), .m3_wready(m3_wready),
    .m3_bid(m3_bid), .m3_bresp(m3_bresp), .m3_bvalid(m3_bvalid), .m3_bready(m3_bready),
    .m3_arid(m3_arid), .m3_araddr(m3_araddr), .m3_arlen(m3_arlen), .m3_arvalid(m3_arvalid), .m3_arready(m3_arready),
    .m3_rid(m3_rid), .m3_rdata(m3_rdata), .m3_rresp(m3_rresp), .m3_rlast(m3_rlast), .m3_rvalid(m3_rvalid), .m3_rready(m3_rready),
    .d_awid(d_awid), .d_awaddr(d_awaddr), .d_awlen(d_awlen), .d_awvalid(d_awvalid), .d_awready(d_awready),
    .d_wdata(d_wdata), .d_wstrb(d_wstrb), .d_wlast(d_wlast), .d_wvalid(d_wvalid), .d_wready(d_wready),
    .d_bid(d_bid), .d_bresp(d_bresp), .d_bvalid(d_bvalid), .d_bready(d_bready),
    .d_arid(d_arid), .d_araddr(d_araddr), .d_arlen(d_arlen), .d_arvalid(d_arvalid), .d_arready(d_arready),
    .d_rid(d_rid), .d_rdata(d_rdata), .d_rresp(d_rresp), .d_rlast(d_rlast), .d_rvalid(d_rvalid), .d_rready(d_rready),
    .perf_max_wait0(perf_max_wait0), .perf_max_wait1(perf_max_wait1), .perf_max_wait2(perf_max_wait2), .perf_max_wait3(perf_max_wait3)
  );

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    d_rvalid <= 1'b0;
    d_bvalid <= 1'b0;
    if (d_arvalid && d_arready) begin
      if (ar_count < 8)
        ar_log[ar_count] = d_araddr;
      ar_count = ar_count + 1;
      rd_active <= 1'b1;
      rd_addr <= d_araddr;
      rd_left <= d_arlen;
      rd_id <= d_arid;
    end
    if (rd_active && d_rready) begin
      d_rdata <= mem[rd_addr[10:5]];
      d_rid <= rd_id;
      d_rresp <= 2'b00;
      d_rlast <= (rd_left == 0);
      d_rvalid <= 1'b1;
      if (rd_left == 0) begin
        rd_active <= 1'b0;
      end else begin
        rd_left <= rd_left - 1'b1;
        rd_addr <= rd_addr + 32;
      end
    end
    if (d_awvalid && d_awready) begin
      wr_id <= d_awid;
    end
    if (d_wvalid && d_wready) begin
      mem[d_awaddr[10:5]] <= d_wdata;
      if (d_wlast) wr_pending <= 1'b1;
    end
    if (wr_pending && !d_bvalid) begin
      d_bid <= wr_id;
      d_bresp <= 2'b00;
      d_bvalid <= 1'b1;
      wr_pending <= 1'b0;
    end
  end

  task automatic issue_m0_read(input [31:0] address, input [3:0] len);
    begin
      m0_arid = 4'h0; m0_araddr = address; m0_arlen = len; m0_arvalid = 1'b1;
      while (!m0_arready) @(posedge clk);
      @(posedge clk); @(negedge clk); m0_arvalid = 1'b0;
    end
  endtask
  task automatic issue_m1_read(input [31:0] address, input [3:0] len);
    begin
      m1_arid = 4'h1; m1_araddr = address; m1_arlen = len; m1_arvalid = 1'b1;
      while (!m1_arready) @(posedge clk);
      @(posedge clk); @(negedge clk); m1_arvalid = 1'b0;
    end
  endtask
  task automatic issue_m2_read(input [31:0] address, input [3:0] len);
    begin
      m2_arid = 4'h2; m2_araddr = address; m2_arlen = len; m2_arvalid = 1'b1;
      while (!m2_arready) @(posedge clk);
      @(posedge clk); @(negedge clk); m2_arvalid = 1'b0;
    end
  endtask
  task automatic issue_m3_read(input [31:0] address, input [3:0] len);
    begin
      m3_arid = 4'h3; m3_araddr = address; m3_arlen = len; m3_arvalid = 1'b1;
      while (!m3_arready) @(posedge clk);
      @(posedge clk); @(negedge clk); m3_arvalid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0; reset = 1'b1; init_done = 1'b0;
    m0_awid=0; m1_awid=0; m2_awid=0; m3_awid=0; m0_awaddr=0; m1_awaddr=0; m2_awaddr=0; m3_awaddr=0; m0_awlen=0; m1_awlen=0; m2_awlen=0; m3_awlen=0; m0_awvalid=0; m1_awvalid=0; m2_awvalid=0; m3_awvalid=0;
    m0_wdata=0; m1_wdata=0; m2_wdata=0; m3_wdata=0; m0_wstrb={SW{1'b0}}; m1_wstrb={SW{1'b0}}; m2_wstrb={SW{1'b0}}; m3_wstrb={SW{1'b0}}; m0_wlast=1; m1_wlast=1; m2_wlast=1; m3_wlast=1; m0_wvalid=0; m1_wvalid=0; m2_wvalid=0; m3_wvalid=0;
    m0_bready=1; m1_bready=1; m2_bready=1; m3_bready=1; m0_arid=0; m1_arid=0; m2_arid=0; m3_arid=0; m0_araddr=0; m1_araddr=0; m2_araddr=0; m3_araddr=0; m0_arlen=0; m1_arlen=0; m2_arlen=0; m3_arlen=0; m0_arvalid=0; m1_arvalid=0; m2_arvalid=0; m3_arvalid=0; m0_rready=1; m1_rready=1; m2_rready=1; m3_rready=1;
    d_awready=1; d_wready=1; d_arready=1; d_bid=0; d_bresp=0; d_bvalid=0; d_rid=0; d_rdata=0; d_rresp=0; d_rlast=0; d_rvalid=0; rd_active=0; wr_pending=0; ar_count=0; cycle_count=0; m0_words=0; m1_words=0; m2_words=0; m3_words=0; m0_first_cycle=-1; m0_last_cycle=-1;
    for (i = 0; i < 64; i = i + 1) mem[i] = {4{64'h0}};
    mem[2] = {64'h0000_0007,64'h0000_0006,64'h0000_0005,64'h0000_0004};
    mem[3] = {64'h0000_0003,64'h0000_0002,64'h0000_0001,64'h0000_0000};
    mem[8] = {64'h1111_0007,64'h1111_0006,64'h1111_0005,64'h1111_0004};
    mem[10] = {64'h2222_0007,64'h2222_0006,64'h2222_0005,64'h2222_0004};
    mem[12] = {64'h3333_0007,64'h3333_0006,64'h3333_0005,64'h3333_0004};
    mem[14] = {64'h4444_0007,64'h4444_0006,64'h4444_0005,64'h4444_0004};
    repeat (2) @(posedge clk);
    reset = 1'b0;
    @(negedge clk);
    m0_arvalid = 1'b1; m0_araddr = 32'h8000_0040; m0_arlen = 0;
    @(posedge clk);
    #1;
    if (m0_arready !== 1'b0) $fatal(1, "fabric accepted AR before init_done");
    @(negedge clk);
    m0_arvalid = 1'b0; init_done = 1'b1;
    @(negedge clk);

    fork
      issue_m0_read(32'h8000_0040, 4'd1);
      issue_m1_read(32'h8000_0100, 4'd0);
      issue_m2_read(32'h8000_0140, 4'd0);
      issue_m3_read(32'h8000_0180, 4'd0);
    join

    while (m0_words < 8 || m1_words < 4 || m2_words < 4 || m3_words < 4) begin
      @(posedge clk);
      if (m0_rvalid && m0_rready) begin
        if (m0_rid !== 0 || m0_rresp !== 0) $fatal(1, "m0 R metadata mismatch");
        m0_words = m0_words + 4;
        if (m0_first_cycle < 0) m0_first_cycle = cycle_count;
        else m0_last_cycle = cycle_count;
      end
      if (m1_rvalid && m1_rready) begin
        if (m1_rid !== 1 || m1_rresp !== 0 || m1_rlast !== 1) $fatal(1, "m1 R mismatch");
        m1_words = m1_words + 4;
      end
      if (m2_rvalid && m2_rready) begin
        if (m2_rid !== 2 || m2_rresp !== 0 || m2_rlast !== 1) $fatal(1, "m2 R mismatch");
        m2_words = m2_words + 4;
      end
      if (m3_rvalid && m3_rready) begin
        if (m3_rid !== 3 || m3_rresp !== 0 || m3_rlast !== 1) $fatal(1, "m3 R mismatch");
        m3_words = m3_words + 4;
      end
      if (cycle_count > 200) $fatal(1, "fabric read timeout");
    end
    if (m0_last_cycle - m0_first_cycle !== 1)
      $fatal(1, "m0 burst has a fabric bubble: first=%0d last=%0d", m0_first_cycle, m0_last_cycle);

    m1_awid = 4'h9; m1_awaddr = 32'h8000_0100; m1_awlen = 0; m1_awvalid = 1'b1;
    while (!m1_awready) @(posedge clk);
    @(posedge clk); m1_awvalid = 1'b0;
    m1_wdata = {4{64'hdead_beef_cafe_babe}}; m1_wstrb = {SW{1'b1}}; m1_wlast = 1'b1; m1_wvalid = 1'b1;
    while (!m1_wready) @(posedge clk);
    @(posedge clk); m1_wvalid = 1'b0;
    while (!m1_bvalid) @(posedge clk);
    if (m1_bid !== 4'h9 || m1_bresp !== 0) $fatal(1, "m1 B response mismatch");

    if (ar_count !== 4) $fatal(1, "unexpected downstream AR count=%0d", ar_count);
    if (ar_log[0] !== 32'h8000_0040 || ar_log[1] !== 32'h8000_0100 ||
        ar_log[2] !== 32'h8000_0140 || ar_log[3] !== 32'h8000_0180)
      $fatal(1, "downstream AR order mismatch");
    normal_ar_count = ar_count;

    // Sustained all-master read pressure.  Every master keeps ARVALID high;
    // the downstream model is always ready and returns one beat per request.
    // This exercises the starvation promotion path instead of only checking a
    // finite four-request burst.
    fair_ar0 = 0; fair_ar1 = 0; fair_ar2 = 0; fair_ar3 = 0;
    fair_r0 = 0; fair_r1 = 0; fair_r2 = 0; fair_r3 = 0;
    @(negedge clk);
    m0_arid = 4'h0; m0_araddr = 32'h8000_0040; m0_arlen = 4'd0; m0_arvalid = 1'b1;
    m1_arid = 4'h1; m1_araddr = 32'h8000_0100; m1_arlen = 4'd0; m1_arvalid = 1'b1;
    m2_arid = 4'h2; m2_araddr = 32'h8000_0140; m2_arlen = 4'd0; m2_arvalid = 1'b1;
    m3_arid = 4'h3; m3_araddr = 32'h8000_0180; m3_arlen = 4'd0; m3_arvalid = 1'b1;
    for (fair_cycle = 0; fair_cycle < 400; fair_cycle = fair_cycle + 1) begin
      @(posedge clk);
      if (m0_arvalid && m0_arready) fair_ar0 = fair_ar0 + 1;
      if (m1_arvalid && m1_arready) fair_ar1 = fair_ar1 + 1;
      if (m2_arvalid && m2_arready) fair_ar2 = fair_ar2 + 1;
      if (m3_arvalid && m3_arready) fair_ar3 = fair_ar3 + 1;
      if (m0_rvalid && m0_rready) fair_r0 = fair_r0 + 1;
      if (m1_rvalid && m1_rready) fair_r1 = fair_r1 + 1;
      if (m2_rvalid && m2_rready) fair_r2 = fair_r2 + 1;
      if (m3_rvalid && m3_rready) fair_r3 = fair_r3 + 1;
    end
    @(negedge clk);
    m0_arvalid = 1'b0; m1_arvalid = 1'b0; m2_arvalid = 1'b0; m3_arvalid = 1'b0;
    if (fair_ar0 == 0 || fair_ar1 == 0 || fair_ar2 == 0 || fair_ar3 == 0 ||
        fair_r0 == 0 || fair_r1 == 0 || fair_r2 == 0 || fair_r3 == 0)
      $fatal(1, "fairness pressure starved a master: AR=%0d/%0d/%0d/%0d R=%0d/%0d/%0d/%0d",
             fair_ar0, fair_ar1, fair_ar2, fair_ar3, fair_r0, fair_r1, fair_r2, fair_r3);
    if (perf_max_wait0 >= 8'd255 || perf_max_wait1 >= 8'd255 ||
        perf_max_wait2 >= 8'd255 || perf_max_wait3 >= 8'd255)
      $fatal(1, "fabric starvation counter reached 255: %0d/%0d/%0d/%0d",
             perf_max_wait0, perf_max_wait1, perf_max_wait2, perf_max_wait3);
    $display("PGL50H AXI4 memory fabric fairness PASS (AR=%0d/%0d/%0d/%0d R=%0d/%0d/%0d/%0d max_wait=%0d/%0d/%0d/%0d)",
             fair_ar0, fair_ar1, fair_ar2, fair_ar3, fair_r0, fair_r1, fair_r2, fair_r3,
             perf_max_wait0, perf_max_wait1, perf_max_wait2, perf_max_wait3);
    $display("PGL50H AXI4 memory fabric contract PASS (AR=%0d, m0_gap=%0d)", normal_ar_count, m0_last_cycle - m0_first_cycle);
    $finish;
  end
endmodule
