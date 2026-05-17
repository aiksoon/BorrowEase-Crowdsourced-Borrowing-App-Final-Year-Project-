param(
    [string]$Root = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

$extensions = @(
    ".dart", ".js", ".ts", ".tsx", ".jsx", ".json",
    ".md", ".sql", ".yaml", ".yml", ".ps1", ".txt"
)

$excludeRegex = '/(?:\.git|node_modules|\.dart_tool|build|dist|coverage|ios/Flutter/ephemeral|android/\.gradle|frontend/web|frontend/windows)(?:/|$)'

# Common mojibake fingerprints from UTF-8 <-> CP1252 confusion.
# Keep this regex ASCII-only to avoid parser issues on non-UTF-8 shells.
$combinedPattern = '(?:\u00E2(?:\u20AC\u00A2|\u2020\u2019|\u20AC\u201D|\u20AC\u201C|\u20AC)|\u00F0\u0178|\u00C3.|\uFFFD)'

$files = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant()
    if ($extensions -notcontains $ext) { return $false }

    $normalizedPath = $_.FullName.Replace('\', '/')
    if ($normalizedPath -match $excludeRegex) { return $false }

    return $true
}

$hits = @()
foreach ($file in $files) {
    $matches = Select-String -Path $file.FullName -Pattern $combinedPattern -Encoding UTF8 -AllMatches
    foreach ($m in $matches) {
        $hits += [PSCustomObject]@{
            File = $m.Path
            Line = $m.LineNumber
            Text = $m.Line.Trim()
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host "[OK] No mojibake patterns found."
    exit 0
}

Write-Host "[FAIL] Potential mojibake detected:" -ForegroundColor Red
$hits | ForEach-Object {
    Write-Host ("{0}:{1} -> {2}" -f $_.File, $_.Line, $_.Text)
}
exit 1
