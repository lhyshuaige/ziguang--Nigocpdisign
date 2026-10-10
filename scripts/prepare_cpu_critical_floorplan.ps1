param(
    [string]$ProjectRoot = 'D:\PDS\project\NAX',
    [string]$RegionName = 'cpu_rf_alu_local',
    [string]$RegionGeometry = '3 40 3 36'
)

$timingPath = Join-Path $ProjectRoot 'pds\pgl50h\report_timing\pgl50h_top_all_setup_violations.rtr'
$netlistPath = Join-Path $ProjectRoot 'pds\pgl50h\place_route\pgl50h_top_pnr.netlist'
$projectPcfPath = Join-Path $ProjectRoot 'constraints\pgl50h_cpu_div_floorplan.pcf'
$mappedPcfPath = Join-Path $ProjectRoot 'pds\pgl50h\device_map\pgl50h_top.pcf'
$fragmentPath = Join-Path $ProjectRoot 'constraints\pgl50h_cpu_critical_floorplan_fragment.pcf'

$netlistLines = Get-Content -LiteralPath $netlistPath
$instances = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
for ($i = 0; $i -lt ($netlistLines.Count - 1); $i++) {
    if ($netlistLines[$i] -eq 'Inst') {
        [void]$instances.Add(($netlistLines[$i + 1] -split ';', 2)[0])
    }
}

$selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

# Keep the mirrored integer RF payload DRMs together.  The distributed-RAM
# location table is deliberately left free: it is a control/select side cone,
# and constraining it with the data cone caused local routing congestion.
foreach ($instance in $instances) {
    if ($instance -match '^u_soc_core/u_cpu/integer_RegFilePlugin_logic_regfile_fpga/banks_0_ram/ram_[0-9]+/iGopDrm$') {
        [void]$selected.Add($instance)
    }
}

# Add every mapped cell traversed by an actually failing RF-read -> RF-write
# timing path.  Matching against the post-route netlist avoids stale generated
# names and keeps this fragment valid for the current CPU build only.
$reportText = Get-Content -LiteralPath $timingPath -Raw
foreach ($block in ($reportText -split '(?=Startpoint  :)')) {
    if ($block -notmatch 'Startpoint\s+:\s+([^\r\n]+)') { continue }
    $startpoint = $matches[1]
    if ($block -notmatch 'Endpoint\s+:\s+([^\r\n]+)') { continue }
    $endpoint = $matches[1]
    if (($startpoint -notmatch '/u_cpu/.+banks_0_ram/ram_') -or
        ($endpoint -notmatch '/u_cpu/.+banks_0_ram/ram_')) { continue }

    foreach ($line in ($block -split '\r?\n')) {
        if ($line -notmatch 'u_soc_core/u_cpu/') { continue }
        $logical = ($line -split '\s{2,}')[-1].Trim()
        if ($logical -match '^(.*)/(?:F|Z|Y[0-9A-Z]*|Cout|DOA\[[0-9]+\]|DOB\[[0-9]+\]|DIA\[[0-9]+\]|DIB\[[0-9]+\]|CLKA|CLKB)$') {
            $candidate = $matches[1]
            if ($instances.Contains($candidate)) {
                [void]$selected.Add($candidate)
            }
        }
    }
}

# PDS may rename packed/permuted cells after route.  The timing report uses
# those post-route names, while a fresh PNR constraint is checked against the
# pre-placement map.  If a validation run identified such names, drop only
# those rejected aliases and retain the stable mapped instances.
$placeRouteRoot = Join-Path $ProjectRoot 'pds\pgl50h\place_route'
$validationLogs = [System.Collections.Generic.List[string]]::new()
$currentPnrLog = Join-Path $placeRouteRoot 'run.log'
if (Test-Path -LiteralPath $currentPnrLog) {
    $validationLogs.Add($currentPnrLog)
}
$logBackupRoot = Join-Path $placeRouteRoot 'logbackup'
if (Test-Path -LiteralPath $logBackupRoot) {
    foreach ($logFile in (Get-ChildItem -LiteralPath $logBackupRoot -Filter '*.log' -File)) {
        $validationLogs.Add($logFile.FullName)
    }
}
foreach ($pnrLogPath in $validationLogs) {
    foreach ($line in (Get-Content -LiteralPath $pnrLogPath)) {
        if ($line -match 'PhysicalConstraintEditor-0023:.* Instance (\S+) in the def_inst_region command cannot be found') {
            [void]$selected.Remove($matches[1])
        }
    }
}

$markerBegin = '# BEGIN CODEX CPU RF/ALU CRITICAL FLOORPLAN'
$markerEnd = '# END CODEX CPU RF/ALU CRITICAL FLOORPLAN'
$fragment = [System.Collections.Generic.List[string]]::new()
$fragment.Add($markerBegin)
$fragment.Add('# Generated from the exhaustive post-route CPU setup report.')
$fragment.Add('def_region {cpu_div_radix4} 18 36 8 26')
$fragment.Add('def_inst_region {u_soc_core/u_cpu/EU0_DivPlugin_logic_div/N15.fsub_1/gateop_A2} {cpu_div_radix4}')
$fragment.Add('def_inst_region {u_soc_core/u_cpu/EU0_DivPlugin_logic_div/N18_1.fsub_1/gateop_A2} {cpu_div_radix4}')
$fragment.Add('def_inst_region {u_soc_core/u_cpu/EU0_DivPlugin_logic_div/N21.fsub_1/gateop_A2} {cpu_div_radix4}')
$fragment.Add("def_region {$RegionName} $RegionGeometry")
foreach ($instance in ($selected | Sort-Object)) {
    $fragment.Add("def_inst_region {$instance} {$RegionName}")
}
$fragment.Add($markerEnd)

Set-Content -LiteralPath $fragmentPath -Value $fragment -Encoding ascii

foreach ($pcfPath in @($projectPcfPath, $mappedPcfPath)) {
    $existing = Get-Content -LiteralPath $pcfPath
    $cleaned = [System.Collections.Generic.List[string]]::new()
    $inside = $false
    foreach ($line in $existing) {
        if ($line -eq $markerBegin) { $inside = $true; continue }
        if ($line -eq $markerEnd) { $inside = $false; continue }
        if (-not $inside) { $cleaned.Add($line) }
    }
    $cleaned.Add('')
    foreach ($line in $fragment) { $cleaned.Add($line) }
    Set-Content -LiteralPath $pcfPath -Value $cleaned -Encoding ascii
    Write-Output "Updated PCF: $pcfPath"
}

Write-Output "CPU floorplan fragment: $fragmentPath"
Write-Output "Constrained mapped instances: $($selected.Count)"
