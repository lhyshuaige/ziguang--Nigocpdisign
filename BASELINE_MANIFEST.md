# PGL50H SoC baseline package

This directory is a clean, reviewable copy of the current baseline used for the
PGL50H SoC work. The active CPU RTL is the contest implementation below; no
experimental CPU candidate is selected by the source lists.

## Baseline identity

- Device: PGL50H
- PDS: 2022.2-SP6.7.1
- Top: `pgl50h_top`
- System clock: `pll_clk_sys`, 100 MHz, 10 ns
- DDR user clock: `ddrphy_clkin`, 100 MHz
- CPU RTL: `rtl/NaxRiscvContest.v`
- CPU RTL SHA-256: `B88BBD0AA5F60B591BDC3C60D8D70C0AD1720F095A20DC1C1F9AE5C1C7FA3262`
- Reference PDS snapshot: `pds_baseline/`
- Reference setup WNS: `-0.017 ns` on `pll_clk_sys`
- Reference DDR setup WNS: `+1.815 ns` on `ddrphy_clkin`

## Directory map

| Directory | Contents |
|---|---|
| `rtl/` | Active CPU, SoC, AXI, DMA, AI, clock/reset and DDR boundary RTL plus source lists |
| `ip/` | Generated PLL and PDS HMIC DDR3 IP sources |
| `constraints/` | Baseline top pins, SoC timing and HMIC constraints; no experiment-only floorplans |
| `tb/` | Baseline/general module and SoC testbenches |
| `sim/coremark_soc/` | CoreMark image, baseline runner, and baseline logs; no object caches |
| `modular/` | Module contracts, manifest, timing budget and hierarchy-flow scripts |
| `scripts/` | Existing audit/build/report scripts from the source project |
| `pds_baseline/` | Full `pgl50h_soc_cdc_reset_setup_m0017_20261007` source, PDS database, reports and reference constraints |
| `docs/` | Baseline validation, timing and modular-flow notes |

## Reproduction entry points

- Simulation source list: `rtl/pgl50h_soc.f`
- PDS source list: `rtl/pgl50h_soc_pds.f`
- CoreMark runner: `sim/coremark_soc/run_coremark_soc_verilator.ps1`
- Baseline PDS implementation database: `pds_baseline/pds/pgl50h_hmic_cdc_reset_20261007/`
- Module contract: `modular/interface_contract.md`
- Module metadata: `modular/module_manifest.json`

## Deliberately excluded

Date-suffixed candidate RTL, candidate-specific CoreMark images and testbenches,
experimental CPU floorplans/PCFs, and Verilator/PDS object caches are not in the
active package. They remain in the original `NAX` project for historical audit.

The reference PDS snapshot is retained because it is the authoritative baseline
for placement/routing and timing comparison; it is not a claim that the design
has been validated on physical hardware.
