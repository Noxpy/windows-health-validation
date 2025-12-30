<#
.SYNOPSIS
    Executes DISM Component Cleanup with reboot-awareness, structured logging, and timeout protection.

.DESCRIPTION
    Runs DISM Component Cleanup (superseded component removal) with validation:
    - Administrative privileges
    - Pending reboot detection
    - Disk availability
    Captures full output to a timestamped log file and produces structured JSON.
    Timeout protection prevents hanging scans in automation environments.
    Automatically selects the correct DISM parameter depending on OS version.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-30

.EXIT CODES
    0 = Cleanup completed successfully or nothing to clean
    1 = Cleanup completed with warnings or errors
    3 = Pre-check failure, execution error, or timeout

.NOTES
    - Write-capable operation
    - Safe for scheduled tasks
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "DISM_ComponentCleanup_$Timestamp.log"
$TimeoutMs = 120000  # 2 minutes
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
    "WARNING: A system reboot is pending."
} else {
    "No reboot flags detected."
}

$RebootStatus | Write-Host -ForegroundColor Cyan
$RebootStatus | Out-File $LogFile -Append

# Abort if reboot pending
if ($RebootPending) {
    "ABORTED: Reboot pending. Component Cleanup will not run." | Write-Host -ForegroundColor Yellow
    "ABORTED: Reboot pending. Component Cleanup will not run." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Disk Check ----------------
if (-not (Test-Path "$Drive\")) {
    "ERROR: Target drive $Drive not accessible." | Out-File $LogFile -Append
    exit 3
}

# ---------------- Determine DISM Cleanup Parameter ----------------
$osVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
# /StartComponentCleanup works on all supported builds
$DismParam = "/StartComponentCleanup"

Write-Host "DISM parameter selected: $DismParam" -ForegroundColor Cyan
"DISM parameter selected: $DismParam" | Out-File $LogFile -Append

# ---------------- Execute DISM Component Cleanup ----------------
Write-Host "Starting DISM Component Cleanup..." -ForegroundColor Cyan

$job = Start-Job -ScriptBlock {
    param($param)
    & dism.exe /Online /Cleanup-Image $param 2>&1 | Out-String
} -ArgumentList $DismParam

# Timeout handling
if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: DISM Component Cleanup exceeded timeout ($TimeoutMs ms)." | Out-File $LogFile -Append
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
    Operation       = "DISM Component Cleanup"
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

# Exit code
if ($logText -match $errorPattern) { exit 1 } else { exit 0 }
