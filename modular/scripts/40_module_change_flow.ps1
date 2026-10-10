param(
  [Parameter(Mandatory=$true)][ValidateSet('ai','dma','axi_fabric')][string]$ChangedModule,
  [Parameter(Mandatory=$true)][string]$NewMapDb,
  [string]$ParentPlacementDb = 'D:\PDS\project\NAX\pds\snapshots\pgl50h_soc_cdc_reset_setup_m0017_20261007\pds\pgl50h_hmic_cdc_reset_20261007\place_route\pgl50h_top_plc.adf',
  [string]$PdsShell = 'D:\PDS\PDSAPP\PDS_2022.2-SP6.7.1\PDS_2022\PDS_2022.2-SP6.7.1-ads\bin\pds_shell.exe'
)

$root = 'D:\PDS\project\NAX'
$template = Join-Path $root 'modular\scripts\20_reuse_parent_placement.tcl'
$log = Join-Path $root ("modular\reports\incremental_{0}_{1}.log" -f $ChangedModule,(Get-Date -Format 'yyyyMMdd_HHmmss'))
$script = Join-Path $env:TEMP ("pgl50h_incremental_{0}_{1}.tcl" -f $ChangedModule,(Get-Date -Format 'yyyyMMdd_HHmmssfff'))
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
$tcl = Get-Content -LiteralPath $template -Raw
$tcl = $tcl.Replace('set MAP_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/device_map/pgl50h_top_map.adf"', ('set MAP_DB "{0}"' -f ($NewMapDb -replace '\\','/')))
$tcl = $tcl.Replace('set PLC_DB "D:/PDS/project/NAX/pds/snapshots/pgl50h_soc_cdc_reset_setup_m0017_20261007/pds/pgl50h_hmic_cdc_reset_20261007/place_route/pgl50h_top_plc.adf"', ('set PLC_DB "{0}"' -f ($ParentPlacementDb -replace '\\','/')))
Set-Content -LiteralPath $script -Value $tcl -Encoding ascii
& $PdsShell -f $script *> $log
$runCode = $LASTEXITCODE
Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
if ($runCode -ne 0) { throw "PDS incremental run failed; see $log" }
Write-Host "Changed module: $ChangedModule"
Write-Host "New map DB: $NewMapDb"
Write-Host "Parent placement was supplied through -input_place_db_file. Review $log and the generated timing reports before accepting the change."
