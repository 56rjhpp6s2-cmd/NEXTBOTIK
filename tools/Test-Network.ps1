param(
    [string]$EnginePath,
    [ValidateRange(1024, 65535)][int]$Port = 24621,
    [ValidateRange(30, 300)][int]$TimeoutSeconds = 110,
    [switch]$CaptureClient
)
# Uses two real ENet peers over loopback; never downloads an engine.
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'Find-Engine.ps1')
$processes = @()
try {
    $EnginePath = Find-GameEngine $EnginePath
    $runId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $logs = @{}
    foreach ($role in @('host', 'client')) {
        $logs[$role] = Join-Path $projectDirectory "tests\engine-net-$role.log"
        $arguments = @('--headless', '--path', ('"' + $projectDirectory + '"'), '--max-fps', '60', '--quit-after', '6000', '--log-file', ('"' + $logs[$role] + '"'), '--', "--net-test-$role", "--net-run=$runId", "--net-port=$Port")
        if ($CaptureClient -and $role -eq 'client') {
            $arguments = @('--position', '-4000,-4000', '--resolution', '1280x720') + @($arguments | Where-Object { $_ -ne '--headless' }) + @('--capture-network-client')
        }
        $processes += Start-Process -FilePath $EnginePath -ArgumentList $arguments -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (@($processes | Where-Object { -not $_.HasExited }).Count -gt 0) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Network tests timed out. See tests/engine-net-host.log and engine-net-client.log.' }
        foreach ($process in $processes) { [void]$process.WaitForExit(250) }
    }
    foreach ($role in @('host', 'client')) {
        $content = Get-Content -LiteralPath $logs[$role] -Raw -Encoding UTF8
        $resultPattern = 'NETWORK ' + $role.ToUpperInvariant() + ' TEST: \d+ checks, 0 failures'
        $unexpectedErrors = @($content -split '\r?\n' | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
        if ($content -notmatch $resultPattern -or $content -match 'SCRIPT ERROR|Parse Error|FAIL:|Failed to load script|above the MTU' -or $unexpectedErrors.Count -gt 0) {
            Write-Host $content
            throw "Network $role test failed."
        }
        Write-Host ([regex]::Match($content, $resultPattern).Value) -ForegroundColor Green
    }
    Write-Host 'Loopback passed. A separate two-PC Radmin VPN session is still a manual check.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
        $process.Dispose()
    }
}
