# PGL50H generated IP

The SoC has two build paths:

* The default RTL/simulation path uses the primitive-free clock and DDR
  boundaries.  It is the path used by Verilator and the contract testbenches.
* The board path defines `PGL50H_USE_PDS_PLL` and `PGL50H_USE_PDS_DDR3` in PDS.
  Add `rtl/pgl50h_soc_pds.f`, the generated PLL Verilog, and the generated
  HMIC PDS project `ip/ddr3/pnr/pgl50h_hmic_ddr3.pds` to the PDS project.

The checked-in instance descriptions are the regeneration source of truth:

* `pll/pgl50h_pll_50m_to_100m.idf`: 50 MHz input, 100 MHz `clkout0`.
* `ddr3/pgl50h_hmic_ddr3.idf`: PGL50H/FBG484, Bank3, DDR3 x32, 50 MHz
  reference clock, 800 MT/s target rate, 15/10/3 row/column/bank geometry.

Run Pango's `ip_generate.exe` from the PDS installation to regenerate either
directory.  Do not hand-edit generated `.v`, `.vp`, `.fdc`, or `.pds` files.
The generated HMIC project emits `ddr3_test.fdc`, which contains the board
pin map and generated-clock constraints for the Bank3 DDR3 interface.
The SoC wrapper-level clock/user-I/O/DDR net names are listed separately in
`../constraints/pgl50h_top_pins.fdc`; import both files in the final PDS top
project and resolve any Pin Planner duplicate/override report against the
board revision being used.
