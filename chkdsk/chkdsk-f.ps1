<#
.SYNOPSIS
    Executes CHKDSK with /F (fix) safely, with reboot awareness, structured logging,
    explicit scheduling validation, and timeout protection.

.DESCRIPTION
    Runs CHKDSK /F on the specified drive after checking for:
    - Administrative privileges
    - Pending reboot conditions
    - Already scheduled CHKDSK operations
    - Disk availability
    Automatically schedules repairs for system volumes if they cannot be executed live.
    Produces human-readable logs and structured JSON summaries.
    Aborts if execution exceeds the timeout.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-30

.EXIT CODES
    0 = No issues detected
    1 = Issues detected or repaired
    2 = Repair scheduled (reboot required)
    3 = Pre-check failure, execution error, or timeout

.NOTES
    - Non-interactive
    - Write-capable operation
    - Automation-safe
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "CHKDSK_F_Option_$Timestamp.log"
$Drive     = "C:"
$TimeoutMs = 60000  # 60 seconds timeout (adjust as needed)

# Ensure log directory exists
if (-not (Test-Path $LogRoot)) {
    try { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
    catch { Write-Host "ERROR: Cannot create log directory." -ForegroundColor Red; exit 3 }
}

"==== CHKDSK /F START ====" | Out-File $LogFile -Append

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

# ---------------- Safety Functions ----------------
function Test-PendingReboot {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    return $false
}

function Test-ScheduledChkDsk {
    $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $be = (Get-ItemProperty $k -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
    return ($be -and $be -ne "autocheck autochk *")
}

# ---------------- Pre-Checks ----------------
$RebootPending    = Test-PendingReboot
$AlreadyScheduled = Test-ScheduledChkDsk
$DiskAvailable    = Test-Path "$Drive\"

if (-not $DiskAvailable) {
    "ERROR: Target drive not accessible." | Out-File $LogFile -Append
    exit 3
}
if ($AlreadyScheduled) {
    "INFO: CHKDSK already scheduled. No action taken." | Out-File $LogFile -Append
    exit 2
}
if ($RebootPending) {
    "WARNING: System reboot pending. CHKDSK scheduling may be deferred." | Out-File $LogFile -Append
}
if ($Drive -eq "C:") {
    "INFO: System volume detected. Repair will be scheduled if in use." | Out-File $LogFile -Append
}

# ---------------- Execute CHKDSK /F with Timeout ----------------
Write-Host "Scheduling CHKDSK /F on $Drive..." -ForegroundColor Yellow

$job = Start-Job -ScriptBlock {
    param($drive)
    cmd.exe /c "echo Y|chkdsk $drive /F 2>&1" | Out-String
} -ArgumentList $Drive

if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: CHKDSK exceeded timeout ($TimeoutMs ms). Job terminated." | Out-File $LogFile -Append
    Stop-Job $job -Force
    Remove-Job $job -Force
    exit 3
}

$chkdskOutput = Receive-Job $job
$chkdskOutput | Out-File $LogFile -Append
Remove-Job $job -Force

# ---------------- Post-Execution Validation ----------------
$ScheduledAfter = Test-ScheduledChkDsk
$logText        = $chkdskOutput

$fixedPattern   = "made corrections"
$cleanPattern   = "Windows has made no further repairs"
$failedPattern  = "failed|unable|error"

if ($ScheduledAfter) {
    $Result  = 2
    $Message = "CHKDSK /F successfully scheduled for next reboot."
}
elseif ($logText -match $failedPattern) {
    $Result  = 3
    $Message = "CHKDSK encountered an execution error."
}
elseif ($logText -match $fixedPattern) {
    $Result  = 1
    $Message = "File system errors were repaired."
}
elseif ($logText -match $cleanPattern) {
    $Result  = 0
    $Message = "No repairs were necessary."
}
else {
    $Result  = 1
    $Message = "CHKDSK completed with warnings or ambiguous output."
}

# ---------------- Structured Summary ----------------
[PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Drive           = $Drive
    Mode            = "Fix"
    ResultCode      = $Result
    RebootPending   = $RebootPending
    RepairScheduled = ($Result -eq 2)
} | ConvertTo-Json -Depth 2 | Out-File $LogFile -Append

Write-Host $Message -ForegroundColor Green
"==== CHKDSK /F END ====" | Out-File $LogFile -Append

exit $Result
