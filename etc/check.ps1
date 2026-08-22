# Local lint: luacheck (style + undefined globals, per .luacheckrc) and a
# LuaJIT parse of each file (LuaJIT is Lua 5.1, same dialect as WoW).
# Usage: .\etc\check.ps1 (works from any directory)

$repoRoot = Split-Path $PSScriptRoot
$src = Join-Path $repoRoot "src"
$failed = $false

luacheck $src --config (Join-Path $repoRoot ".luacheckrc")
if ($LASTEXITCODE -ne 0) { $failed = $true }

Get-ChildItem $src -Filter *.lua | ForEach-Object {
    luajit -bl $_.FullName $null 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$($_.Name): syntax error" -ForegroundColor Red
        luajit -bl $_.FullName $null
        $script:failed = $true
    }
}

if ($failed) { exit 1 }
Write-Host "All checks passed." -ForegroundColor Green
