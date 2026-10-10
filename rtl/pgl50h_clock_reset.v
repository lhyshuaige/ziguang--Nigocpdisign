// PGL50H clock/reset boundary.
//
// The default build is intentionally primitive-free so that the SoC can be
// linted and simulated without PDS generated IP.  A PDS project can define
// PGL50H_USE_PDS_PLL and add the generated PLL plus
// pgl50h_pds_pll_wrapper.v to the PDS source list.

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

`ifdef PGL50H_USE_PDS_PLL
  pgl50h_pds_pll_wrapper u_pgl50h_pll (
    .clk_in(clk_50m),
    .reset_n(reset_ext_n),
    .clk_out(pll_clk),
    .locked(pll_lock)
  );
`else
  // Simulation/bring-up fallback.  The PDS PLL wrapper is the place where
  // 50 MHz is converted to the selected CPU/AXI frequency on the board.
  assign pll_clk  = clk_50m;
  assign pll_lock = 1'b1;
`endif

  // The generated HMIC exposes its AXI/user clock as ddrphy_clkin.  Selecting
  // it for the real DDR build keeps the CPU bridge and HMIC in one clock
  // domain; the standalone 50->100 MHz PLL remains the normal no-DDR clock.
  wire selected_clk = use_external_clk ? clk_sys_ext : pll_clk;
  wire selected_lock = use_external_clk ? (pll_lock & ext_pll_locked) : pll_lock;
  assign clk_sys    = selected_clk;
  assign pll_locked = selected_lock;

  reg [RESET_SYNC_STAGES-1:0] reset_pipe;

  // Asynchronous assertion, synchronous release.  DDR init_done is sampled
  // in the system clock domain; the PDS DDR wrapper must hold it low until
  // its own PHY training has completed.
  always @(posedge clk_sys or negedge reset_ext_n) begin
    if (!reset_ext_n) begin
      reset_pipe <= {RESET_SYNC_STAGES{1'b0}};
    end else if (!selected_lock || !ddr_init_done) begin
      reset_pipe <= {RESET_SYNC_STAGES{1'b0}};
    end else begin
      reset_pipe <= {reset_pipe[RESET_SYNC_STAGES-2:0], 1'b1};
    end
  end

  assign soc_reset_n = reset_pipe[RESET_SYNC_STAGES-1];
  assign soc_reset   = !soc_reset_n;

endmodule
