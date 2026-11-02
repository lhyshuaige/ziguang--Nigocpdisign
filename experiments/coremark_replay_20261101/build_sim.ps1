param([string]$VerilatorRoot='D:\PDS\Verilator',[string]$GccBin='D:\PDS\w64devkit\w64devkit\bin')
$ErrorActionPreference='Stop'
$taskDir=$PSScriptRoot
$record=Get-Content -LiteralPath (Join-Path $taskDir 'sim\sources.json') -Raw | ConvertFrom-Json
$taskObj=Join-Path $taskDir 'sim\build'
New-Item -ItemType Directory -Path $taskObj -Force | Out-Null
$env:PATH="$GccBin;$VerilatorRoot\bin;$env:PATH"
$env:VERILATOR_ROOT=$VerilatorRoot.Replace('\','/')
$taskSources=@($record.compile_sources | ForEach-Object { (Join-Path $taskDir $_).Replace('\','/') })
& (Join-Path $VerilatorRoot 'bin\verilator.exe') --cc --exe --Mdir $taskObj --top-module pgl50h_soc_coremark_tb --language 1800-2012 --Wall -Wno-fatal -CFLAGS '-O2 -std=c++17' @taskSources *> (Join-Path $taskObj 'elaborate.log')
if($LASTEXITCODE -ne 0){throw 'Verilator elaboration failed'}
$taskCxx=(Join-Path $GccBin 'g++.exe').Replace('\','/')
& (Join-Path $GccBin 'make.exe') -C $taskObj -f Vpgl50h_soc_coremark_tb.mk -j 4 "CXX=$taskCxx" "LINK=$taskCxx" *> (Join-Path $taskObj 'build.log')
if($LASTEXITCODE -ne 0){throw 'Simulator compilation failed'}
Write-Output 'SIMULATOR_BUILD_PASS'
