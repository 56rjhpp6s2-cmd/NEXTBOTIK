function Find-GameEngine {
    param([string]$PreferredPath)
    $candidates = @($PreferredPath, $env:GODOT_ENGINE)
    $bundledDirectory = Join-Path $PSScriptRoot 'engine'
    if (Test-Path -LiteralPath $bundledDirectory) {
        $candidates += Get-ChildItem -LiteralPath $bundledDirectory -Filter '*.exe' | Where-Object { $_.Name -notlike '*_console.exe' } | Select-Object -ExpandProperty FullName
    }
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Godot was not found. Put the portable Godot executable in tools/engine, or set GODOT_ENGINE to its path.'
}
