<#
.SYNOPSIS
    Observes CHKDSK BootExecute flags and pending reboot indicators.

.DESCRIPTION
    Operator may select:
      1) One drive
      2) Multiple drives
      3) ALL fixed drives

    Reports scheduled CHKDSK flags (/f /r /c) per drive.
    Reports standard Windows reboot indicators.

.NOTES
    Read-only
    PowerShell 2.0+
#>

# ---------------- Drive Selection ----------------
Write-Host ""
Write-Host "Select drive scope:" -ForegroundColor Cyan
Write-Host "1 - Single drive"
Write-Host "2 - Multiple drives"
Write-Host "3 - ALL fixed drives"

$choice = Read-Host "Enter selection (1, 2, or 3)"

$drives = @()

if ($choice -eq "1") {

    $d = Read-Host "Enter drive letter (example: C:)"
    $d = $d.Trim().ToUpper()

    if ($d -notmatch "^[A-Z]:$") {
        Write-Host "Invalid drive format." -ForegroundColor Red
        exit 1
    }

    $drives += $d
}

elseif ($choice -eq "2") {

    $input = Read-Host "Enter drive letters separated by commas (example: C:,D:,E:)"
    $parts = $input.Split(",")

    foreach ($p in $parts) {
        $d = $p.Trim().ToUpper()
        if ($d -match "^[A-Z]:$") {
            $drives += $d
        }
    }

    if ($drives.Count -eq 0) {
        Write-Host "No valid drives provided." -ForegroundColor Red
        exit 1
    }
}

elseif ($choice -eq "3") {

    # PowerShell 2.0 compatible fixed-disk enumeration
    $wmi = Get-WmiObject Win32_LogicalDisk -ErrorAction SilentlyContinue
    foreach ($disk in $wmi) {
        if ($disk.DriveType -eq 3) {
            $drives += $disk.DeviceID
        }
    }

    if ($drives.Count -eq 0) {
        Write-Host "No fixed drives detected." -ForegroundColor Red
        exit 1
    }
}

else {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

# ---------------- BootExecute Read ----------------
$sessionKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"

$bootExecute = $null
try {
    $bootExecute = (Get-ItemProperty -Path $sessionKey -Name BootExecute).BootExecute
}
catch {
    Write-Host "Failed to read BootExecute." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== BootExecute Raw Value ===" -ForegroundColor Cyan
foreach ($line in $bootExecute) {
    Write-Host $line
}

# ---------------- CHKDSK Flag Analysis ----------------
Write-Host ""
Write-Host "=== CHKDSK Scheduling Status ===" -ForegroundColor Cyan

foreach ($drive in $drives) {

    $ntDrive = "\??\$drive"
    $escaped = [regex]::Escape($ntDrive)

    Write-Host ""
    Write-Host "Drive ${drive}:" -ForegroundColor Yellow

    $found = $false

    if ($bootExecute -match "autocheck autochk /f $escaped") {
        Write-Host " • /f scheduled" -ForegroundColor Yellow
        $found = $true
    }

    if ($bootExecute -match "autocheck autochk /r $escaped") {
        Write-Host " • /r scheduled" -ForegroundColor Yellow
        $found = $true
    }

    if ($bootExecute -match "autocheck autochk /c $escaped") {
        Write-Host " • /c scheduled" -ForegroundColor Yellow
        $found = $true
    }

    if (-not $found) {
        Write-Host " • No CHKDSK scheduled" -ForegroundColor Green
    }
}

# ---------------- Pending Reboot Indicators ----------------
Write-Host ""
Write-Host "=== Pending Reboot Indicators ===" -ForegroundColor Cyan

$rebootKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
)

foreach ($key in $rebootKeys) {
    if (Test-Path $key) {
        Write-Host " • PRESENT: $key" -ForegroundColor Yellow
    }
    else {
        Write-Host " • Not present: $key" -ForegroundColor Green
    }
}

$pendingRename = Get-ItemProperty `
    -Path $sessionKey `
    -Name PendingFileRenameOperations `
    -ErrorAction SilentlyContinue

if ($pendingRename) {
    Write-Host " • Pending file rename operations PRESENT" -ForegroundColor Yellow
}
else {
    Write-Host " • No pending file rename operations" -ForegroundColor Green
}

Write-Host ""
Write-Host "Observation complete." -ForegroundColor Cyan
