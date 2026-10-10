# DDR CDC reset PDS rerun (2026-10-07)

Both isolated projects rebuilt the current `NaxRiscvContest.v` A2 baseline and
the new `pgl50h_ddr_cdc_reset` RTL, then completed compile, ADS synthesis,
device mapping, placement, routing, and independent post-route max/min timing
reports. The HMIC clock-group experiment and the original SoC constraints were
run separately, preserving the previous projects and reports.

| Final post-route metric | HMIC clock-group experiment | Original SoC constraints |
|---|---:|---:|
| `pll_clk_sys` slow setup WNS / failing endpoints | -0.017 ns / 2 | -0.364 ns / 7 |
| `ddrphy_clkin` slow setup WNS | +1.815 ns | +0.991 ns |
| `ddrphy_clkin -> clk_50m` slow setup WNS | excluded | -0.512 ns / 15 |
| `pll_clk_sys` slow/fast hold WHS | +0.138 / +0.092 ns | -0.102 / -0.070 ns |
| `ddrphy_clkin` slow/fast hold WHS | +0.171 / +0.100 ns | -0.175 / -0.181 ns |
| `ddrphy_clkin` slow/fast removal WHS | +0.506 / +0.306 ns | +0.537 / +0.369 ns |
| `clk_50m -> ddrphy_clkin` slow/fast removal WHS | excluded | -5.302 / -3.274 ns; 1624 failing endpoints |
| `clk_50m -> ioclk_gate_clk` slow/fast hold WHS | excluded | -1.384 / -0.668 ns |
| Routed | yes | yes |

The new reset module synthesized as two DDR-clocked `GTP_DFF_P` registers,
asynchronously preset by the reset request. Compared with the earlier
clock-group run, mapped use increased from 21,237 LUT / 16,973 FF to
21,238 LUT / 16,975 FF.

The original-constraint removal critical path still starts at the vendor HMIC
`u_ddrp_rstn_sync/sig_async_r2` in the 50 MHz domain and ends at an HMIC
controller asynchronous reset pin in the DDR domain. The SoC CDC-side reset
change cannot repair that internal HMIC path. The clock-group run excludes it;
its positive reported removal slack is **not** proof that the vendor path was
physically fixed. The original-constraint result is not timing closure.

The final independent reports are `pgl50h_top_setup.rtr` and
`pgl50h_top_hold.rtr` in this directory and in sibling directory
`pgl50h_hmic_cdc_reset_original_20261007`. Earlier PNR timing summaries are
intermediate snapshots and are not used for the table above. Board-level DDR
training and reset sequencing remain unverified without hardware.
