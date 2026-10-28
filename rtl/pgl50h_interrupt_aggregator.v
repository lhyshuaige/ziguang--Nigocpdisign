`timescale 1ns/1ps

// Sticky interrupt collector for the SoC peripheral fabric.
//
// Bit assignment is architectural and is shared with pgl50h_csr_fabric:
//   [0] timer, [1] AI done, [2] AI error,
//   [3] DMA done, [4] DMA error, [5] QSPI.
// Source edges are latched so a one-cycle completion pulse cannot be lost.
// A level source (for example timer) is re-armed only after it deasserts,
// which makes write-one-to-clear deterministic while software services it.
module pgl50h_interrupt_aggregator (
  input  wire       clk,
  input  wire       reset,
  input  wire       timer_irq,
  input  wire       ai_done_irq,
  input  wire       ai_error_irq,
  input  wire       dma_done_irq,
  input  wire       dma_error_irq,
  input  wire       qspi_irq,
  input  wire [5:0] enable,
  input  wire [5:0] clear,
  output reg  [5:0] pending,
  output wire       irq
);

  wire [5:0] source_level = {qspi_irq, dma_error_irq, dma_done_irq,
                              ai_error_irq, ai_done_irq, timer_irq};
  reg [5:0] source_seen;
  wire [5:0] source_event = source_level & ~source_seen;

  assign irq = |(pending & enable);

  always @(posedge clk) begin
    if (reset) begin
      pending    <= 6'h00;
      source_seen <= 6'h00;
    end else begin
      source_seen <= source_level;
      pending <= (pending & ~clear) | source_event;
    end
  end

endmodule
