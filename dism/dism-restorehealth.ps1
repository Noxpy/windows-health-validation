<#
.SYNOPSIS
    Executes DISM /RestoreHealth with reboot-awareness, structured logging, and timeout protection.

.DESCRIPTION
    Runs DISM /RestoreHealth after validating:
    - Administrative privileges
    - Pending reboot conditions
    - Disk availability
    Captures full output to a timestamped log file and produces structured JSON.
    Timeout protection prevents hanging scans in automated environments.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-30

.EXIT CODES
    0 = RestoreHealth completed successfully
    1 = RestoreHealth completed with warnings or errors
    3 = Pre-check failure, execution error, or timeout

.NOTES
    - Write-capable operation
    - Safe for scheduled tasks
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "DISM_RestoreHealth_$Timestamp.log"
$TimeoutMs = 300000   # 5 minutes, adjust as needed
$Drive     = "C:"

# Ensure log directory exists
if (-not (Test-Path $LogRoot)) {
    try { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
    catch { Write-Host "ERROR: Cannot create log directory." -ForegroundColor Red; exit 3 }
}

"==== DISM /RestoreHealth START ====" | Out-File $LogFile -Append

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

# ---------------- Pending Reboot Detection ----------------
function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($key in $keys) {
        if (Test-Path $key) { return $true }
    }

    $pendingRename = Get-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
        -Name "PendingFileRenameOperations" `
        -ErrorAction SilentlyContinue

    return [bool]$pendingRename
}

$RebootPending = Test-PendingReboot
$RebootStatus  = if ($RebootPending) {
    "WARNING: A system reboot is pending. DISM /RestoreHealth will not run."
} else {
    "No reboot flags detected."
}

$RebootStatus | Write-Host -ForegroundColor Cyan
$RebootStatus | Out-File $LogFile -Append

# Abort if reboot pending
if ($RebootPending) {
    $SkippedMessage = "ABORTED: Reboot pending. DISM /RestoreHealth was not executed."
    Write-Host $SkippedMessage -ForegroundColor Yellow
    $SkippedMessage | Out-File $LogFile -Append

    # Structured JSON summary for skipped execution
    [PSCustomObject]@{
        Timestamp     = (Get-Date).ToString("s")
        Operation     = "DISM /RestoreHealth"
        Drive         = $Drive
        ResultSummary = "Skipped due to pending reboot."
        RebootPending = $true
        ResultCode    = 3
    } | ConvertTo-Json -Depth 2 | Out-File $LogFile -Append

    exit 3
}

# ---------------- Disk Check ----------------
if (-not (Test-Path "$Drive\")) {
    "ERROR: Target drive $Drive not accessible." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Execute DISM /RestoreHealth ----------------
Write-Host "Starting DISM /RestoreHealth..." -ForegroundColor Cyan

$job = Start-Job -ScriptBlock {
    & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
}

# Timeout handling
if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: DISM /RestoreHealth exceeded timeout ($TimeoutMs ms)." | Out-File $LogFile -Append
    if ((Get-Command Stop-Job).Parameters.Keys -contains 'Force') { Stop-Job $job -Force } else { Stop-Job $job }
    Remove-Job $job
    exit 3
}

$DismOutput = Receive-Job $job
$DismOutput | Out-File $LogFile -Append
if ((Get-Command Remove-Job).Parameters.Keys -contains 'Force') { Remove-Job $job -Force } else { Remove-Job $job }

# ---------------- Parse Output ----------------
$logText = $DismOutput
$successPattern = "completed successfully|operation completed"
$warningPattern = "reboot required|warning|error: 0x"

$RestoreSummary = if ($logText -match $warningPattern) {
    "DISM /RestoreHealth completed with warnings or errors."
} else {
    "DISM /RestoreHealth completed successfully."
}

# ---------------- Structured JSON Summary ----------------
[PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Operation       = "DISM /RestoreHealth"
    Drive           = $Drive
    ResultSummary   = $RestoreSummary
    RebootPending   = $RebootPending
    ResultCode      = if ($logText -match $warningPattern) {1} else {0}
} | ConvertTo-Json -Depth 2 | Out-File $LogFile -Append

# ---------------- Final Output ----------------
$FinalSummary = @"
$RestoreSummary
Full log: $LogFile
DISM log: C:\Windows\Logs\DISM\DISM.log
CBS log:  C:\Windows\Logs\CBS\CBS.log
"@

Write-Host $FinalSummary -ForegroundColor Green
$FinalSummary | Out-File $LogFile -Append

"==== DISM /RestoreHealth END ====" | Out-File $LogFile -Append

# Exit code
if ($logText -match $warningPattern) { exit 1 } else { exit 0 }
