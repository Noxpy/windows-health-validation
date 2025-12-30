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

.NOTES
    - Standalone PowerShell execution
    - Read-only operation
#>

# ---------------- Configuration ----------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot   = "C:\Temp\ErrorPolicyLogs"
$LogFile   = Join-Path $LogRoot "DISM_CheckHealth_$Timestamp.log"
$TimeoutMs = 60000
$Drive     = "C:"

if (-not (Test-Path $LogRoot)) { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
"==== DISM /CheckHealth START ====" | Out-File $LogFile -Append

# ---------------- Admin Check ----------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) { "ERROR: Administrative privileges required." | Out-File $LogFile -Append; exit 3 }

# ---------------- Pending Reboot ----------------
function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    return $false
}
$RebootPending = Test-PendingReboot
$RebootStatus  = if ($RebootPending) {"WARNING: A system reboot is pending."} else {"No reboot flags detected."}
$RebootStatus | Write-Host -ForegroundColor Cyan
$RebootStatus | Out-File $LogFile -Append

# ---------------- Disk Check ----------------
if (-not (Test-Path "$Drive\")) { "ERROR: Target drive $Drive not accessible." | Out-File $LogFile -Append; exit 3 }

# ---------------- Execute DISM /CheckHealth ----------------
Write-Host "Starting DISM /CheckHealth..." -ForegroundColor Cyan
$job = Start-Job -ScriptBlock { & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String }

if (-not (Wait-Job $job -Timeout ($TimeoutMs / 1000))) {
    "ERROR: DISM /CheckHealth exceeded timeout ($TimeoutMs ms)." | Out-File $LogFile -Append
    if ((Get-Command Stop-Job).Parameters.Keys -contains 'Force') { Stop-Job $job -Force } else { Stop-Job $job }
    Remove-Job $job
    exit 3
}

$DismOutput = Receive-Job $job
$DismOutput | Out-File $LogFile -Append
if ((Get-Command Remove-Job).Parameters.Keys -contains 'Force') { Remove-Job $job -Force } else { Remove-Job $job }

# ---------------- Parse Output ----------------
$logText = $DismOutput
$corruptPattern = "corrupt|repairable|Error: 0x"
$ComponentSummary = if ($logText -match $corruptPattern) { "Potential component store corruption detected." } else { "No component store corruption detected." }

# ---------------- Structured JSON ----------------
[PSCustomObject]@{
    Timestamp       = (Get-Date).ToString("s")
    Operation       = "DISM /CheckHealth"
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

"==== DISM /CheckHealth END ====" | Out-File $LogFile -Append

if ($logText -match $corruptPattern) { exit 1 } else { exit 0 }
