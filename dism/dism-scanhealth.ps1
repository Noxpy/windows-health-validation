<#
.SYNOPSIS
    Executes DISM /ScanHealth with reboot-awareness, structured logging, and timeout protection.

.DESCRIPTION
    Runs DISM /ScanHealth directly from PowerShell after validating:
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

.NOTES
    - Standalone PowerShell execution
    - No RMM dependencies
    - Read-only operation (safe for scheduled tasks)
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "DISM_ScanHealth_$Timestamp.log"
$TimeoutMs = 60000   # 60 seconds, adjust as needed
$Drive     = "C:"

# Ensure log directory exists
if (-not (Test-Path $LogRoot)) {
    try { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
    catch { Write-Host "ERROR: Cannot create log directory." -ForegroundColor Red; exit 3 }
}

"==== DISM /ScanHealth START ====" | Out-File $LogFile -Append

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
if ($RebootPending) {
    $RebootStatus = "WARNING: A system reboot is pending."
} else {
    $RebootStatus = "No reboot flags detected."
}

$RebootStatus | Write-Host -ForegroundColor Cyan
$RebootStatus | Out-File $LogFile -Append

# ---------------- Disk Availability Check ----------------
if (-not (Test-Path "$Drive\")) {
    "ERROR: Target drive $Drive not accessible." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Execute DISM /ScanHealth with Timeout ----------------
Write-Host "Starting DISM /ScanHealth..." -ForegroundColor Cyan

$job = Start-Job -ScriptBlock {
    & dism.exe /Online /Cleanup-Image /ScanHealth 2>&1 | Out-String
}

# Wait with timeout
if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: DISM /ScanHealth exceeded timeout ($TimeoutMs ms). Job terminated." |
        Out-File $LogFile -Append

    # Version-agnostic Stop-Job
    $stopParams = (Get-Command Stop-Job).Parameters.Keys
    if ($stopParams -contains 'Force') { Stop-Job $job -Force } else { Stop-Job $job }

    Remove-Job $job
    exit 3
}

$DismOutput = Receive-Job $job
$DismOutput | Out-File $LogFile -Append

# Remove job safely
$removeParams = (Get-Command Remove-Job).Parameters.Keys
if ($removeParams -contains 'Force') { Remove-Job $job -Force } else { Remove-Job $job }

# ---------------- Parse Output ----------------
$logText = $DismOutput
$corruptPattern   = "corrupt|repairable|Error: 0x"
$ComponentSummary = if ($logText -match $corruptPattern) {
    "Potential component store corruption detected."
} else {
    "No component store corruption detected."
}

# ---------------- Structured JSON Summary ----------------
[PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Operation       = "DISM /ScanHealth"
    Drive           = $Drive
    ComponentStatus = $ComponentSummary
    RebootPending   = $RebootPending
    ResultCode      = if ($logText -match $corruptPattern) {1} else {0}
} | ConvertTo-Json -Depth 2 | Out-File $LogFile -Append

# ---------------- Final Output ----------------
$FinalSummary = @"
$ComponentSummary
Full log: $LogFile
DISM log: C:\Windows\Logs\DISM\DISM.log
CBS log:  C:\Windows\Logs\CBS\CBS.log
"@
Write-Host $FinalSummary -ForegroundColor Green
$FinalSummary | Out-File $LogFile -Append

"==== DISM /ScanHealth END ====" | Out-File $LogFile -Append

# Exit code version-agnostic
if ($logText -match $corruptPattern) { exit 1 } else { exit 0 }
