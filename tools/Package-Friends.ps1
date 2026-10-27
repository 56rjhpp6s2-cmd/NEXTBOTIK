param([string]$EnginePath)
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'Find-Engine.ps1')
$buildDirectory = Join-Path $projectDirectory 'build'
$staging = Join-Path $buildDirectory ('.package-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $staging 'BELOW_ZERO'
try {
    $engine = Find-GameEngine $EnginePath
    if ($engine -like '*_console.exe') {
        $guiEngine = $engine -replace '_console\.exe$', '.exe'
        if (-not (Test-Path -LiteralPath $guiEngine)) { throw 'The main Godot executable must be next to its console wrapper.' }
        $engine = $guiEngine
    }
    New-Item -ItemType Directory -Path (Join-Path $package 'runtime') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $buildDirectory '.gdignore') -Force | Out-Null
    $runtimeDirectory = Join-Path $package 'runtime'
    Copy-Item -LiteralPath $engine -Destination (Join-Path $runtimeDirectory 'Godot.exe')
    $engine = Join-Path $runtimeDirectory 'Godot.exe'
    # Editor operations use a temporary profile inside staging, never the user's editor settings.
    New-Item -ItemType File -Path (Join-Path $runtimeDirectory '_sc_') -Force | Out-Null
    $logs = Join-Path $projectDirectory '.godot\package_logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $common = @('--headless', '--path', ('"' + $projectDirectory + '"'))
    $importLog = Join-Path $logs 'import.log'
    $process = Start-Process -FilePath $engine -ArgumentList ($common + @('--log-file', ('"' + $importLog + '"'), '--editor', '--import', '--quit')) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0 -or (Get-Content -LiteralPath $importLog -Raw) -match 'SCRIPT ERROR|Parse Error') { throw "Import failed: $importLog" }
    $pack = Join-Path $package 'BELOW_ZERO.pck'
    $exportLog = Join-Path $logs 'export.log'
    $process = Start-Process -FilePath $engine -ArgumentList ($common + @('--log-file', ('"' + $exportLog + '"'), '--export-pack', '"Windows Desktop"', ('"' + $pack + '"'))) -WindowStyle Hidden -Wait -PassThru
    $exportText = Get-Content -LiteralPath $exportLog -Raw
    $unexpectedErrors = @($exportText -split '\r?\n' | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pack) -or $exportText -match 'SCRIPT ERROR|Parse Error' -or $unexpectedErrors.Count -gt 0) { throw "Export failed: $exportLog" }
    $licenseFile = Join-Path $package 'runtime\GODOT_LICENSES.txt'
    $licenseScript = Join-Path $PSScriptRoot 'write_engine_licenses.gd'
    $process = Start-Process -FilePath $engine -ArgumentList ($common + @('--log-file', ('"' + (Join-Path $logs 'licenses.log') + '"'), '--script', ('"' + $licenseScript + '"'), '--', '--portable-test', ('"--license-output=' + $licenseFile + '"'))) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $licenseFile)) { throw 'Could not write engine licenses.' }
    Remove-Item -LiteralPath (Join-Path $runtimeDirectory '_sc_') -Force
    $editorProfile = Join-Path $runtimeDirectory 'editor_data'
    if (Test-Path -LiteralPath $editorProfile) {
        $resolvedProfile = (Resolve-Path -LiteralPath $editorProfile).Path
        if (-not $resolvedProfile.StartsWith(((Resolve-Path -LiteralPath $staging).Path.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to clean an editor profile outside staging.' }
        Remove-Item -LiteralPath $resolvedProfile -Recurse -Force
    }
    $launcher = @'
@echo off
cd /d "%~dp0"
if not exist "runtime\Godot.exe" goto missing
if not exist "BELOW_ZERO.pck" goto missing
start "" "%~dp0runtime\Godot.exe" --main-pack "%~dp0BELOW_ZERO.pck"
exit /b 0
:missing
echo Extract the entire ZIP first. Keep PLAY.cmd, BELOW_ZERO.pck and runtime together.
pause
exit /b 1
'@
    [IO.File]::WriteAllText((Join-Path $package 'PLAY.cmd'), ($launcher -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'FRIEND_README.txt') -Destination (Join-Path $package 'READ_ME.txt')
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'LICENSE') -Destination $package
    $archive = Join-Path $buildDirectory 'BELOW_ZERO_Friends.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $temporaryArchive = Join-Path $buildDirectory ('friends-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $temporaryArchive, [IO.Compression.CompressionLevel]::Optimal, $false)
    Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
    Write-Host "READY: $archive"
    Write-Host ('Size: {0:N1} MB' -f ((Get-Item -LiteralPath $archive).Length / 1MB))
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    if (Test-Path -LiteralPath $staging) {
        $resolvedStaging = (Resolve-Path -LiteralPath $staging).Path
        $resolvedBuild = (Resolve-Path -LiteralPath $buildDirectory).Path.TrimEnd('\') + '\'
        if (-not $resolvedStaging.StartsWith($resolvedBuild, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to clean a path outside build.' }
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}
