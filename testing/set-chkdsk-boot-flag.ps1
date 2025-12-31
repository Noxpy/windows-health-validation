<#
.SYNOPSIS
    Schedules CHKDSK for a drive by modifying BootExecute.

.DESCRIPTION
    Adds autocheck autochk flags (/f or /r) for one drive.
    Intended for testing orchestration logic.

.NOTES
    Modifies system state.
    Requires Administrator.
    PowerShell 2.0+
#>

# ---------------- Drive Selection ----------------
$drive = Read-Host "Enter drive letter (example: C:)"
$drive = $drive.Trim().ToUpper()

if ($drive -notmatch "^[A-Z]:$") {
    Write-Host "Invalid drive format." -ForegroundColor Red
    exit 1
}

# ---------------- Flag Selection ----------------
Write-Host "Select CHKDSK flag to schedule for ${drive}:"
Write-Host "1 - /f"
Write-Host "2 - /r"

$flagChoice = Read-Host "Enter selection (1 or 2)"

if ($flagChoice -eq "1") {
    $flag = "/f"
}
elseif ($flagChoice -eq "2") {
    $flag = "/r"
}
else {
    Write-Host "Invalid selection. Exiting." -ForegroundColor Red
    exit 1
}

# ---------------- Registry Paths ----------------
$sessionKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$ntDrive = "\??\$drive"

# ---------------- Read BootExecute ----------------
try {
    $bootExecute = (Get-ItemProperty -Path $sessionKey -Name BootExecute -ErrorAction Stop).BootExecute
}
catch {
    Write-Host "Failed to read BootExecute registry key." -ForegroundColor Red
    exit 1
}

# ---------------- Check for Existing Entry ----------------
$newEntry = "autocheck autochk $flag $ntDrive"
$alreadyScheduled = $false

foreach ($line in $bootExecute) {
    if ($line -eq $newEntry) {
        Write-Host "CHKDSK $flag already scheduled for ${drive}." -ForegroundColor Yellow
        $alreadyScheduled = $true
        break
    }
}

if (-not $alreadyScheduled) {
    $updated = @()
    $updated += $bootExecute
    $updated += $newEntry

    try {
        Set-ItemProperty -Path $sessionKey -Name BootExecute -Value $updated
        Write-Host "CHKDSK $flag scheduled for ${drive} (next boot)." -ForegroundColor Cyan
    }
    catch {
        Write-Host "Failed to update BootExecute registry key." -ForegroundColor Red
        exit 1
    }
}
