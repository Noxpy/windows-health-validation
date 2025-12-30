<#
.SYNOPSIS
    Executes DISM /CheckHealth with reboot-awareness, structured logging, and timeout protection.

.DESCRIPTION
    Runs DISM /CheckHealth directly from PowerShell after validating:
    - Administrative privileges
    - Pending reboot conditions
    - Disk availability
    Captures full output to a timestamped log file and produces a structured JSON summary.
    Timeout protection prevents hanging scans in automated environments.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-30

.EXIT CODES
    0 = No corruption detected
    1 = Potential corruption detected
    3 = Pre-check failure, execution error, or timeout
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "DISM_CheckHealth_$Timestamp.log"
$TimeoutMs = 30000   # 30 seconds is usually sufficient for /CheckHealth
$Drive     = "C:"

# Ensure log directory exists
if (-not (Test-Path $LogRoot)) {
    try { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
    catch { Write-Host "ERROR: Cannot create log directory." -ForegroundColor Red; exit 3 }
}

"==== DISM /CheckHealth START ====" | Out-File $LogFile -Append

# ---------------- Admin Check ----------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    "ERROR: Administrative privileges required." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Pending Reboot Check ----------------
function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    return $false
}

$RebootPending = Test-PendingReboot
$RebootStatus = if ($RebootPending) {
    "NOTE: A system reboot is pending, but CheckHealth will run."
} else { "No reboot flags detected." }

$RebootStatus | Write-Host -ForegroundColor Cyan
$RebootStatus | Out-File $LogFile -Append

# ---------------- Disk Availability Check ----------------
if (-not (Test-Path "$Drive\")) {
    "ERROR: Target drive $Drive not accessible." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Execute DISM /CheckHealth with Timeout ----------------
Write-Host "Starting DISM /CheckHealth..." -ForegroundColor Cyan

$job = Start-Job -ScriptBlock {
    & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
}

# Wait with timeout
if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: DISM /CheckHealth exceeded timeout ($TimeoutMs ms). Job terminated." |
        Out-File $LogFile -Append

    Stop-Job $job -Force
    Remove-Job $job
    exit 3
}

$DismOutput = Receive-Job $job
$DismOutput | Out-File $LogFile -Append
Remove-Job $job -Force

# ---------------- Parse Output ----------------
$logText = $DismOutput

# Only flag corruption if DISM explicitly reports it; ignore "No component store corruption detected"
if ($logText -match "(?i)(corrupt|repairable|Error: 0x)" -and
    $logText -notmatch "(?i)No component store corruption detected") {
    $ComponentSummary = "Potential component store corruption detected."
    $ResultCode = 1
} else {
    $ComponentSummary = "No component store corruption detected."
    $ResultCode = 0
}

# ---------------- Final Output ----------------
$FinalSummary = @"
$ComponentSummary
$RebootStatus
Full log: $LogFile
DISM log: C:\Windows\Logs\DISM\DISM.log
CBS log:  C:\Windows\Logs\CBS\CBS.log
"@
Write-Host $FinalSummary -ForegroundColor Green
$FinalSummary | Out-File $LogFile -Append

# ---------------- Structured JSON Summary ----------------
[PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Operation       = "DISM /CheckHealth"
    Drive           = $Drive
    ComponentStatus = $ComponentSummary
    RebootPending   = $RebootPending
    ResultCode      = $ResultCode
} | ConvertTo-Json -Depth 2 | Out-File $LogFile -Append

"==== DISM /CheckHealth END ====" | Out-File $LogFile -Append

# Exit code based solely on actual corruption
exit $ResultCode
