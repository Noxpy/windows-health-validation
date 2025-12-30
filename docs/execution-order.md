# Execution Order

This document defines the recommended and supported execution order for
Windows health validation and repair.

## Phase 1: Read-Only Validation (Safe)

These checks do not modify disk or system state and are safe for
automation and scheduled execution.

1. CHKDSK (read-only)
2. DISM /CheckHealth
3. DISM /ScanHealth

If all checks pass, systems are considered safe for patching.

## Phase 2: Component Store Repair (Conditional)

Only execute if Phase 1 indicates corruption.

4. DISM /RestoreHealth
5. DISM /StartComponentCleanup

## Phase 3: System File Repair

6. SFC /Scannow

## Phase 4: Disk Repair (Disruptive)

Only execute when disk-level issues are confirmed.

7. CHKDSK /F
8. CHKDSK /R
9. CHKDSK /F /R

Disk repair actions may require downtime and reboots and should be
change-controlled.
