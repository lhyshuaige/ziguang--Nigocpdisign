`timescale 1ns/1ps

// CSR/interrupt contract test.  The test deliberately exercises the public
// CPU peripheral window rather than reaching into implementation registers.
module pgl50h_csr_irq_tb;
  reg clk;
  reg reset;
  reg        cmd_valid;
  reg        cmd_write;
  reg [31:0] cmd_addr;
  reg [31:0] cmd_wdata;
  reg  [3:0] cmd_wstrb;
  wire       cmd_ready;
  wire       rsp_valid;
  wire [31:0] rsp_rdata;
  wire       rsp_error;
  reg  [7:0] keys;
  wire [7:0] leds;
  wire       timer_irq;
  wire [63:0] mtime_value;

  wire        ai_start;
  wire [31:0] ai_control, ai_src_addr, ai_dst_addr, ai_length, ai_channels, ai_scale;
  reg  [31:0] ai_status;
  reg         ai_done_irq, ai_error_irq;
  wire [31:0] dma_control, dma_src_addr, dma_dst_addr, dma_length, dma_stride;
  wire        dma_start;
  reg  [31:0] dma_status;
  reg         dma_done_irq, dma_error_irq;
  reg         qspi_irq;
  wire [31:0] qspi_control, qspi_txdata;
  reg  [31:0] qspi_status, qspi_rxdata;

  wire [5:0] irq_enable;
  wire [5:0] irq_clear;
  wire [5:0] irq_pending;
  wire       external_irq;
  reg        ai_start_seen;
  reg        dma_start_seen;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (reset) begin
      ai_start_seen <= 1'b0;
      dma_start_seen <= 1'b0;
    end else begin
      if (ai_start) ai_start_seen <= 1'b1;
      if (dma_start) dma_start_seen <= 1'b1;
    end
  end

  pgl50h_csr_fabric dut_csr (
    .clk(clk), .reset(reset),
    .cmd_valid(cmd_valid), .cmd_write(cmd_write), .cmd_addr(cmd_addr),
    .cmd_wdata(cmd_wdata), .cmd_wstrb(cmd_wstrb), .cmd_ready(cmd_ready),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_error(rsp_error),
    .keys(keys), .leds(leds), .timer_irq(timer_irq), .mtime_value(mtime_value),
    .ai_status(ai_status),
    .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr),
    .ai_dst_addr(ai_dst_addr), .ai_length(ai_length), .ai_channels(ai_channels), .ai_scale(ai_scale),
    .dma_status(dma_status),
    .dma_start(dma_start), .dma_control(dma_control), .dma_src_addr(dma_src_addr),
    .dma_dst_addr(dma_dst_addr), .dma_length(dma_length), .dma_stride(dma_stride),
    .qspi_status(qspi_status), .qspi_rxdata(qspi_rxdata),
    .qspi_control(qspi_control), .qspi_txdata(qspi_txdata),
    .irq_enable(irq_enable), .irq_clear(irq_clear), .irq_pending(irq_pending)
  );

  pgl50h_interrupt_aggregator dut_irq (
    .clk(clk), .reset(reset),
    .timer_irq(timer_irq), .ai_done_irq(ai_done_irq), .ai_error_irq(ai_error_irq),
    .dma_done_irq(dma_done_irq), .dma_error_irq(dma_error_irq), .qspi_irq(qspi_irq),
    .enable(irq_enable), .clear(irq_clear), .pending(irq_pending), .irq(external_irq)
  );

  task automatic csr_write(input [31:0] address, input [31:0] data, input [3:0] strb, input expect_error);
    begin
      @(negedge clk);
      while (!cmd_ready) @(negedge clk);
      cmd_valid = 1'b1; cmd_write = 1'b1; cmd_addr = address;
      cmd_wdata = data; cmd_wstrb = strb;
      @(posedge clk);
      @(negedge clk); cmd_valid = 1'b0; cmd_write = 1'b0; cmd_wstrb = 4'h0;
      while (!rsp_valid) @(posedge clk);
      if (rsp_error !== expect_error) $fatal(1, "write error mismatch addr=%h err=%b", address, rsp_error);
    end
  endtask

  task automatic csr_read(input [31:0] address, output [31:0] data, input expect_error);
    begin
      @(negedge clk);
      while (!cmd_ready) @(negedge clk);
      cmd_valid = 1'b1; cmd_write = 1'b0; cmd_addr = address;
      cmd_wdata = 32'h0; cmd_wstrb = 4'h0;
      @(posedge clk);
      @(negedge clk); cmd_valid = 1'b0;
      while (!rsp_valid) @(posedge clk);
      data = rsp_rdata;
      if (rsp_error !== expect_error) $fatal(1, "read error mismatch addr=%h err=%b", address, rsp_error);
    end
  endtask

  reg [31:0] rd;
  initial begin
    clk = 1'b0; reset = 1'b1; cmd_valid = 1'b0; cmd_write = 1'b0;
    cmd_addr = 0; cmd_wdata = 0; cmd_wstrb = 0; keys = 8'h5a;
    ai_status = 0; ai_done_irq = 0; ai_error_irq = 0;
    dma_status = 0; dma_done_irq = 0; dma_error_irq = 0;
    qspi_irq = 0; qspi_status = 0; qspi_rxdata = 0;
    repeat (3) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    csr_write(32'h4000_0000, 32'h0000_00a5, 4'hf, 1'b0);
    if (leds !== 8'ha5) $fatal(1, "legacy GPIO alias write failed");
    csr_read(32'h1000_0000, rd, 1'b0);
    if (rd !== 32'h0000_00a5) $fatal(1, "GPIO canonical readback failed: %h", rd);
    csr_read(32'h4000_0004, rd, 1'b0);
    if (rd !== 32'h0000_005a) $fatal(1, "keys alias read failed: %h", rd);
    csr_write(32'h1000_0000, 32'h0000_003c, 4'b0001, 1'b0);
    if (leds !== 8'h3c) $fatal(1, "byte strobe failed");

    csr_write(32'h1000_0010, 32'h0000_ffff, 4'hf, 1'b0);
    csr_write(32'h1000_0014, 32'hffff_ffff, 4'hf, 1'b0);
    if (timer_irq !== 1'b0) $fatal(1, "timer unexpectedly asserted");

    csr_write(32'h1001_0008, 32'h8000_0100, 4'hf, 1'b0);
    csr_write(32'h1001_000c, 32'h8000_0200, 4'hf, 1'b0);
    csr_write(32'h1001_0010, 32'd64, 4'hf, 1'b0);
    csr_write(32'h4001_0000, 32'h0000_0001, 4'hf, 1'b0);
    if (!(ai_start_seen || ai_start) || ai_src_addr !== 32'h8000_0100 || ai_dst_addr !== 32'h8000_0200 || ai_length !== 64) begin
      $fatal(1, "AI CSR descriptor mismatch");
    end
    // A running engine owns its descriptor.  Parameter writes must be
    // rejected until the status busy bit drops.
    ai_status = 32'h0000_0001;
    csr_write(32'h1001_0008, 32'h8000_0990, 4'hf, 1'b1);
    ai_status = 32'h0000_0000;

    csr_write(32'h1001_1008, 32'h8000_0300, 4'hf, 1'b0);
    csr_write(32'h1001_100c, 32'h8000_0400, 4'hf, 1'b0);
    csr_write(32'h1001_1010, 32'd128, 4'hf, 1'b0);
    csr_write(32'h1001_1014, 32'd32, 4'hf, 1'b0);
    csr_write(32'h1001_1000, 32'h0000_0001, 4'hf, 1'b0);
    if (!(dma_start_seen || dma_start) || dma_src_addr !== 32'h8000_0300 || dma_dst_addr !== 32'h8000_0400 || dma_length !== 128 || dma_stride !== 32)
      $fatal(1, "DMA CSR descriptor mismatch");
    dma_status = 32'h0000_0001;
    csr_write(32'h1001_100c, 32'h8000_0aa0, 4'hf, 1'b1);
    dma_status = 32'h0000_0000;

    csr_write(32'h1000_1000, 32'h0000_0003, 4'hf, 1'b0);
    csr_write(32'h1000_1008, 32'h0000_0055, 4'hf, 1'b0);
    if (qspi_control !== 32'h3 || qspi_txdata !== 32'h55) $fatal(1, "QSPI CSR write failed");
    qspi_rxdata = 32'hcafe_beef;
    csr_read(32'h1000_100c, rd, 1'b0);
    if (rd !== 32'hcafe_beef) $fatal(1, "QSPI RX read failed");

    csr_write(32'h1000_0024, 32'h0000_003e, 4'hf, 1'b0);
    @(negedge clk); ai_done_irq = 1'b1;
    @(negedge clk); ai_done_irq = 1'b0;
    repeat (1) @(posedge clk);
    if (!irq_pending[1] || !external_irq) $fatal(1, "AI done IRQ was not latched");
    csr_read(32'h1000_0020, rd, 1'b0);
    if (!rd[1]) $fatal(1, "pending CSR read missing AI bit");
    csr_write(32'h1000_0028, 32'h0000_0002, 4'hf, 1'b0);
    @(posedge clk); @(negedge clk);
    if (irq_pending[1] || external_irq) begin
      $fatal(1, "IRQ clear failed");
    end

    @(negedge clk); dma_error_irq = 1'b1;
    @(negedge clk); dma_error_irq = 1'b0;
    repeat (1) @(posedge clk);
    if (!irq_pending[4]) $fatal(1, "DMA error IRQ was not latched");
    csr_write(32'h1000_0028, 32'h0000_0010, 4'hf, 1'b0);
    csr_read(32'h2000_0000, rd, 1'b1);
    $display("PGL50H CSR/interrupt contract PASS");
    $finish;
  end
endmodule
