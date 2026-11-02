$ErrorActionPreference = 'Stop'
$shooterPython = 'C:\Users\lhy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'build\shooter.dll'))) {
    & $shooterPython -B (Join-Path $PSScriptRoot 'build_native.py') --test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $shooterPython -B (Join-Path $PSScriptRoot 'preview.py')
