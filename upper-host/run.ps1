param([string]$Python)
$ErrorActionPreference = 'Stop'
$taskCandidates = @(
    $Python,
    $env:NIGO_PYTHON,
    (Join-Path $PSScriptRoot '.venv\Scripts\python.exe'),
    'python',
    (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
)
$taskRuntime = $null
$taskCheck = @'
import sys
try:
    import tkinter
    from PIL import Image, ImageTk
    assert hasattr(Image, 'Resampling')
except Exception:
    sys.exit(1)
'@
foreach ($taskCandidate in $taskCandidates) {
    if ([string]::IsNullOrWhiteSpace($taskCandidate)) { continue }
    if (!(Get-Command $taskCandidate -ErrorAction SilentlyContinue)) { continue }
    & $taskCandidate -B -c $taskCheck
    if ($LASTEXITCODE -eq 0) { $taskRuntime = $taskCandidate; break }
}
if (!$taskRuntime) { throw 'Python with Tkinter and Pillow >= 9.1 is required. Install requirements.txt, or use -Python <python.exe>.' }
& $taskRuntime -B (Join-Path $PSScriptRoot 'app.py')
exit $LASTEXITCODE
