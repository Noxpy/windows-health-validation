<#
.SYNOPSIS
    Executes CHKDSK (read-only) with enhanced safety, reboot-awareness,
    scheduled CHKDSK detection, structured logging, and validation output.

.DESCRIPTION
    Runs CHKDSK on the system drive in read-only mode after checking for:
    - Administrative privileges
    - Pending reboot conditions
    - Already scheduled CHKDSK operations
    - Disk availability
    Captures full output to a timestamped log file and emits both
    human-readable and structured summaries suitable for automation.

.AUTHOR
    Anthony Marturano

.MODIFIED
    2025-12-19

.NOTES
    - Standalone PowerShell execution
    - No RMM dependencies
    - Reboot-safe execution guard
    - Read-only operation only
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "CHKDSK_ReadOnly_$Timestamp.log"
$Drive     = "C:"

# ---------------- Ensure Log Directory ----------------
if (-not (Test-Path $LogRoot)) {
    try {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    } catch {
        Write-Host "ERROR: Cannot create log directory $LogRoot. $_" -ForegroundColor Red
        exit 3
    }
}

"==== CHKDSK READ-ONLY VALIDATION START ====" |
    Out-File -FilePath $LogFile -Encoding UTF8 -Append

# ---------------- Admin Privilege Check ----------------
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $msg = "ERROR: Script must be run with administrative privileges."
    Write-Host $msg -ForegroundColor Red
    $msg | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    exit 3
}

# ---------------- Functions ----------------
function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($key in $keys) {
        if (Test-Path $key) { return $true }
    }

    $sessionKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    if (Test-Path $sessionKey) {
        $pending = Get-ItemProperty -Path $sessionKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($pending) { return $true }
    }

    return $false
}

function Test-ScheduledChkDsk {
    $sessionKey  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $bootExecute = (Get-ItemProperty -Path $sessionKey -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
    if ($bootExecute -and ($bootExecute -ne "autocheck autochk *")) { return $true }
    return $false
}

# ---------------- Pre-Checks ----------------
$RebootPending   = Test-PendingReboot
$ScheduledChkDsk = Test-ScheduledChkDsk
$DiskAvailable   = Test-Path "$Drive\"

$RebootStatusMessage = if ($RebootPending) {
    "WARNING: A system reboot is pending."
} elseif ($ScheduledChkDsk) {
    "WARNING: CHKDSK /R or /F is scheduled at next reboot."
} elseif (-not $DiskAvailable) {
    "ERROR: System drive $Drive is not accessible."
} else {
    "No reboot flags or scheduled CHKDSK detected."
}

$RebootStatusMessage | Write-Host -ForegroundColor Cyan
$RebootStatusMessage | Out-File -FilePath $LogFile -Encoding UTF8 -Append

if ($RebootPending -or $ScheduledChkDsk -or -not $DiskAvailable) {
    $msg = "CHKDSK read-only aborted due to failed pre-checks."
    Write-Warning $msg
    $msg | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    exit 2
}

# ---------------- Run CHKDSK (Read-Only) ----------------
Write-Host "Running CHKDSK (read-only) on $Drive..." -ForegroundColor Cyan

try {
    $chkdskOutput = cmd.exe /c "chkdsk $Drive" 2>&1
    $ChkDskExitCode = $LASTEXITCODE
} catch {
    Write-Host "ERROR: Failed to execute CHKDSK. $_" -ForegroundColor Red
    $_ | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    exit 3
}

if (-not $chkdskOutput -or $chkdskOutput.Count -eq 0) {
    "ERROR: CHKDSK produced no output." |
        Out-File -FilePath $LogFile -Encoding UTF8 -Append
    exit 3
}

$chkdskOutput | Out-File -FilePath $LogFile -Encoding UTF8 -Append
"CHKDSK exit code: $ChkDskExitCode" |
    Out-File -FilePath $LogFile -Encoding UTF8 -Append

# ---------------- Parse Output ----------------
$cleanOutput = $chkdskOutput |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" }

$healthyPattern = "Windows has scanned the file system and found no problems."
$errorPattern   = "found (?:errors|corruption|problems)"

if ($cleanOutput -contains $healthyPattern) {
    $CHKResult  = 0
    $CHKMessage = "Drive is healthy. No problems found."
} elseif ($cleanOutput -match $errorPattern) {
    $CHKResult  = 1
    $CHKMessage = "File system problems or warnings detected."
} else {
    $CHKResult  = 1
    $CHKMessage = "CHKDSK output inconclusive. Review log for details."
}

# ---------------- Structured Summary ----------------
$SummaryObject = [PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Drive           = $Drive
    Healthy         = ($CHKResult -eq 0)
    RebootPending   = $RebootPending
    ScheduledChkDsk = $ScheduledChkDsk
    ExitCode        = $CHKResult
}

$SummaryObject | ConvertTo-Json -Depth 2 |
    Out-File -FilePath $LogFile -Encoding UTF8 -Append

# ---------------- Final Output ----------------
$FinalSummary = @"
$CHKMessage
Reboot / CHKDSK Status: $RebootStatusMessage
Full log: $LogFile
"@

Write-Host $FinalSummary -ForegroundColor Green
$FinalSummary | Out-File -FilePath $LogFile -Encoding UTF8 -Append

"==== CHKDSK READ-ONLY VALIDATION END ====" |
    Out-File -FilePath $LogFile -Encoding UTF8 -Append

exit $CHKResult
