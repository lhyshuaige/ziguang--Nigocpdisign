`timescale 1ns/1ps

module pgl50h_ai_engine_tb;
  localparam integer DW = 256;
  localparam integer SW = DW / 8;
  reg clk, reset;
  reg start;
  reg [31:0] control, src_addr, dst_addr, length, channels, scale;
  wire [31:0] status;
  wire done_irq, error_irq;

  wire [3:0] awid;
  wire [31:0] awaddr;
  wire [3:0] awlen;
  wire awvalid;
  reg awready;
  wire [DW-1:0] wdata;
  wire [SW-1:0] wstrb;
  wire wlast, wvalid;
  reg wready;
  reg [3:0] bid;
  reg [1:0] bresp;
  reg bvalid;
  wire bready;
  wire [3:0] arid;
  wire [31:0] araddr;
  wire [3:0] arlen;
  wire arvalid;
  reg arready;
  reg [3:0] rid;
  reg [DW-1:0] rdata;
  reg [1:0] rresp;
  reg rlast, rvalid;
  wire rready;

  reg [DW-1:0] source_mem [0:3];
  reg rd_active;
  reg [1:0] rd_index;
  reg [2:0] rd_wait;
  reg b_wait;
  integer cycles;
  integer expected;

  always #5 clk = ~clk;

  pgl50h_ai_engine dut (
    .clk(clk), .reset(reset), .start(start), .control(control),
    .src_addr(src_addr), .dst_addr(dst_addr), .length(length),
    .channels(channels), .scale(scale), .status(status),
    .done_irq(done_irq), .error_irq(error_irq),
    .m_awid(awid), .m_awaddr(awaddr), .m_awlen(awlen), .m_awvalid(awvalid), .m_awready(awready),
    .m_wdata(wdata), .m_wstrb(wstrb), .m_wlast(wlast), .m_wvalid(wvalid), .m_wready(wready),
    .m_bid(bid), .m_bresp(bresp), .m_bvalid(bvalid), .m_bready(bready),
    .m_arid(arid), .m_araddr(araddr), .m_arlen(arlen), .m_arvalid(arvalid), .m_arready(arready),
    .m_rid(rid), .m_rdata(rdata), .m_rresp(rresp), .m_rlast(rlast), .m_rvalid(rvalid), .m_rready(rready)
  );

  always @(posedge clk) begin
    cycles = cycles + 1;
    arready <= (cycles > 3);
    awready <= (cycles > 18);
    wready  <= (cycles[1:0] != 2'b01);
    bvalid  <= 1'b0;
    if (arvalid && arready) begin
      if (arid !== 4'h2 || araddr !== src_addr || arlen !== 1)
        $fatal(1, "AI AR mismatch id=%h addr=%h len=%0d", arid, araddr, arlen);
      rd_active <= 1'b1;
      rd_index <= 0;
      rd_wait <= 2;
    end
    if (rd_active && !rvalid && (rd_wait != 0)) rd_wait <= rd_wait - 1'b1;
    if (rd_active && !rvalid && (rd_wait == 0)) begin
      rdata <= source_mem[rd_index];
      rid <= 4'h2;
      rresp <= 2'b00;
      rlast <= (rd_index == 1);
      rvalid <= 1'b1;
    end
    if (rvalid && rready) begin
      rvalid <= 1'b0;
      if (rd_index == 1) begin
        rd_active <= 1'b0;
      end else begin
        rd_index <= rd_index + 1'b1;
        rd_wait <= 2;
      end
    end
    if (wvalid && wready) begin
      if (!wlast || wstrb[3:0] !== 4'hf) $fatal(1, "AI write beat metadata mismatch");
      b_wait <= 1'b1;
    end
    if (b_wait) begin
      bvalid <= 1'b1;
      bid <= 4'h2;
      bresp <= 2'b00;
      b_wait <= 1'b0;
    end
  end

  task automatic launch(input [31:0] nbytes);
    begin
      @(negedge clk);
      length = nbytes;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  initial begin
    clk = 0; reset = 1; start = 0; control = 0; src_addr = 32'h8000_1000;
    dst_addr = 32'h8000_2000; length = 64; channels = 1; scale = 32'h0000_0100;
    arready = 0; awready = 0; wready = 0; bid = 0; bresp = 0; bvalid = 0;
    rid = 0; rdata = 0; rresp = 0; rlast = 0; rvalid = 0;
    rd_active = 0; rd_index = 0; rd_wait = 0; b_wait = 0; cycles = 0;
    source_mem[0] = 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0403_0201;
    source_mem[1] = 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0807_0605;
    expected = 1*2 + 3*4 + 5*6 + 7*8;
    repeat (3) @(posedge clk);
    reset = 0;
    launch(64);
    while (!done_irq && !error_irq) begin
      @(posedge clk);
      if (cycles > 200) $fatal(1, "AI engine timeout");
    end
    if (error_irq || status[0] || !status[1]) $fatal(1, "AI engine did not complete cleanly status=%h", status);
    if (wdata[31:0] !== expected[31:0]) $fatal(1, "AI result mismatch got=%0d expected=%0d", $signed(wdata[31:0]), expected);

    // Q8.8 scaling is part of the software-visible descriptor contract:
    // 0x0080 is 0.5 and 0x0000 is a valid zero scale.
    scale = 32'h0000_0080;
    launch(64);
    while (!done_irq && !error_irq) begin
      @(posedge clk);
      if (cycles > 300) $fatal(1, "AI scaled descriptor timeout");
    end
    if (error_irq || status[0] || !status[1] || wdata[31:0] !== 32'd50)
      $fatal(1, "AI Q8.8 half-scale mismatch status=%h result=%0d", status, $signed(wdata[31:0]));

    scale = 32'h0000_0000;
    launch(64);
    while (!done_irq && !error_irq) begin
      @(posedge clk);
      if (cycles > 400) $fatal(1, "AI zero-scale descriptor timeout");
    end
    if (error_irq || status[0] || !status[1] || wdata[31:0] !== 32'd0)
      $fatal(1, "AI zero-scale mismatch status=%h result=%0d", status, $signed(wdata[31:0]));

    scale = 32'h0000_0100;
    launch(3);
    while (!done_irq && !error_irq) begin
      @(posedge clk);
      if (cycles > 300) $fatal(1, "AI invalid descriptor timeout");
    end
    if (!error_irq || !status[2] || status[0]) $fatal(1, "AI invalid descriptor error missing status=%h", status);
    $display("PGL50H INT8 AI engine contract PASS");
    $finish;
  end
endmodule
