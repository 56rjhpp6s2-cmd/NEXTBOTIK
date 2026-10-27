param([switch]$Editor, [switch]$Test, [switch]$NoDownload, [string]$EnginePath)
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'Find-Engine.ps1')
try {
    $engine = Find-GameEngine $EnginePath
    $logs = Join-Path $projectDirectory '.godot\launcher_logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $importLog = Join-Path $logs 'import.log'
    $importArgs = @('--headless', '--path', ('"' + $projectDirectory + '"'), '--editor', '--import', '--quit', '--log-file', ('"' + $importLog + '"'))
    $import = Start-Process -FilePath $engine -ArgumentList $importArgs -WindowStyle Hidden -Wait -PassThru
    $content = Get-Content -LiteralPath $importLog -Raw -Encoding UTF8
    if ($import.ExitCode -ne 0 -or $content -match 'SCRIPT ERROR|Parse Error|Failed to load script') { throw "Import failed. See $importLog" }
    if ($Test) {
        $suites = @('smoke', 'map', 'movement', 'procedural', 'modes', 'combat', 'spawn')
        $quitAfter = @{ spawn = 18000 }
        foreach ($suite in $suites) {
            $testLog = Join-Path $logs ($suite + '.log')
            $qa = if ($quitAfter.ContainsKey($suite)) { $quitAfter[$suite] } else { 6000 }
            $arguments = @('--headless', '--path', ('"' + $projectDirectory + '"'), '--max-fps', '60', '--quit-after', $qa, '--log-file', ('"' + $testLog + '"'), '--', ('--' + $suite + '-test'))
            $testProcess = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
            $content = Get-Content -LiteralPath $testLog -Raw -Encoding UTF8
            $resultPattern = $suite.ToUpperInvariant() + ' TEST: \d+ checks, 0 failures'
            if ($testProcess.ExitCode -ne 0 -or $content -notmatch $resultPattern -or $content -match 'SCRIPT ERROR|FAIL:') { throw "Test failed. See $testLog" }
            Write-Host ([regex]::Match($content, $resultPattern).Value)
        }
        exit 0
    }
    $arguments = @('--path', ('"' + $projectDirectory + '"'))
    if ($Editor) { $arguments += '--editor' }
    Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectDirectory
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
