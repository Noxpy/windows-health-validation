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

$drive = Read-Host "Enter drive letter (example: C:)"
$drive = $drive.Trim().ToUpper()

if ($drive -notmatch "^[A-Z]:$") {
    Write-Host "Invalid drive format." -ForegroundColor Red
    exit 1
}

Write-Host "Select flag:"
Write-Host "1 - /f"
Write-Host "2 - /r"

$flagChoice = Read-Host "Enter selection"

if ($flagChoice -eq "1") {
    $flag = "/f"
}
elseif ($flagChoice -eq "2") {
    $flag = "/r"
}
else {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

$sessionKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$ntDrive = "\??\$drive"

$bootExecute = (Get-ItemProperty $sessionKey -Name BootExecute).BootExecute

$newEntry = "autocheck autochk $flag $ntDrive"

foreach ($line in $bootExecute) {
    if ($line -eq $newEntry) {
        Write-Host "Flag already present." -ForegroundColor Yellow
        exit 0
    }
}

$updated = @()
$updated += $bootExecute
$updated += $newEntry

Set-ItemProperty -Path $sessionKey -Name BootExecute -Value $updated

Write-Host "CHKDSK $flag scheduled for $drive (next boot)." -ForegroundColor Cyan
