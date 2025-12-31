<#
.SYNOPSIS
    Full system health repair orchestration.

.DESCRIPTION
    Performs corrective actions:
    - CHKDSK with repair
    - DISM /RestoreHealth
    - SFC /ScanNow
    - DISM /ComponentCleanup
#>

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = Split-Path -Parent $Root

$Steps = @(
    "chkdsk\chkdsk-f.ps1",
    "dism\dism-restorehealth.ps1",
    "sfc\sfc-scan.ps1",
    "dism\dism-componentcleanup.ps1"
)

Write-Host "==== FULL HEALTH REPAIR START ====" -ForegroundColor Cyan

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
        0 { continue }
        1 { continue }   # Repairable issues handled
        2 {
            Write-Host "UNREPAIRABLE CONDITION DETECTED. STOPPING." -ForegroundColor Red
            exit 2
        }
        3 { exit 3 }
    }
}

Write-Host "`n==== FULL HEALTH REPAIR END ====" -ForegroundColor Cyan
exit 0
