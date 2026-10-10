param(
  [string]$SetupReport = 'D:\\PDS\\project\\NAX\\pds\\b11_local_bypass_20261008\\report_timing\\pgl50h_top_setup.rtr',
  [string]$HoldReport  = 'D:\\PDS\\project\\NAX\\pds\\b11_local_bypass_20261008\\report_timing\\pgl50h_top_hold.rtr',
  [string]$Output      = 'D:\\PDS\\project\\NAX\\docs\\cpu_partition_signoff_20261008.md'
)

function Get-CpuPaths([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $text = Get-Content -LiteralPath $Path -Raw
  $sections = [regex]::Split($text, '(?=Startpoint\s+:)')
  $rows = @()
  foreach ($section in $sections) {
    $sp = [regex]::Match($section, 'Startpoint\s+:\s+([^\r\n]+)')
    $ep = [regex]::Match($section, 'Endpoint\s+:\s+([^\r\n]+)')
    if (-not $sp.Success -or -not $ep.Success) { continue }
    if ($sp.Groups[1].Value -notmatch 'u_soc_core/u_cpu' -or
        $ep.Groups[1].Value -notmatch 'u_soc_core/u_cpu') { continue }
    $slacks = [regex]::Matches($section, 'Slack\s+\([^\)]*\)\s+(-?\d+\.\d+)')
    foreach ($m in $slacks) {
      $rows += [pscustomobject]@{
        Startpoint = $sp.Groups[1].Value.Trim()
        Endpoint   = $ep.Groups[1].Value.Trim()
        SlackNs    = [double]$m.Groups[1].Value
      }
    }
  }
  return $rows
}

$setup = @(Get-CpuPaths $SetupReport)
$hold = @(Get-CpuPaths $HoldReport)
$setupWns = if ($setup.Count) { ($setup | Measure-Object SlackNs -Minimum).Minimum } else { $null }
$holdWhs = if ($hold.Count) { ($hold | Measure-Object SlackNs -Minimum).Minimum } else { $null }

$lines = @(
  '# CPU partition timing signoff (SoC-context report)',
  '',
  'This report filters paths whose startpoint and endpoint are both under `u_soc_core/u_cpu` from the successful full-SoC P&R database. CPU placement is therefore the parent placement; no standalone re-placement is implied.',
  '',
  '| Metric | Result |',
  '|---|---:|',
  "| Clock | `pll_clk_sys`, 100 MHz |",
  "| CPU setup WNS | $setupWns ns |",
  "| CPU setup path count | $($setup.Count) |",
  "| CPU hold minimum slack | $holdWhs ns |",
  "| CPU hold path count | $($hold.Count) |",
  '',
  '## Worst CPU setup endpoints',
  ''
)
foreach ($row in ($setup | Sort-Object SlackNs | Select-Object -First 10)) {
  $lines += "- $($row.SlackNs) ns: $($row.Startpoint) -> $($row.Endpoint)"
}
Set-Content -LiteralPath $Output -Value ($lines -join [Environment]::NewLine)
Write-Output "CPU setup WNS = $setupWns ns; CPU hold minimum slack = $holdWhs ns; setup paths = $($setup.Count); hold paths = $($hold.Count)"
