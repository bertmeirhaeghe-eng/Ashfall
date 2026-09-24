# Downloads the Kokoro voice model used by Ashfall into addons\godot_kokoro\models\.
# Run from the project folder in PowerShell:  powershell -ExecutionPolicy Bypass -File tools\get_kokoro_model.ps1
$ErrorActionPreference = "Stop"
$name = "kokoro-int8-multi-lang-v1_0"
$url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$name.tar.bz2"
$dest = Join-Path (Split-Path -Parent $PSScriptRoot) "addons\godot_kokoro\models"
$tmp = Join-Path $env:TEMP "ashfall_kokoro"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$archive = Join-Path $tmp "$name.tar.bz2"
Write-Host "Downloading $name (~132 MB)..."
$ProgressPreference = "SilentlyContinue"
Invoke-WebRequest -Uri $url -OutFile $archive
Write-Host "Extracting..."
tar -xjf $archive -C $tmp   # tar ships with Windows 10 and later
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Recurse -Force (Join-Path $tmp "$name\*") $dest
Remove-Item -Recurse -Force $tmp
Write-Host "Kokoro model installed in $dest"
