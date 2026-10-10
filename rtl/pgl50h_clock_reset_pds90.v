// PDS timing-closure variant of the clock/reset boundary, using the generated
// 50 MHz -> 90 MHz PLL.  The 100 MHz implementation remains the production
// high-performance target; this file provides a board-safe closure baseline.
module pgl50h_clock_reset #(
  parameter integer RESET_SYNC_STAGES = 2
) (
  input  wire clk_50m,
  input  wire reset_ext_n,
  input  wire ddr_init_done,
  input  wire clk_sys_ext,
  input  wire ext_pll_locked,
  input  wire use_external_clk,
  output wire clk_sys,
  output wire pll_locked,
  output wire soc_reset,
  output wire soc_reset_n
);
  wire pll_clk;
  wire pll_lock;
  pgl50h_pds_pll90_wrapper u_pgl50h_pll (
    .clk_in(clk_50m), .reset_n(reset_ext_n), .clk_out(pll_clk), .locked(pll_lock)
  );
  wire selected_clk = use_external_clk ? clk_sys_ext : pll_clk;
  wire selected_lock = use_external_clk ? (pll_lock & ext_pll_locked) : pll_lock;
  assign clk_sys = selected_clk;
  assign pll_locked = selected_lock;

  reg [RESET_SYNC_STAGES-1:0] reset_pipe;
  always @(posedge clk_sys or negedge reset_ext_n) begin
    if (!reset_ext_n) reset_pipe <= {RESET_SYNC_STAGES{1'b0}};
    else if (!selected_lock || !ddr_init_done) reset_pipe <= {RESET_SYNC_STAGES{1'b0}};
    else reset_pipe <= {reset_pipe[RESET_SYNC_STAGES-2:0], 1'b1};
  end
  assign soc_reset_n = reset_pipe[RESET_SYNC_STAGES-1];
  assign soc_reset = !soc_reset_n;
endmodule
