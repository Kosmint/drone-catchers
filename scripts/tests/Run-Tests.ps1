<#
.SYNOPSIS
  Runs all automation script tests (no GitHub, no agy, no Studio needed).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tests\Run-Tests.ps1
#>
$failed = 0
foreach ($t in @('Test-AgyGate.ps1', 'Test-GeminiHelper.ps1')) {
    Write-Host "== $t"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $t)
    $failed += $LASTEXITCODE
}
if ($failed -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green } else { Write-Host "$failed test(s) failed." -ForegroundColor Red }
exit $failed
