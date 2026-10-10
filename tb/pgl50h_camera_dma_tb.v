`timescale 1ns/1ps

module pgl50h_camera_dma_tb;
  localparam integer DW = 256;
  localparam integer SW = DW / 8;
  reg clk, reset;
  reg start;
  reg [31:0] control, src_addr, dst_addr, length, stride;
  wire [31:0] status;
  wire done_irq, error_irq;
  reg pixel_valid, pixel_sof, pixel_eol;
  reg [31:0] pixel_data;
  wire pixel_ready;

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
  reg [DW-1:0] captured_write [0:3];
  integer rd_index, rd_wait, wr_index, cycles;
  reg rd_active, b_wait;

  always #5 clk = ~clk;

  pgl50h_camera_dma dut (
    .clk(clk), .reset(reset), .start(start), .control(control),
    .src_addr(src_addr), .dst_addr(dst_addr), .length(length), .stride(stride),
    .status(status), .done_irq(done_irq), .error_irq(error_irq),
    .pixel_valid(pixel_valid), .pixel_ready(pixel_ready), .pixel_data(pixel_data),
    .pixel_sof(pixel_sof), .pixel_eol(pixel_eol),
    .m_awid(awid), .m_awaddr(awaddr), .m_awlen(awlen), .m_awvalid(awvalid), .m_awready(awready),
    .m_wdata(wdata), .m_wstrb(wstrb), .m_wlast(wlast), .m_wvalid(wvalid), .m_wready(wready),
    .m_bid(bid), .m_bresp(bresp), .m_bvalid(bvalid), .m_bready(bready),
    .m_arid(arid), .m_araddr(araddr), .m_arlen(arlen), .m_arvalid(arvalid), .m_arready(arready),
    .m_rid(rid), .m_rdata(rdata), .m_rresp(rresp), .m_rlast(rlast), .m_rvalid(rvalid), .m_rready(rready)
  );

  always @(posedge clk) begin
    cycles = cycles + 1;
    arready <= (cycles > 3);
    awready <= (cycles > 12);
    wready <= (cycles[1:0] != 2'b01);
    bvalid <= 1'b0;
    if (arvalid && arready) begin
      if (arid !== 4'h3 || araddr !== src_addr || arlen !== 1)
        $fatal(1, "DMA AR mismatch id=%h addr=%h len=%0d", arid, araddr, arlen);
      rd_active <= 1'b1;
      rd_index <= 0;
      rd_wait <= 2;
    end
    if (rd_active && !rvalid && rd_wait != 0) rd_wait <= rd_wait - 1;
    if (rd_active && !rvalid && rd_wait == 0) begin
      rdata <= source_mem[rd_index];
      rid <= 4'h3;
      rresp <= 2'b00;
      rlast <= (rd_index == 1);
      rvalid <= 1'b1;
    end
    if (rvalid && rready) begin
      rvalid <= 1'b0;
      if (rd_index == 1) rd_active <= 1'b0;
      else begin rd_index <= rd_index + 1; rd_wait <= 2; end
    end
    if (awvalid && awready) begin
      if (awid !== 4'h3 || awaddr !== dst_addr || awlen !== 1)
        $fatal(1, "DMA AW mismatch id=%h addr=%h len=%0d", awid, awaddr, awlen);
      wr_index <= 0;
    end
    if (wvalid && wready) begin
      captured_write[wr_index] <= wdata;
      if (!wlast && wr_index == 1) $fatal(1, "DMA WLAST missing");
      wr_index <= wr_index + 1;
      if (wlast) b_wait <= 1'b1;
    end
    if (b_wait) begin
      bvalid <= 1'b1; bid <= 4'h3; bresp <= 2'b00; b_wait <= 1'b0;
    end
  end

  task automatic launch(input [31:0] nbytes);
    begin
      @(negedge clk); length = nbytes; start = 1'b1;
      @(negedge clk); start = 1'b0;
    end
  endtask

  initial begin
    clk = 0; reset = 1; start = 0; control = 0;
    src_addr = 32'h8000_3000; dst_addr = 32'h8000_4000; length = 64; stride = 0;
    pixel_valid = 0; pixel_sof = 0; pixel_eol = 0; pixel_data = 0;
    arready = 0; awready = 0; wready = 0; bid = 0; bresp = 0; bvalid = 0;
    rid = 0; rdata = 0; rresp = 0; rlast = 0; rvalid = 0;
    rd_active = 0; rd_index = 0; rd_wait = 0; wr_index = 0; b_wait = 0; cycles = 0;
    source_mem[0] = 256'h1111_000f_1111_000e_1111_000d_1111_000c_1111_000b_1111_000a_1111_0009_1111_0008;
    source_mem[1] = 256'h2222_000f_2222_000e_2222_000d_2222_000c_2222_000b_2222_000a_2222_0009_2222_0008;
    repeat (3) @(posedge clk);
    reset = 0;
    launch(64);
    while (!done_irq && !error_irq) begin
      @(posedge clk);
      if (cycles > 250) $fatal(1, "DMA timeout");
    end
    if (error_irq || status[0] || !status[1]) $fatal(1, "DMA did not complete cleanly status=%h", status);
    if (captured_write[0] !== source_mem[0] || captured_write[1] !== source_mem[1])
      $fatal(1, "DMA data mismatch");

    src_addr = 32'h8000_3004;
    launch(64);
    while (!done_irq && !error_irq) begin
      @(posedge clk);
      if (cycles > 350) $fatal(1, "DMA invalid descriptor timeout");
    end
    if (!error_irq || !status[2] || status[0]) $fatal(1, "DMA invalid descriptor error missing status=%h", status);
    $display("PGL50H camera/DMA contract PASS");
    $finish;
  end
endmodule
