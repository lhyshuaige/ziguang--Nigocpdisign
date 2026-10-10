$ErrorActionPreference = 'Stop'
$ai = 'D:\PDS\project\NAX\modular\constraints\50_ai_lock_generated_20261010.pcf'
$hmic = 'D:\PDS\project\NAX\modular\constraints\51_hmic_lock_generated_20261010.pcf'
$out = 'D:\PDS\project\NAX\modular\constraints\52_ai_hmic_lock_combined_20261010.pcf'
if (!(Test-Path -LiteralPath $ai) -or !(Test-Path -LiteralPath $hmic)) { throw 'Generated AI/HMIC PCF is missing' }
$aiText = Get-Content -LiteralPath $ai -Raw
$hmicText = Get-Content -LiteralPath $hmic -Raw
Set-Content -LiteralPath $out -Value ($aiText + "`r`n# ---- HMIC exact-site constraints ----`r`n" + $hmicText) -Encoding ascii
Write-Output "combined=$out"
Write-Output "ai_lines=$((Get-Content -LiteralPath $ai).Count) hmic_lines=$((Get-Content -LiteralPath $hmic).Count) combined_lines=$((Get-Content -LiteralPath $out).Count)"
