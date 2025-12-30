<#
.SYNOPSIS
    Executes SFC /SCANNOW with strict reboot-awareness and structured logging.

.DESCRIPTION
    Runs System File Checker only when the system is in a stable state.
    If a pending reboot is detected, execution is aborted to preserve
    result integrity and reproducibility.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-30

.EXIT CODES
    0 = No integrity violations
    1 = Integrity violations found and repaired
    3 = Pre-check failure or pending reboot detected

.NOTES
    - Read-only validation with repair capability
    - Non-interactive
    - Automation-safe
    - Aborts if system state is unstable
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "SFC_Scan_$Timestamp.log"

# Ensure log directory exists
if (-not (Test-Path $LogRoot)) {
    try { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
    catch {
        Write-Host "ERROR: Cannot create log directory." -ForegroundColor Red
        exit 3
    }
}

"==== SFC /SCANNOW START ====" | Out-File $LogFile -Append

# ---------------- Admin Check ----------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    "ERROR: Administrative privileges required." | Out-File $LogFile -Append
    Write-Host "ERROR: Administrative privileges required." -ForegroundColor Red
    exit 3
}

# ---------------- Pending Reboot Detection ----------------
function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($k in $keys) {
        if (Test-Path $k) { return $true }
    }

    $sessionKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $pendingOps = Get-ItemProperty -Path $sessionKey `
        -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue

    if ($pendingOps) { return $true }

    return $false
}

$RebootPending = Test-PendingReboot

# ---- HARD GATE ----
if ($RebootPending) {
    "ERROR: Pending reboot detected. SFC execution aborted to preserve result integrity." |
        Out-File $LogFile -Append

    Write-Host "ERROR: Pending reboot detected. Aborting SFC." -ForegroundColor Red
    "==== SFC /SCANNOW ABORTED ====" | Out-File $LogFile -Append
    exit 3
}

"No reboot flags detected. Proceeding with SFC." |
    Out-File $LogFile -Append
Write-Host "No reboot flags detected. Proceeding with SFC." -ForegroundColor Cyan

# ---------------- Execute SFC ----------------
Write-Host "Starting SFC /SCANNOW..." -ForegroundColor Cyan
$sfcOutput = & sfc.exe /scannow 2>&1
$exitCode  = $LASTEXITCODE

$sfcOutput | Out-File $LogFile -Append

# ---------------- Parse Output ----------------
$logText = $sfcOutput -join "`n"

if ($logText -match "Windows Resource Protection did not find any integrity violations") {
    $Result  = 0
    $Message = "No integrity violations detected."
}
elseif ($logText -match "Windows Resource Protection found corrupt files and successfully repaired them") {
    $Result  = 1
    $Message = "Integrity violations found and repaired."
}
elseif ($logText -match "Windows Resource Protection found corrupt files but was unable to fix some") {
    $Result  = 1
    $Message = "Integrity violations detected but not fully repaired."
}
else {
    $Result  = 1
    $Message = "SFC completed with ambiguous output."
}

# ---------------- Structured JSON Summary ----------------
[PSCustomObject]@{
    Timestamp      = (Get-Date).ToString("s")
    Operation      = "SFC /SCANNOW"
    ResultCode     = $Result
    RebootPending  = $false
} | ConvertTo-Json -Depth 2 | Out-File $LogFile -Append

# ---------------- Final Output ----------------
Write-Host $Message -ForegroundColor Green
$Message | Out-File $LogFile -Append

"==== SFC /SCANNOW END ====" | Out-File $LogFile -Append
exit $Result
