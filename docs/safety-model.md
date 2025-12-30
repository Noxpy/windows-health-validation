# Safety Model

This framework is designed around explicit risk boundaries.

## Read-Only Operations
- CHKDSK (no flags)
- DISM /CheckHealth
- DISM /ScanHealth

Characteristics:
- No disk writes
- No reboot required
- Safe for monitoring and compliance checks

## Write / Repair Operations
- DISM /RestoreHealth
- DISM /StartComponentCleanup
- SFC /Scannow
- CHKDSK /F, /R

Characteristics:
- May modify system state
- May require reboot
- Should be executed intentionally and logged

## Design Principles
- Never perform repairs automatically
- Fail safely when pre-checks detect risk
- Always log actions and outcomes
- Prefer validation over blind remediation
