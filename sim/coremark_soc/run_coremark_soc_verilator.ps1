param(
  [UInt64]$TimeoutCycles = 50000000
)

$ErrorActionPreference = 'Stop'

$simDir = (Resolve-Path $PSScriptRoot).Path
$rtlDir = (Resolve-Path (Join-Path $simDir '..\..\rtl')).Path
$tbDir = (Resolve-Path (Join-Path $simDir '..\..\tb')).Path
$coremarkSimDir = (Resolve-Path 'D:\PDS\project\NaxRiscv\pds\pgl50h\coremark_sim').Path
$repoDir = (Resolve-Path 'D:\PDS\project\NaxRiscv').Path
$elf = Join-Path $repoDir 'ext\NaxSoftware\baremetal\coremark\build\rv32im\coremark.elf'
$converter = Join-Path $coremarkSimDir 'elf32_to_hex.py'
$memh = Join-Path $simDir 'coremark.memh'
$verilator = 'D:\PDS\Verilator\bin\verilator.exe'
$w64bin = 'D:\PDS\w64devkit\w64devkit\bin'
$runner = Join-Path $simDir 'obj_dir\Vpgl50h_soc_coremark_tb.exe'

if (!(Test-Path $elf)) { throw "CoreMark ELF not found: $elf" }
if (!(Test-Path $converter)) { throw "ELF converter not found: $converter" }
if (!(Test-Path $verilator)) { throw "Verilator not found: $verilator" }
if (!(Test-Path (Join-Path $w64bin 'make.exe'))) { throw "GNU Make not found: $w64bin" }

$env:PATH = "$w64bin;D:\PDS\Verilator\bin;$env:PATH"
$env:VERILATOR_ROOT = 'D:/PDS/Verilator'

Write-Host '[1/3] Converting CoreMark ELF to the SoC HMIC backing-store image'
& python $converter $elf $memh
if ($LASTEXITCODE -ne 0) { throw 'ELF conversion failed' }

$sources = @(
  (Join-Path $rtlDir 'NaxRiscvContest.v'),
  (Join-Path $rtlDir 'pgl50h_clock_reset.v'),
  (Join-Path $rtlDir 'pgl50h_interrupt_aggregator.v'),
  (Join-Path $rtlDir 'pgl50h_csr_fabric.v'),
  (Join-Path $rtlDir 'pgl50h_ai_engine.v'),
  (Join-Path $rtlDir 'pgl50h_camera_dma.v'),
  (Join-Path $rtlDir 'pgl50h_cpu_axi_adapter.v'),
  (Join-Path $rtlDir 'pgl50h_axi4_hmic_adapter.v'),
  (Join-Path $rtlDir 'pgl50h_axi_hmic_cdc.v'),
  (Join-Path $rtlDir 'pgl50h_axi4_mem_fabric.v'),
  (Join-Path $rtlDir 'pgl50h_soc_core.v'),
  (Join-Path $tbDir 'pgl50h_soc_coremark_tb.v'),
  (Join-Path $tbDir 'pgl50h_soc_coremark_verilator.cpp')
)

Write-Host '[2/3] Building pgl50h_soc_core with AXI fabric and HMIC model'
Push-Location $simDir
try {
  $relativeSources = @(
    '../../rtl/NaxRiscvContest.v',
    '../../rtl/pgl50h_clock_reset.v',
    '../../rtl/pgl50h_interrupt_aggregator.v',
    '../../rtl/pgl50h_csr_fabric.v',
    '../../rtl/pgl50h_ai_engine.v',
    '../../rtl/pgl50h_camera_dma.v',
    '../../rtl/pgl50h_cpu_axi_adapter.v',
    '../../rtl/pgl50h_axi4_hmic_adapter.v',
    '../../rtl/pgl50h_axi_hmic_cdc.v',
    '../../rtl/pgl50h_axi4_mem_fabric.v',
    '../../rtl/pgl50h_soc_core.v',
    '../../tb/pgl50h_soc_coremark_tb.v',
    '../../tb/pgl50h_soc_coremark_verilator.cpp'
  )
  & $verilator --cc --exe --Mdir obj_dir --top-module pgl50h_soc_coremark_tb --language 1800-2012 --Wall -Wno-fatal -CFLAGS '-O2 -std=c++17' @relativeSources
  if ($LASTEXITCODE -ne 0) { throw 'Verilator code generation failed' }
  $gxx = 'D:/PDS/w64devkit/w64devkit/bin/g++.exe'
  & (Join-Path $w64bin 'make.exe') -C obj_dir -f Vpgl50h_soc_coremark_tb.mk -j 4 "CXX=$gxx" "LINK=$gxx"
  if ($LASTEXITCODE -ne 0) { throw 'Verilator C++ build failed' }
} finally {
  Pop-Location
}

Write-Host '[3/3] Running full SoC CoreMark'
if (!(Test-Path $runner)) { throw "Verilator executable not found: $runner" }
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $simDir
try {
  & $runner $TimeoutCycles 2>&1 | Tee-Object -FilePath (Join-Path $simDir 'coremark_soc_verilator.log')
  $runnerExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
$ErrorActionPreference = $oldErrorActionPreference
if ($runnerExitCode -ne 0) { throw 'SoC CoreMark did not pass; see coremark_soc_verilator.log' }
