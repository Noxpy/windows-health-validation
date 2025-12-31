<#
.SYNOPSIS
    Removes scheduled CHKDSK entries from BootExecute.

.DESCRIPTION
    Allows removal of /f, /r, or all CHKDSK entries for a drive.

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

$sessionKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$ntDrive = "\??\$drive"
$escaped = [regex]::Escape($ntDrive)

$bootExecute = (Get-ItemProperty $sessionKey -Name BootExecute).BootExecute

$filtered = @()
$removed = $false

foreach ($line in $bootExecute) {
    if ($line -match "autocheck autochk .* $escaped") {
        Write-Host "Removing: $line" -ForegroundColor Yellow
        $removed = $true
    }
    else {
        $filtered += $line
    }
}

if (-not $removed) {
    Write-Host "No CHKDSK entries found for $drive." -ForegroundColor Green
    exit 0
}

Set-ItemProperty -Path $sessionKey -Name BootExecute -Value $filtered
Write-Host "CHKDSK scheduling removed for $drive." -ForegroundColor Cyan
