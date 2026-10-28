// INT8 AI accelerator integration point.
//
// This first SoC increment only provides the software-visible control/status
// handshake.  The real INT8 MAC/tiling engine and its AXI master will replace
// this module without changing the CPU CSR map.

module pgl50h_ai_accel_stub (
  input  wire        clk,
  input  wire        reset,
  input  wire        start,
  input  wire [31:0] control,
  input  wire [31:0] src_addr,
  input  wire [31:0] dst_addr,
  input  wire [31:0] length,
  output wire [31:0] status
);

  reg       busy_reg;
  reg       done_reg;
  reg       error_reg;
  reg [7:0] progress_reg;

  // Keep configuration inputs explicit until the real DMA/compute datapath
  // consumes them.  This prevents the integration boundary from changing.
  wire unused_cfg;
  assign unused_cfg = control[0] ^ src_addr[0] ^ dst_addr[0] ^ length[0];

  always @(posedge clk) begin
    if (reset) begin
      busy_reg     <= 1'b0;
      done_reg     <= 1'b0;
      error_reg    <= 1'b0;
      progress_reg <= 8'h00;
    end else begin
      if (start && !busy_reg) begin
        busy_reg     <= 1'b1;
        done_reg     <= 1'b0;
        error_reg    <= 1'b0;
        progress_reg <= 8'd16;
      end else if (busy_reg && (progress_reg != 8'h00)) begin
        progress_reg <= progress_reg - 8'd1;
      end else if (busy_reg) begin
        busy_reg <= 1'b0;
        done_reg <= 1'b1;
      end
    end
  end

  assign status = {29'h0, error_reg, done_reg, busy_reg};

endmodule
