<#
.SYNOPSIS
    Executes DISM /ComponentCleanup with reboot-awareness, structured logging, and timeout protection.

.DESCRIPTION
    Runs DISM /ComponentCleanup to reduce the WinSxS component store size by removing superseded components.
    Validates administrative privileges, detects pending reboot conditions, and captures full output
    to a timestamped log file with a structured JSON summary.
    Includes timeout protection to prevent indefinite hangs in automated environments.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-30

.EXIT CODES
    0 = Cleanup completed successfully or nothing to clean
    1 = Cleanup completed with warnings
    3 = Pre-check failure, execution error, or timeout

.NOTES
    - Write-capable operation
    - No reboot flags are created or modified
    - Safe for automation and scheduled tasks
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "DISM_ComponentCleanup_$Timestamp.log"
$TimeoutMs = 120000   # 2 minutes
$Drive     = "C:"

if (-not (Test-Path $LogRoot)) {
    try { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
    catch { Write-Host "ERROR: Cannot create log directory." -ForegroundColor Red; exit 3 }
}

"==== DISM /ComponentCleanup START ====" | Out-File $LogFile -Append

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
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    if (Test-Path $keys[0] -or Test-Path $keys[1]) { return $true }

    $pendingRename = Get-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
        -Name "PendingFileRenameOperations" `
        -ErrorAction SilentlyContinue

    return [bool]$pendingRename
}

$RebootPending = Test-PendingReboot
$RebootStatus  = if ($RebootPending) {
    "WARNING: A system reboot is pending."
} else {
    "No reboot flags detected."
}

$RebootStatus | Write-Host -ForegroundColor Cyan
$RebootStatus | Out-File $LogFile -Append

# ---------------- Disk Check ----------------
if (-not (Test-Path "$Drive\")) {
    "ERROR: Target drive $Drive not accessible." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Execute DISM /ComponentCleanup ----------------
Write-Host "Starting DISM /ComponentCleanup..." -ForegroundColor Cyan

$job = Start-Job -ScriptBlock {
    & dism.exe /Online /Cleanup-Image /ComponentCleanup 2>&1 | Out-String
}

if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: DISM /ComponentCleanup exceeded timeout ($TimeoutMs ms)." |
        Out-File $LogFile -Append

    if ((Get-Command Stop-Job).Parameters.Keys -contains 'Force') {
        Stop-Job $job -Force
    } else {
        Stop-Job $job
    }

    Remove-Job $job
    exit 3
}

$DismOutput = Receive-Job $job
$DismOutput | Out-File $LogFile -Append

if ((Get-Command Remove-Job).Parameters.Keys -contains 'Force') {
    Remove-Job $job -Force
} else {
    Remove-Job $job
}

# ---------------- Parse Output ----------------
$logText = $DismOutput
$successPattern = "completed successfully|operation completed"
$warningPattern = "reboot required|warning"
$errorPattern   = "failed|error|0x"

$ComponentSummary = if ($logText -match $errorPattern) {
    "DISM Component Cleanup encountered errors."
} elseif ($logText -match $warningPattern) {
    "DISM Component Cleanup completed with warnings."
} else {
    "DISM Component Cleanup completed successfully."
}

# ---------------- Structured JSON Summary ----------------
[PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Operation       = "DISM /ComponentCleanup"
    Drive           = $Drive
    ResultSummary   = $ComponentSummary
    RebootPending   = $RebootPending
    ResultCode      = if ($logText -match $errorPattern) {1} else {0}
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

"==== DISM /ComponentCleanup END ====" | Out-File $LogFile -Append

if ($logText -match $errorPattern) { exit 1 } else { exit 0 }
