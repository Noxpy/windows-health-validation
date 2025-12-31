<#
.SYNOPSIS
    Read-only system health validation orchestration.

.DESCRIPTION
    Executes non-destructive health checks:
    - CHKDSK (read-only)
    - DISM /CheckHealth
    - DISM /ScanHealth
    - SFC /ScanNow

    No repairs are performed.
#>

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = Split-Path -Parent $Root

$Steps = @(
    "chkdsk\chkdsk-readonly.ps1",
    "dism\dism-checkhealth.ps1",
    "dism\dism-scanhealth.ps1",
    "sfc\sfc-scan.ps1"
)

$OverallExit = 0

Write-Host "==== READ-ONLY HEALTH VALIDATION START ====" -ForegroundColor Cyan

foreach ($step in $Steps) {
    $path = Join-Path $Repo $step

    Write-Host "`n--- Running $step ---" -ForegroundColor Yellow

    if (-not (Test-Path $path)) {
        Write-Host "ERROR: Missing script $step" -ForegroundColor Red
        exit 3
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path
    $code = $LASTEXITCODE

    Write-Host "Exit code: $code"

    switch ($code) {
        0 { }
        1 { if ($OverallExit -lt 1) { $OverallExit = 1 } }
        2 { $OverallExit = 2 }
        3 { exit 3 }
    }
}

Write-Host "`n==== READ-ONLY HEALTH VALIDATION END ====" -ForegroundColor Cyan
exit $OverallExit
