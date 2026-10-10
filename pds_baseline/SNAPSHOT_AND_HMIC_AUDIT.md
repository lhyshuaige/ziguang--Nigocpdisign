# PGL50H SoC snapshot and HMIC constraint audit — 2026-10-07

## Snapshot identity

This is a frozen copy of the routed **HMIC clock-group experiment** with the
SoC-owned DDR CDC reset synchronizer. It is a comparison baseline, **not** a
timing-closed or board-validated release. Do not rerun PDS in this directory;
copy it to a new work directory first so the reports remain unchanged. The
bundled `run_hmic_cdc_reset.tcl` contains the original absolute project path;
point `open_project` and the report-copy commands to the copied project before
rerunning. The actual PGL50H project is
`pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_soc_hmic_clockgroup_PGL50H.pds`;
`run_hmic_cdc_reset.pds` is a PDS shell-generated auxiliary file.

- PDS: 2022.2-SP6.7.1, PGL50H-6FBG484, single routed run.
- `pll_clk_sys` slow setup WNS: **-0.017 ns**, 2 failing endpoints, TNS -0.019 ns.
- `ddrphy_clkin` slow setup WNS: +1.815 ns.
- `pll_clk_sys` hold WHS slow/fast: +0.138/+0.092 ns.
- `ddrphy_clkin` hold WHS slow/fast: +0.171/+0.100 ns.
- `ddrphy_clkin` removal WHS slow/fast: +0.506/+0.306 ns.
- Layout and routing completed; zero unrouted nets.

The snapshot contains the complete isolated PDS implementation directory,
all 85 Verilog source files listed in its project manifest, the two included
top-level RTL files, the board/SoC constraints, the generated HMIC IP IDF and
example FDC, and the installed PDS HMIC FDC template. All 85 project source
paths resolve inside the snapshot; the copied setup and hold reports have the
same SHA256 hashes as the original run. `reference/original_constraint_run/`
contains the independent timing reports from the same RTL rebuilt under the
unmodified SoC HMIC constraints.

| Key file | SHA256 |
|---|---|
| `rtl/NaxRiscvContest.v` | `B88BBD0AA5F60B591BDC3C60D8D70C0AD1720F095A20DC1C1F9AE5C1C7FA3262` |
| `rtl/pgl50h_soc_core.v` | `0E3C4661A125C743CBF81A25EA9467B40D60BB522A81C94B0B9A2988C9966AE0` |
| `rtl/pgl50h_axi_hmic_cdc.v` | `37BFA515C6CCC40D83E735AACBAE38BFA3DD95834FCC686D506A9C93C2335518` |
| `pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_hmic_soc_clockgroup_test.fdc` | `289330F13913ABB38385C355584DC5BE8556BD9FFFA0BFF56D658409C0981867` |
| `pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_top_setup.rtr` | `49A362BA77517BD14D97B328AE15F35900E4103308BCD10D32CE906ABFAE8B82` |
| `pds/pgl50h_hmic_cdc_reset_20261007/pgl50h_top_hold.rtr` | `5C7A920CCB1DFEE6157947C71CBB293D6BFD947AF2EC7F36A0126AE941395944` |

## Does the generated HMIC constraint apply to this instance?

**Yes for the identified HMIC-internal clock crossings, with SoC-specific
scope and verification; no as an unexamined whole-SoC timing waiver.**

1. The active generated IDF specifies PGL50H-6FBG484, Bank3, 32-bit DDR3,
   50 MHz reference, 800 MT/s, and `REGION_NUM=3`. The generated example
   `ip/ddr3/pnr/ddr_test.fdc` separately marks `ref_clk`, each `ioclk0..2`,
   and `ioclk_gate_clk` as asynchronous clock groups. The installed PDS
   template has the same group structure. Its PLL multiply/divide numbers
   differ from the instantiated example, but both describe 100 MHz
   `ddrphy_clkin` and 400 MHz IO clocks; the generated instance FDC is the
   source to adapt, not the generic installed template.
2. In the SoC hierarchy, example `I_ipsxb_ddr_top` maps to
   `u_ddr3/u_pds_ddr3/u_hmic`; example `ref_clk` maps to top `clk_50m`;
   HMIC `I_GTP_CLKDIV` supplies `ddrphy_clkin`. The PDS clock report resolves
   all of these generated clock roots. The example's `free_clk` belongs to
   its BIST wrapper and has no corresponding SoC clock; it was not copied.
   The SoC-only `pll_clk_sys` remains a separate clock, with its existing
   explicit asynchronous CDC grouping to `ddrphy_clkin`.
3. Under the unmodified SoC constraints, **all 1624** `clk_50m ->
   ddrphy_clkin` removal endpoints are HMIC-owned. The negative min report
   contains 3248 slow/fast async path records for these 1624 unique endpoints,
   with **zero** non-HMIC start/end records. The worst is -5.302 ns slow and
   -3.274 ns fast. The path starts at HMIC `u_ddrp_rstn_sync/sig_async_r2`
   (50 MHz) and ends on controller async-reset pins (`ddrphy_clkin`). The
   unprotected `ipsxb_rst_sync_v1_1.v` confirms a two-flop 50 MHz release
   stage; the HMIC top then distributes `ddr_rstn` to the DDR controller.
4. The other newly excluded families are also inside HMIC: 38
   `ddrphy_clkin -> clk_50m` training/reset-controller endpoints (15 fail
   setup in this routed original-constraint run), and the PHY gated-training
   clock controls (one negative hold endpoint in this run). The earlier full
   excluded-path audit found no CPU, AXI, AI, or DMA endpoint in those
   families. The current negative setup/min reports confirm HMIC ownership
   for every failing endpoint in these families.
5. The standalone generated HMIC example uses these clock groups and its
   routed PDS timing summary reports positive setup/hold/removal for its
   remaining timed domains. This supports applying the vendor model to the
   identical embedded HMIC instance. It does **not** prove analog reset
   behavior, DDR training, or board operation.

The experiment excludes the HMIC-internal crossings rather than physically
repairing them. The SoC CDC DDR-side reset synchronizer is separate: it
synthesizes as two DDR-clocked asynchronously preset flops and does not change
HMIC's vendor-owned `ddr_rstn` network. Because parts of the PHY reset
controller are protected IP, an end-to-end source-level proof of its reset
sequencing is unavailable here. Retain the original-constraint comparison and
re-audit the excluded endpoints if the HMIC IP, clock topology, or top-level
integration changes. Do not describe this snapshot as full 100 MHz closure:
its CPU setup still misses by 0.017 ns, and no physical board test has run.
