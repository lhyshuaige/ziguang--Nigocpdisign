$ErrorActionPreference='Stop'
$taskRuntime=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if(!(Test-Path -LiteralPath $taskRuntime)){$taskRuntime='python'}
& $taskRuntime -c 'import tkinter; from PIL import Image,ImageTk'
if($LASTEXITCODE -ne 0){throw 'Use a Python installation with Tkinter and Pillow (pip install -r requirements.txt).'}
& $taskRuntime (Join-Path $PSScriptRoot 'app.py')
