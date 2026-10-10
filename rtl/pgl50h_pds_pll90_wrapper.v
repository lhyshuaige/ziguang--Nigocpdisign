// Port-normalizing wrapper for the generated 50 MHz -> 90 MHz Pango PLL.
module pgl50h_pds_pll90_wrapper (
  input  wire clk_in,
  input  wire reset_n,
  output wire clk_out,
  output wire locked
);
  wire clk_out4_unused;

  pgl50h_pll_50m_to_90m u_generated_pll (
    .clkin1  (clk_in),
    .clkout0 (clk_out),
    .clkout4 (clk_out4_unused),
    .pll_lock(locked)
  );

  wire unused_reset = reset_n ^ clk_out4_unused;
endmodule
