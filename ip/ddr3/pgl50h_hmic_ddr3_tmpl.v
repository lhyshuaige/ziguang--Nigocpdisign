// Created by IP Generator (Version 2022.2-SP6.7.1 build 188940)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


pgl50h_hmic_ddr3 the_instance_name (
  .ref_clk(ref_clk),                // input
  .resetn(resetn),                  // input
  .ddr_init_done(ddr_init_done),    // output
  .ddrphy_clkin(ddrphy_clkin),      // output
  .pll_lock(pll_lock)               // output
);
