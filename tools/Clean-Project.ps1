[CmdletBinding(SupportsShouldProcess=$true)]
param()
# Removes only reproducible output. Source, assets, current package and runtime stay.
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectPrefix = $projectDirectory.TrimEnd('\') + '\'

function Assert-ProjectPath([string]$Candidate) {
    $resolved = [IO.Path]::GetFullPath($Candidate)
    if (-not $resolved.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing a path outside this project: $resolved"
    }
    $item = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing a junction or symbolic link: $resolved"
    }
    return $resolved
}

try {
    # Preserve the unrelated terminal game in an archive before tidying the root.
    $snakeFiles = @('snake.py', 'SNAKE.cmd') | ForEach-Object { Join-Path $projectDirectory $_ } | Where-Object { Test-Path -LiteralPath $_ }
    if ($snakeFiles.Count -gt 0 -and $PSCmdlet.ShouldProcess('terminal snake files', 'Archive in extras and remove loose copies')) {
        $extras = Join-Path $projectDirectory 'extras'
        New-Item -ItemType Directory -Path $extras -Force | Out-Null
        $backup = Join-Path $extras ('terminal_snake_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss') + '.zip')
        Compress-Archive -LiteralPath $snakeFiles -DestinationPath $backup
        foreach ($source in $snakeFiles) { Remove-Item -LiteralPath (Assert-ProjectPath $source) -Force }
    }
    $targets = @()
    $cache = Join-Path $projectDirectory '.godot'
    if (Test-Path -LiteralPath $cache) {
        $targets += Get-ChildItem -LiteralPath $cache -Force | Where-Object {
            $_.Name -like 'test_*' -or $_.Name -in @('combat_fixtures', 'network_tests', 'package_logs', 'launcher_logs')
        } | Select-Object -ExpandProperty FullName
    }
    $tests = Join-Path $projectDirectory 'tests'
    $targets += Get-ChildItem -LiteralPath $tests -File -Filter '*.log' | Select-Object -ExpandProperty FullName
    foreach ($relative in @('tests\captures', 'tests\__pycache__', 'tools\generate_projectiles.gd', 'tools\generate_projectiles.gd.uid', 'tools\engine\Godot_v4.5.1-stable_win64.exe.zip')) {
        $candidate = Join-Path $projectDirectory $relative
        if (Test-Path -LiteralPath $candidate) { $targets += $candidate }
    }
    $build = Join-Path $projectDirectory 'build'
    if (Test-Path -LiteralPath $build) {
        $targets += Get-ChildItem -LiteralPath $build -Directory -Force | Where-Object {
            $_.Name -like '.package-*' -or $_.Name -like 'portable-fresh-*' -or (Test-Path -LiteralPath (Join-Path $_.FullName 'portable-first.log'))
        } | Select-Object -ExpandProperty FullName
    }
    $removed = 0
    foreach ($candidate in ($targets | Select-Object -Unique)) {
        $resolved = Assert-ProjectPath $candidate
        $item = Get-Item -LiteralPath $resolved -Force
        if ($item.PSIsContainer) {
            $links = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
            if ($links.Count -gt 0) { throw "Refusing a folder containing links: $resolved" }
        }
        if ($PSCmdlet.ShouldProcess($resolved, 'Remove generated or obsolete files')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
            $removed += 1
        }
    }
    Write-Host "Cleaned $removed entries. Game source, assets, runtime and BELOW_ZERO_Friends.zip are preserved."
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
