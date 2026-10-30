[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot 'tools\engine\Godot_v4.5.1-stable_win64_console.exe'
$androidRoot = Join-Path $projectRoot 'tools\android-build'
$sdkRoot = Join-Path $androidRoot 'sdk'
$jdkRoot = Get-ChildItem -LiteralPath (Join-Path $androidRoot 'jdk') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$keystore = Join-Path $androidRoot 'debug.keystore'
$apk = Join-Path $projectRoot 'build\BELOW_ZERO_Android.apk'

if (-not (Test-Path -LiteralPath $engine)) {
    throw 'Godot 4.5.1 was not found under tools\engine. See ANDROID.md.'
}
if ($null -eq $jdkRoot -or -not (Test-Path -LiteralPath (Join-Path $jdkRoot.FullName 'bin\java.exe'))) {
    throw 'OpenJDK 17 was not found under tools\android-build\jdk. See ANDROID.md.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sdkRoot 'platform-tools\adb.exe'))) {
    throw 'Android Platform Tools were not found. See ANDROID.md.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sdkRoot 'build-tools\35.0.1\apksigner.bat'))) {
    throw 'Android Build Tools 35.0.1 were not found. See ANDROID.md.'
}
if (-not (Test-Path -LiteralPath $keystore)) {
    throw 'The local debug keystore is missing. See ANDROID.md.'
}

$env:JAVA_HOME = $jdkRoot.FullName
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $keystore
$env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $apk) | Out-Null
& $engine --headless --path $projectRoot --export-debug 'Android' $apk
if ($LASTEXITCODE -ne 0) {
    throw "Godot Android export failed with exit code $LASTEXITCODE."
}

$apksigner = Join-Path $sdkRoot 'build-tools\35.0.1\apksigner.bat'
& $apksigner verify --verbose $apk
if ($LASTEXITCODE -ne 0) {
    throw 'APK signature verification failed.'
}

$file = Get-Item -LiteralPath $apk
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash
Write-Host ''
Write-Host "Android APK ready: $($file.FullName)"
Write-Host "Size: $($file.Length) bytes"
Write-Host "SHA-256: $hash"
