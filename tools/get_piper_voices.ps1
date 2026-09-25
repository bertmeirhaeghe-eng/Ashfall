# Downloads the six Dutch Piper voices used when Ashfall is played in Dutch
# (Nederlands) into addons\godot_kokoro\piper\.  ~390 MB on disk.
# Run from the project folder in PowerShell:  powershell -ExecutionPolicy Bypass -File tools\get_piper_voices.ps1
$ErrorActionPreference = "Stop"
$voices = @("nl_BE-nathalie-medium", "nl_NL-dii-high", "nl_NL-pim-medium", "nl_NL-ronnie-medium", "nl_NL-miro-high", "nl_BE-rdh-medium")
$base = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"
$dest = Join-Path (Split-Path -Parent $PSScriptRoot) "addons\godot_kokoro\piper"
$tmp = Join-Path $env:TEMP "ashfall_piper"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$ProgressPreference = "SilentlyContinue"
foreach ($v in $voices) {
    Write-Host "Downloading $v..."
    $archive = Join-Path $tmp "$v.tar.bz2"
    Invoke-WebRequest -Uri "$base/vits-piper-$v.tar.bz2" -OutFile $archive
    tar -xjf $archive -C $tmp   # tar ships with Windows 10 and later
    Remove-Item $archive
    $d = Join-Path $tmp "vits-piper-$v"
    # one shared copy of the phoneme data is enough
    if (-not (Test-Path (Join-Path $dest "espeak-ng-data"))) { Copy-Item -Recurse (Join-Path $d "espeak-ng-data") $dest }
    Remove-Item -Recurse -Force (Join-Path $d "espeak-ng-data")
    $target = Join-Path $dest "vits-piper-$v"
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Move-Item $d $dest
}
Remove-Item -Recurse -Force $tmp
Write-Host "Dutch voices installed in $dest"
