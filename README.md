Here’s the fully updated `README.md` with an executive-friendly summary at the top emphasizing audit, compliance, and safe orchestration. You can copy and paste the whole thing:

```markdown
# windows-health-validation

**Audit-Ready, Compliance-Friendly, Safe Orchestration for Windows System Health**  
This framework provides a modular, structured, and safety-first approach to validating and repairing Windows system health. It allows infrastructure engineers, security teams, and IT administrators to perform comprehensive assessments of disk integrity, Windows component store health, and system file integrity while maintaining full auditability and compliance visibility.

A modular, safety-first framework for validating and repairing Windows system health.  
This repository provides structured PowerShell scripts to assess disk integrity, Windows component store health, and system file integrity before performing repairs or patching.

The design emphasizes:  
- Read-only validation before repair  
- Explicit separation of safe vs disruptive actions  
- Automation-safe execution with structured logging  
- Alignment with enterprise patching and compliance workflows  
- **Version-agnostic support:** Compatible with PowerShell 2.0+ to support older Windows systems (Windows 7 / Server 2008 R2 and later). This ensures scripts can run in legacy environments while maintaining audit and compliance readiness.  

---

## Version Compatibility

| Windows Version           | PowerShell Minimum Version | Notes                                                                 |
|---------------------------|---------------------------|-----------------------------------------------------------------------|
| Windows 7 / Server 2008 R2| 2.0                       | Oldest supported OS; read-only scripts will function; repair scripts require admin privileges. |
| Windows 8 / Server 2012   | 3.0                       | Fully compatible.                                                     |
| Windows 8.1 / Server 2012 R2 | 4.0                    | Fully compatible.                                                     |
| Windows 10 / Server 2016+ | 5.1                       | Fully compatible; can use PowerShell 7.x for newer features.          |
| Windows 11 / Server 2022  | 5.1+                      | Latest systems; scripts run unchanged, backward-compatible.           |

> **Rationale:** Maintaining compatibility with PowerShell 2.0+ ensures the framework can run on legacy systems for audit, compliance, and enterprise baseline consistency. Older systems may be encountered in long-lived infrastructure environments or during phased upgrade cycles.  

---

## Repository Structure

```

windows-health-validation/
├── README.md
├── docs/
│   ├── execution-order.md
│   ├── safety-model.md
│   └── compliance-mapping.md
├── chkdsk/
│   ├── chkdsk-readonly.ps1
│   ├── chkdsk-f.ps1
│   ├── chkdsk-r.ps1
│   └── chkdsk-fr.ps1
├── dism/
│   ├── dism-checkhealth.ps1
│   ├── dism-scanhealth.ps1
│   ├── dism-restorehealth.ps1
│   └── dism-componentcleanup.ps1
├── sfc/
│   └── sfc-scan.ps1
├── orchestration/
│   ├── health-validate-readonly.ps1
│   └── health-repair-full.ps1
├── testing/
│   ├── observe-chkdsk-and-reboot-flags.ps1
│   ├── set-chkdsk-boot-flag.ps1
│   └── remove-chkdsk-boot-flag.ps1
└── logs/
└── example-log.txt

````

---

## Orchestration Workflow

```mermaid
flowchart TD
    A[Start: Read-Only Health Validation] --> B[Observe CHKDSK & Pending Reboot Flags]
    B --> C[DISM /ScanHealth Check]
    C --> D[SFC /Scannow Check]
    D --> E{Repair Needed?}
    E -- Yes --> F[Schedule CHKDSK /f or /r (if testing)]
    F --> G[Run Repair Scripts: DISM /RestoreHealth / Chkdsk / SFC]
    G --> H[Log Results]
    E -- No --> H
    H --> I[End: Validation Complete]
````

---

## Multi-Drive CHKDSK Testing Flow

```mermaid
flowchart TD
    A[Start: CHKDSK Testing Scripts] --> B{Select Drive Scope}
    B -- Single Drive --> C[Enter Drive Letter]
    B -- Multiple Drives --> D[Enter Drive Letters Separated by Commas]
    B -- ALL Fixed Drives --> E[Detect All Fixed Drives via WMI]
    C --> F[Read BootExecute]
    D --> F
    E --> F
    F --> G[Analyze CHKDSK Flags (/f, /r, /c) per Drive]
    G --> H{Action?}
    H -- Observe --> I[Display Current Flags and Pending Reboot Indicators]
    H -- Set Flag --> J[Add /f or /r for Selected Drives]
    H -- Remove Flag --> K[Remove Scheduled Flags for Selected Drives]
    I --> L[End]
    J --> L
    K --> L
```

---

## Intended Usage

1. Run **read-only validation** prior to patching or remediation.
2. Observe scheduled CHKDSK flags and pending reboot indicators using `observe-chkdsk-and-reboot-flags.ps1`.
3. Set or remove CHKDSK flags for testing with `set-chkdsk-boot-flag.ps1` and `remove-chkdsk-boot-flag.ps1`.
4. Run orchestrated read-only validation with `health-validate-readonly.ps1`.
5. Execute repair actions only when required.
6. Review and store logs for audit and compliance purposes.

---

## Example Usage

### 1. Observe CHKDSK Flags and Pending Reboots

```powershell
.\testing\observe-chkdsk-and-reboot-flags.ps1
```

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

## Notes

* Scripts are **read-only by default** unless specifically performing repairs.
* Compatible with **PowerShell 2.0+** for legacy Windows systems; supports compliance testing in older environments.
* Administrator privileges are required for modifying BootExecute and scheduling CHKDSK flags.
* Use the `logs/` folder for storing or reviewing automated outputs.
* Supports multi-drive operations, all fixed drives, and safe orchestration.

---

## Compliance Notes

* Read-only validation ensures no unintended changes occur during audits or pre-deployment checks.
* Maintaining **PowerShell 2.0+ compatibility** allows testing in legacy enterprise environments where newer PowerShell versions may not be installed.
* All scripts include explicit logging, making them suitable for compliance reporting and enterprise auditing.
* Multi-drive support and all-fixed-drive detection ensure that all disks can be assessed for compliance, reducing risk during patch cycles or system maintenance.

---

## Recommended Execution Order

1. Observe current CHKDSK flags and pending reboot indicators.
2. Validate DISM and SFC health using read-only scripts.
3. Schedule CHKDSK flags if required for testing or repair.
4. Run repair scripts only after validation and with logs enabled.
5. Reboot only if prompted by pending operations.

```


