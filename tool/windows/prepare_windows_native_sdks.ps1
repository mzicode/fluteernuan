# Prepares Agora / Firebase native SDKs and applies Windows CMake workarounds.
# Run from the Flutter project root after `flutter pub get`.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PackageRoot {
    param([Parameter(Mandatory = $true)][string]$PackageName)

    $packageConfigPath = Join-Path (Get-Location) '.dart_tool/package_config.json'
    if (-not (Test-Path -LiteralPath $packageConfigPath)) {
        throw 'Run flutter pub get before preparing Windows native SDKs.'
    }

    $packageConfig = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
    $package = $packageConfig.packages | Where-Object { $_.name -eq $PackageName } | Select-Object -First 1
    if ($null -eq $package) {
        throw "Package $PackageName was not found in package_config.json"
    }

    return ([Uri]$package.rootUri).LocalPath.TrimEnd('\', '/')
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        Write-Host "Reusing $($Destination)"
        return
    }

    Write-Host "Downloading $Url"
    & curl.exe --fail --location --retry 5 --retry-all-errors --retry-delay 2 --output $Destination $Url
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force
        }
        throw "Download failed: $Url"
    }
}

function Expand-ZipTo {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Write-Host "Extracting $ZipPath -> $Destination"
    & tar.exe -xf $ZipPath -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract $ZipPath"
    }
}

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { Join-Path (Get-Location) 'build/windows-native-sdks' }
$downloadRoot = Join-Path $tempRoot 'nuanlin-native-downloads'
New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null

$agoraRoot = Get-PackageRoot 'agora_rtc_engine'
$downloadScript = Join-Path $agoraRoot 'windows/cmake/DownloadSDK.cmake'
if (-not (Test-Path -LiteralPath $downloadScript)) {
    throw "Agora DownloadSDK.cmake not found: $downloadScript"
}

$downloadCmake = Get-Content -LiteralPath $downloadScript -Raw
if ($downloadCmake -notmatch 'set\(IRIS_SDK_DOWNLOAD_URL "([^"]+)"\)') {
    throw 'IRIS_SDK_DOWNLOAD_URL was not found in DownloadSDK.cmake'
}
$irisUrl = $Matches[1]
if ($downloadCmake -notmatch 'set\(NATIVE_SDK_DOWNLOAD_URL "([^"]+)"\)') {
    throw 'NATIVE_SDK_DOWNLOAD_URL was not found in DownloadSDK.cmake'
}
$nativeUrl = $Matches[1]

$irisZip = Join-Path $downloadRoot ([IO.Path]::GetFileName(([Uri]$irisUrl).AbsolutePath))
$nativeZip = Join-Path $downloadRoot ([IO.Path]::GetFileName(([Uri]$nativeUrl).AbsolutePath))
Invoke-Download -Url $irisUrl -Destination $irisZip
Invoke-Download -Url $nativeUrl -Destination $nativeZip

$irisLib = Join-Path $agoraRoot 'windows/third_party/iris/lib'
$nativeLib = Join-Path $agoraRoot 'windows/third_party/native/lib'
Expand-ZipTo -ZipPath $irisZip -Destination $irisLib
Expand-ZipTo -ZipPath $nativeZip -Destination $nativeLib

$pluginDevMarker = Join-Path $agoraRoot 'windows/.plugin_dev'
Write-Utf8NoBom -Path $pluginDevMarker -Content "prepared by tool/windows/prepare_windows_native_sdks.ps1`n"
Write-Host "Agora SDK prepared under $agoraRoot"

$firebaseRoot = Get-PackageRoot 'firebase_core'
$firebaseCmake = Get-Content -LiteralPath (Join-Path $firebaseRoot 'windows/CMakeLists.txt') -Raw
if ($firebaseCmake -notmatch 'set\(FIREBASE_SDK_VERSION "([^"]+)"\)') {
    throw 'FIREBASE_SDK_VERSION was not found in firebase_core windows/CMakeLists.txt'
}
$firebaseVersion = $Matches[1]
$firebaseUrl = "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_windows_${firebaseVersion}.zip"
$firebaseZip = Join-Path $downloadRoot "firebase_cpp_sdk_windows_${firebaseVersion}.zip"
Invoke-Download -Url $firebaseUrl -Destination $firebaseZip

$firebaseExtractRoot = Join-Path $tempRoot 'firebase-cpp-sdk'
Expand-ZipTo -ZipPath $firebaseZip -Destination $firebaseExtractRoot
$firebaseSdkDir = Join-Path $firebaseExtractRoot 'firebase_cpp_sdk_windows'
if (-not (Test-Path -LiteralPath (Join-Path $firebaseSdkDir 'include/firebase/version.h'))) {
    $found = Get-ChildItem -LiteralPath $firebaseExtractRoot -Recurse -Filter 'version.h' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]include[\\/]firebase[\\/]version\.h$' } |
        Select-Object -First 1
    if ($null -eq $found) {
        throw 'Extracted Firebase SDK is missing include/firebase/version.h'
    }
    $firebaseSdkDir = $found.Directory.Parent.Parent.FullName
}

$firebaseSdkDir = $firebaseSdkDir.Replace('\', '/')
if ($env:GITHUB_ENV) {
    Add-Content -Path $env:GITHUB_ENV -Value "FIREBASE_CPP_SDK_DIR=$firebaseSdkDir"
}
$env:FIREBASE_CPP_SDK_DIR = $firebaseSdkDir
Write-Host "FIREBASE_CPP_SDK_DIR=$firebaseSdkDir"

$jniRoot = Get-PackageRoot 'jni'
$jniCmake = Join-Path $jniRoot 'src/CMakeLists.txt'
if (Test-Path -LiteralPath $jniCmake) {
    $jniContent = [System.IO.File]::ReadAllText($jniCmake)
    $patched = $jniContent.Replace(
        'set_target_properties(${TARGET_NAME} PROPERTIES',
        'set_target_properties(jni PROPERTIES'
    )
    if ($patched -ne $jniContent) {
        Write-Utf8NoBom -Path $jniCmake -Content $patched
        Write-Host "Patched jni TARGET_NAME in $jniCmake"
    }
}

Write-Host 'Windows native SDK preparation finished.'
