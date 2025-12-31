````markdown
# Windows Health Validation

**Windows Health Validation** is a modular, audit-ready framework for assessing and repairing Windows system health. It provides structured, safety-first PowerShell scripts to evaluate disk integrity, Windows component store health, and system file integrity, with full compliance and audit visibility.

The framework is **designed for enterprise environments**, allowing IT administrators, security teams, and infrastructure engineers to perform comprehensive health checks before remediation or patching.

---

## About the Project

Windows Health Validation emphasizes evidence-based system health assessment. Rather than performing blind repairs, it:

- Performs **read-only validation** before any repair actions  
- Explicitly separates **safe** from **disruptive** operations  
- Provides **structured logging** for compliance reporting  
- Supports **multi-version Windows environments** (PowerShell 2.0+), including legacy systems  

This ensures system integrity checks and repairs are controlled, auditable, and safe for production environments.

---

## Project Structure

- **orchestration/** – scripts for orchestrated validation and repair  
- **testing/** – tools to observe or modify CHKDSK flags and pending reboots  
- **logs/** – directory for storing automated outputs  

---

## Supported Windows Versions

| Windows Version           | PowerShell Minimum Version | Notes                                                                 |
|---------------------------|---------------------------|-----------------------------------------------------------------------|
| Windows 7 / Server 2008 R2| 2.0                       | Read-only scripts function; repair scripts require admin privileges. |
| Windows 8 / Server 2012   | 3.0                       | Fully compatible.                                                     |
| Windows 8.1 / Server 2012 R2 | 4.0                    | Fully compatible.                                                     |
| Windows 10 / Server 2016+ | 5.1                       | Fully compatible; can use PowerShell 7.x for newer features.          |
| Windows 11 / Server 2022  | 5.1+                      | Latest systems; backward-compatible scripts.                          |

> Maintaining PowerShell 2.0+ compatibility ensures audit and compliance readiness in legacy enterprise environments.

---

## Core Features

- **Read-only validation first** to prevent unintended changes  
- **Explicit safe vs. disruptive action separation**  
- **Automation-safe execution** with structured logging  
- **Compliance alignment** for enterprise patching and auditing  
- **Multi-drive and all-fixed-drive support**  
- **Version-agnostic PowerShell support** from 2.0 onwards  

---

## Example Usage

### 1. Observe CHKDSK Flags and Pending Reboots

```powershell
.\testing\observe-chkdsk-and-reboot-flags.ps1
````

**Sample Output:**

```
Select drive scope:
1 - Single drive
2 - Multiple drives
3 - ALL fixed drives
Enter selection (1, 2, or 3): 1

Enter drive letter (example: C:): C:

=== BootExecute Raw Value ===
autocheck autochk *
autocheck autochk /f \??\C:

=== CHKDSK Scheduling Status ===
Drive C:
 • /f scheduled

=== Pending Reboot Indicators ===
 • CBS RebootPending not present
 • WU RebootRequired PRESENT
 • Pending file rename operations PRESENT

Observation complete.
```

### 2. Set a CHKDSK Boot Flag

```powershell
.\testing\set-chkdsk-boot-flag.ps1
```

**Sample Output:**

```
Enter drive letter (example: C:): D:
Select CHKDSK flag to schedule:
1 - /f
2 - /r
Enter selection: 1

CHKDSK /f scheduled for D: (next boot)
```

### 3. Remove a CHKDSK Boot Flag

```powershell
.\testing\remove-chkdsk-boot-flag.ps1
```

**Sample Output:**

```
Enter drive letter (example: C:): D:
Removed /f flag for D:
Updated BootExecute value:
autocheck autochk *
```

### 4. Run Read-Only Health Validation

```powershell
.\orchestration\health-validate-readonly.ps1
```

**Sample Output:**

```
[CHKDSK] All drives checked. No flags require action.
[DISM] Component store: No corruption detected.
[SFC] System files: No integrity violations found.
[Summary] Validation complete. Logs saved to C:\Temp\ErrorPolicyLogs
```

---

## Example Logs

```
C:\Temp\ErrorPolicyLogs\DISM_ScanHealth_20251230_170409.log
{
    "Timestamp":  "2025-12-30T17:04:54",
    "Operation":  "DISM /ScanHealth",
    "Drive":  "C:",
    "ComponentStatus":  "No component store corruption detected.",
    "RebootPending":  false,
    "ResultCode":  0
}

C:\Temp\ErrorPolicyLogs\CHKDSK_BootFlags_20251230_170500.log
Drive C:
 • /f scheduled
Drive D:
 • No CHKDSK scheduled
Pending reboot keys:
 • CBS RebootPending not present
 • WU RebootRequired PRESENT
```

---

## Recommended Execution Order

1. Observe current CHKDSK flags and pending reboot indicators
2. Validate DISM and SFC health using read-only scripts
3. Schedule CHKDSK flags if required for testing or repair
4. Run repair scripts only after validation and with logs enabled
5. Reboot only if prompted by pending operations

---

## Compliance Notes

* Read-only validation ensures **no unintended changes** during audits
* Full logging makes the framework suitable for **enterprise auditing**
* Multi-drive and all-fixed-drive detection reduces risk during **patch cycles**
* Compatible with legacy systems for **baseline compliance consistency**

---

## Disclaimer

All scripts are **non-destructive by default**. Administrative privileges are required only for modifying CHKDSK flags or performing repairs. Use in accordance with organizational policies and on authorized systems only.

---

## Contributing

Contributions are welcome. To contribute:

1. Fork the repository and create a feature branch
2. Add or improve PowerShell scripts, validation checks, or logging functionality
3. Ensure all changes are safe, accurate, and maintain audit/compliance readiness
4. Test thoroughly in a controlled environment before submission
5. Submit a pull request for review

---

## Author / Maintainer

Maintained by Noxpy.

---

## License

See the `LICENSE` file for licensing details.
