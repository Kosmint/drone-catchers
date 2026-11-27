<#
.SYNOPSIS
  Runs all automation script tests and Luau unit specs (no GitHub, no agy, no Studio needed).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tests\Run-Tests.ps1
#>
$failed = 0
foreach ($t in @('Test-AgyGate.ps1', 'Test-GeminiHelper.ps1')) {
    Write-Host "== $t"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $t)
    if ($LASTEXITCODE -gt 0) { $failed += $LASTEXITCODE }
    elseif ($LASTEXITCODE -ne 0) { $failed += 1 }
}

$specs = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.spec.luau' -File | Sort-Object Name | Where-Object { $_ })
if ($specs.Count -gt 0) {
    $luneCmd = Get-Command lune -ErrorAction SilentlyContinue
    $luneExe = if ($luneCmd) { $luneCmd.Source } else { $null }
    if (-not $luneExe -and $env:USERPROFILE) {
        $rokitLune = Join-Path $env:USERPROFILE '.rokit\bin\lune.exe'
        if (Test-Path -LiteralPath $rokitLune) { $luneExe = $rokitLune }
    }

    if (-not $luneExe) {
        Write-Host '== Luau specs (lune)'
        Write-Host "FAIL: 'lune' is not installed or not on PATH. Run 'rokit install' from the repo root to install lune." -ForegroundColor Red
        $failed += 1
    } else {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        Push-Location $repoRoot
        try {
            foreach ($spec in $specs) {
                $relPath = 'scripts/tests/' + $spec.Name
                Write-Host "== $($spec.Name)"
                & $luneExe run $relPath
                if ($LASTEXITCODE -ne 0) { $failed += 1 }
            }
        } finally {
            Pop-Location
        }
    }
}

if ($failed -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green } else { Write-Host "$failed test(s) failed." -ForegroundColor Red }
exit $failed
