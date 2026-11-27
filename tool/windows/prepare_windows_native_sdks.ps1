# Prepares Agora / Firebase / NERTC native SDKs and applies Windows CMake workarounds.
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

# nertc_core 5.9.30 downloads NERTC_Windows_SDK_V5.9.21 from yx-web-nosdn, and that
# object now returns 404. CMake file(DOWNLOAD) then aborts configure. The same
# plugin sources in nertc_core 5.9.31 use this still-hosted 5.9.11 package.
# Point the checked-out plugin at that URL and place the zip where DownloadSDK.cmake
# expects it (filename + an extra .zip), so configure extracts it instead of downloading.
$nertcRoot = Get-PackageRoot 'nertc_core'
$nertcCmake = Join-Path $nertcRoot 'windows/cmake/DownloadSDK.cmake'
if (-not (Test-Path -LiteralPath $nertcCmake)) {
    throw "nertc DownloadSDK.cmake not found: $nertcCmake"
}
$nertcCmakeText = [System.IO.File]::ReadAllText($nertcCmake)
if ($nertcCmakeText -notmatch 'set\(NATIVE_SDK_DOWNLOAD_URL "([^"]+)"\)') {
    throw 'NATIVE_SDK_DOWNLOAD_URL was not found in nertc DownloadSDK.cmake'
}
$nertcUrl = $Matches[1]
$nertcFallbackUrl = 'https://yx-web-nosdn.netease.im/package/1761213316/NERTC_Windows_SDK_V5.9.11.zip?download=NERTC_Windows_SDK_V5.9.11.zip'
# A 404 from curl writes to stderr. PowerShell 7 treats that as a terminating
# error when ErrorActionPreference is Stop, which would skip the fallback.
$savedNativeErrorAction = $null
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $savedNativeErrorAction = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
& curl.exe --silent --location --fail --head --max-time 30 --output NUL $nertcUrl
$nertcProbe = $LASTEXITCODE
if ($null -ne $savedNativeErrorAction) {
    $PSNativeCommandUseErrorActionPreference = $savedNativeErrorAction
}
if ($nertcProbe -ne 0) {
    Write-Host "NERTC SDK URL is unavailable, switching to the hosted 5.9.11 package"
    $nertcUrl = $nertcFallbackUrl
    $nertcPatched = [regex]::Replace(
        $nertcCmakeText,
        'set\(NATIVE_SDK_DOWNLOAD_URL "[^"]+"\)',
        "set(NATIVE_SDK_DOWNLOAD_URL `"$nertcUrl`")"
    )
    Write-Utf8NoBom -Path $nertcCmake -Content $nertcPatched
}
$nertcFileName = [IO.Path]::GetFileName(([Uri]$nertcUrl).AbsolutePath)
$nertcNativeDir = Join-Path $nertcRoot 'windows/third_party/native'
$nertcZip = Join-Path $nertcNativeDir ($nertcFileName + '.zip')
Invoke-Download -Url $nertcUrl -Destination $nertcZip
Write-Host "NERTC SDK prepared at $nertcZip"

$jniRoot = Get-PackageRoot 'jni'
$jniCmake = Join-Path $jniRoot 'src/CMakeLists.txt'
if (Test-Path -LiteralPath $jniCmake) {
    $jniContent = [System.IO.File]::ReadAllText($jniCmake)
    $oldTarget = 'set_target_properties(${TARGET_NAME} PROPERTIES'
    $patched = $jniContent.Replace(
        $oldTarget,
        'set_target_properties(jni PROPERTIES'
    )
    if ($patched -ne $jniContent) {
        Write-Utf8NoBom -Path $jniCmake -Content $patched
        Write-Host "Patched jni TARGET_NAME in $jniCmake"
    }
}

Write-Host 'Windows native SDK preparation finished.'
