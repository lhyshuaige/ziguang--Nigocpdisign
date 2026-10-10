param(
  [string]$Candidate = 'D:\PDS\project\NAX\rtl\NaxRiscvContest_r1r2_20260929.v',
  [string]$Baseline  = 'D:\PDS\project\NAX\rtl\NaxRiscvContest.v',
  [string]$Output    = 'D:\PDS\project\NAX\rtl\NaxRiscvContest_r1r2_rf_rep_20260929.v'
)

$ErrorActionPreference = 'Stop'
$candidateText = [System.IO.File]::ReadAllText($Candidate)
$baselineText  = [System.IO.File]::ReadAllText($Baseline)

# The accepted production RTL contains the hand-audited three-copy RF block.
# Reuse that exact block so this experiment differs from production only in the
# R1/R2 execution timing logic, not in RF replication or RF read-port topology.
$baseMatch = [regex]::Match(
  $baselineText,
  '(?s)\s*// Replicate the four-write register file at the execution-unit boundary\..*?(?=\s*DependencyStorage\s+RfDependencyPlugin_logic_forRf_integer_impl)'
)
if(-not $baseMatch.Success){ throw 'Accepted RF-replication block was not found in baseline RTL.' }

$candMatch = [regex]::Match(
  $candidateText,
  '(?s)\s*RegFileAsync\s+integer_RegFilePlugin_logic_regfile_fpga\s*\(.*?(?=\s*DependencyStorage\s+RfDependencyPlugin_logic_forRf_integer_impl)'
)
if(-not $candMatch.Success){ throw 'Single-RF block was not found in R1/R2 candidate RTL.' }

$patched = $candidateText.Substring(0, $candMatch.Index) + $baseMatch.Value + $candidateText.Substring($candMatch.Index + $candMatch.Length)
[System.IO.File]::WriteAllText($Output, $patched, [System.Text.UTF8Encoding]::new($false))
Write-Output "patched=$Output"
Write-Output "candidate_rf_block_chars=$($candMatch.Length)"
Write-Output "baseline_rf_block_chars=$($baseMatch.Length)"
