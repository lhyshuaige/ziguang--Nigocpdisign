// Real-board PDS build list.  The generated IP directories are deliberately
// not part of the default Verilator list because they contain Logos PHY
// primitives and vendor .vp sources.
-f pgl50h_soc.f

// Define these in the PDS project (or add them as Verilog macro definitions).
// PGL50H_USE_PDS_PLL
// PGL50H_USE_PDS_DDR3

// Generated top-level instances.
../ip/pll/pgl50h_pll_50m_to_100m.v
../ip/ddr3/pgl50h_hmic_ddr3.v
../ip/ddr3/pgl50h_hmic_ddr3_ddrphy_top.v
../ip/ddr3/rtl/ipsxb_rst_sync_v1_1.v
../ip/ddr3/rtl/pll/ipsxb_ddrphy_pll_v1_0.v
../ip/ddr3/rtl/ddrphy/ipsxb_ddrphy_slice_top_v1_5.v

// Add the generated HMIC controller/PHY sources through the PDS project file
// project/NAX/ip/ddr3/pnr/pgl50h_hmic_ddr3.pds.  That project contains the
// complete source set and the Bank3 FBG484 DDR3 constraints.
