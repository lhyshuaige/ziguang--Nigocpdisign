`timescale 1ns/1ps

// Compatibility shell for the original peripheral-bus interface.
// The architectural decode now lives in pgl50h_csr_fabric.  Keeping this
// wrapper preserves the legacy port list while the AXI-fabric mode instantiates
// the CSR block directly.
module pgl50h_peripherals (
  input  wire        clk,
  input  wire        reset,
  input  wire        cmd_valid,
  input  wire        cmd_write,
  input  wire [31:0] cmd_addr,
  input  wire [31:0] cmd_wdata,
  input  wire  [3:0] cmd_wstrb,
  output wire        cmd_ready,
  output wire        rsp_valid,
  output wire [31:0] rsp_rdata,
  output wire        rsp_error,
  input  wire  [7:0] keys,
  output wire  [7:0] leds,
  output wire        timer_irq,
  output wire [63:0] mtime_value,
  output wire        ai_start,
  output wire [31:0] ai_control,
  output wire [31:0] ai_src_addr,
  output wire [31:0] ai_dst_addr,
  output wire [31:0] ai_length,
  input  wire [31:0] ai_status_value
);

  wire [5:0] irq_enable;
  wire [5:0] irq_clear;
  wire [5:0] irq_pending;
  wire [31:0] ai_channels_unused;
  wire [31:0] ai_scale_unused;
  wire        dma_start_unused;
  wire [31:0] dma_control_unused, dma_src_unused, dma_dst_unused;
  wire [31:0] dma_length_unused, dma_stride_unused;
  wire [31:0] dma_src_stride_unused, dma_dst_stride_unused;
  wire [31:0] dma_image_width_unused, dma_image_height_unused;
  wire [31:0] dma_output_width_unused, dma_output_height_unused;
  wire [31:0] qspi_control_unused, qspi_txdata_unused;
  wire        irq_unused;

  pgl50h_csr_fabric u_csr (
    .clk(clk), .reset(reset),
    .cmd_valid(cmd_valid), .cmd_write(cmd_write), .cmd_addr(cmd_addr),
    .cmd_wdata(cmd_wdata), .cmd_wstrb(cmd_wstrb), .cmd_ready(cmd_ready),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_error(rsp_error),
    .keys(keys), .leds(leds), .timer_irq(timer_irq), .mtime_value(mtime_value),
    .ai_status(ai_status_value),
    .ai_start(ai_start), .ai_control(ai_control), .ai_src_addr(ai_src_addr),
    .ai_dst_addr(ai_dst_addr), .ai_length(ai_length),
    .ai_channels(ai_channels_unused), .ai_scale(ai_scale_unused),
    .dma_status(32'h0), .dma_start(dma_start_unused), .dma_control(dma_control_unused), .dma_src_addr(dma_src_unused),
    .dma_dst_addr(dma_dst_unused), .dma_length(dma_length_unused), .dma_stride(dma_stride_unused),
    .dma_src_stride(dma_src_stride_unused), .dma_dst_stride(dma_dst_stride_unused),
    .dma_image_width(dma_image_width_unused), .dma_image_height(dma_image_height_unused),
    .dma_output_width(dma_output_width_unused), .dma_output_height(dma_output_height_unused),
    .qspi_status(32'h0), .qspi_rxdata(32'h0), .qspi_control(qspi_control_unused), .qspi_txdata(qspi_txdata_unused),
    .irq_enable(irq_enable), .irq_clear(irq_clear), .irq_pending(irq_pending)
  );

  // The legacy shell has no external IRQ pin.  It still instantiates the
  // sticky collector so timer/AI sources obey the same clear semantics when
  // the shell is used in a larger integration.
  pgl50h_interrupt_aggregator u_irq (
    .clk(clk), .reset(reset),
    .timer_irq(timer_irq),
    .ai_done_irq(ai_status_value[1]),
    .ai_error_irq(ai_status_value[2]),
    .dma_done_irq(1'b0), .dma_error_irq(1'b0), .qspi_irq(1'b0),
    .enable(irq_enable), .clear(irq_clear), .pending(irq_pending), .irq(irq_unused)
  );

endmodule
