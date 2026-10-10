// Port-normalizing wrapper for the PDS-generated Logos PLL.
//
// The generated IP keeps its native ports (clkin1/clkout0/clkout4/pll_lock).
// The SoC clock/reset boundary uses a small, stable interface so the generated
// file can be regenerated without changing the rest of the design.

module pgl50h_pds_pll_wrapper (
  input  wire clk_in,
  input  wire reset_n,
  output wire clk_out,
  output wire locked
);
  wire clk_out4_unused;

  pgl50h_pll_50m_to_100m u_generated_pll (
    .clkin1  (clk_in),
    .clkout0 (clk_out),
    .clkout4 (clk_out4_unused),
    .pll_lock(locked)
  );

  // The generated PLL has no reset pin.  Keep reset in the wrapper interface
  // so the board-level contract remains explicit and prevent an unused-input
  // warning in strict PDS lint flows.
  wire unused_reset = reset_n ^ clk_out4_unused;
endmodule
