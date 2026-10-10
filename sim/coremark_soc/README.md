# PGL50H SoC CoreMark simulation

This flow runs the existing RV32IM CoreMark image through
`pgl50h_soc_core` with `USE_AXI_FABRIC=1`:

`NaxRiscvContest -> CPU AXI adapters -> four-master AXI fabric -> AXI4/HMIC adapter -> HMIC backing store`

The backing store is a 256 KiB, 32-bit-word model that implements the PGL50H
256-bit HMIC user-port contract. It replaces only the vendor DDR3 controller
and PHY at the simulation boundary; it does not bypass the SoC AXI path.

Run from PowerShell:

```powershell
Set-Location D:\PDS\project\NAX\sim\coremark_soc
& .\run_coremark_soc_verilator.ps1
```

The current validated run reports `Correct operation validated`,
`COREMARK_SOC_PASS`, `4.75 Coremark/MHz`, `2,163,260` simulation cycles,
`1,912` HMIC reads, and `96` HMIC writes. The CoreMark timer is a simulated
cycle counter, so the score is a functional baseline rather than a measured
board frequency result.
