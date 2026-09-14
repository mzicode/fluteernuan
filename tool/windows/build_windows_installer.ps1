# Builds the Inno Setup installer from the Flutter Windows Release directory.
# Run from the Flutter project root after `flutter build windows --release`.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$releaseDir = Join-Path (Get-Location) 'build/windows/x64/runner/Release'
if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'customer.exe'))) {
    throw "Release exe was not produced: $releaseDir\customer.exe"
}

$outputDir = Join-Path (Get-Location) 'dist/windows-installer'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$version = '1.0.1'
$pubspec = Get-Content -LiteralPath 'pubspec.yaml' -Raw
if ($pubspec -match '(?m)^version:\s*([^\s+]+)') {
    $version = $Matches[1]
}
$outputBase = "NuanLin-Windows-Setup-$version"

# ISPP /D cannot take unquoted Windows paths. GitHub runners live under D:\a\...
# and \x64 is a hex escape. Write quoted defines into a wrapper next to the
# committed .iss so relative includes and SetupIconFile keep working.
$sourceDir = ((Resolve-Path -LiteralPath $releaseDir).Path -replace '\\', '/')
$outputDirUnix = ((Resolve-Path -LiteralPath $outputDir).Path -replace '\\', '/')
$wrapper = Join-Path (Get-Location) 'windows/installer/_ci_setup.iss'
$wrapperLines = @(
    "#define SourceDir `"$sourceDir`"",
    "#define OutputDir `"$outputDirUnix`"",
    "#define MyAppVersion `"$version`"",
    "#define OutputBaseFilename `"$outputBase`"",
    '#include "customer_setup.iss"'
)
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($wrapper, (($wrapperLines -join "`r`n") + "`r`n"), $utf8)
Write-Host "Inno wrapper:`n$([System.IO.File]::ReadAllText($wrapper))"

$iscc = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) { throw 'ISCC.exe not found after Inno Setup install' }

$isccArgs = @(
    "/O$outputDir",
    "/F$outputBase",
    $wrapper
)
Write-Host "ISCC: $iscc"
Write-Host "ISCC args: $($isccArgs -join ' ')"
$log = Join-Path $outputDir 'iscc.log'
$output = & $iscc @isccArgs 2>&1
$exitCode = $LASTEXITCODE
$output | Tee-Object -FilePath $log
if ($env:GITHUB_STEP_SUMMARY) {
    $preview = ($output | Select-Object -Last 80) -join "`n"
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "## Inno Setup`n``````text`n$preview`n``````"
}
if ($exitCode -ne 0) { exit $exitCode }

Get-ChildItem -LiteralPath $outputDir -File | ForEach-Object {
    if ($_.Name -like '*.sha256.txt') { return }
    if ($_.Name -eq 'iscc.log') { return }
    (Get-FileHash $_.FullName -Algorithm SHA256).Hash | Set-Content -Encoding ascii "$($_.FullName).sha256.txt"
}

Write-Host "Installer output:"
Get-ChildItem -LiteralPath $outputDir -File | ForEach-Object { Write-Host $_.FullName }
