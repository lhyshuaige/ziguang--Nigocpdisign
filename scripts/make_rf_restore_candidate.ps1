param(
  [string]$Production = 'D:\PDS\project\NAX\rtl\NaxRiscvContest.v',
  [string]$Reference  = 'D:\PDS\project\NAX\rtl\backup_before_bypass_rtl_20260927_1535\NaxRiscvContest.v',
  [string]$Output     = 'D:\PDS\project\NAX\rtl\NaxRiscvContest_rf_restore_single_20261006.v'
)

$ErrorActionPreference = 'Stop'
$productionText = [System.IO.File]::ReadAllText($Production)
$referenceText  = [System.IO.File]::ReadAllText($Reference)

$currentMatch = [regex]::Match(
  $productionText,
  '(?s)\s*// Replicate the four-write register file at the execution-unit boundary\..*?(?=\s*DependencyStorage\s+RfDependencyPlugin_logic_forRf_integer_impl)'
)
if (-not $currentMatch.Success) {
  throw 'Current three-copy RF block was not found.'
}

$referenceMatch = [regex]::Match(
  $referenceText,
  '(?s)\s*RegFileAsync\s+integer_RegFilePlugin_logic_regfile_fpga\s*\(.*?(?=\s*DependencyStorage\s+RfDependencyPlugin_logic_forRf_integer_impl)'
)
if (-not $referenceMatch.Success) {
  throw 'Reference single-RF block was not found.'
}

$candidate = $productionText.Substring(0, $currentMatch.Index) +
             $referenceMatch.Value +
             $productionText.Substring($currentMatch.Index + $currentMatch.Length)

[System.IO.File]::WriteAllText($Output, $candidate, [System.Text.UTF8Encoding]::new($false))
Write-Output "candidate=$Output"
Write-Output "current_block_chars=$($currentMatch.Length)"
Write-Output "reference_block_chars=$($referenceMatch.Length)"
