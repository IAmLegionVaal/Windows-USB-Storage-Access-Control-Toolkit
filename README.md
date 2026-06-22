# Windows USB Storage Access Control Toolkit

A guarded PowerShell toolkit for diagnosing, repairing and controlling Windows USB mass-storage access, created by **Dewald Pretorius**.

## Files

- `Windows_USB_Storage_Access_Control_Toolkit.ps1` — diagnostics, policy changes, backups and verification.
- `Launch_USB_Storage_Access_Control.bat` — interactive technician menu.

## Actual repair and control actions

- Repair inaccessible USB storage by enabling the `USBSTOR` driver.
- Clear a machine-level USB write-protection policy.
- Disable USB mass-storage access.
- Set USB storage to read-only.
- Request a Plug and Play device rescan after changes.
- Back up relevant registry keys before every change.

The tool targets USB mass storage. It does not intentionally disable USB keyboards, mice or other non-storage USB devices.

## Usage

Diagnose only:

```powershell
.\Windows_USB_Storage_Access_Control_Toolkit.ps1 -Action Diagnose
```

Preview USB access repair:

```powershell
.\Windows_USB_Storage_Access_Control_Toolkit.ps1 -Action RepairAllSafe -DryRun
```

Repair USB storage access:

```powershell
.\Windows_USB_Storage_Access_Control_Toolkit.ps1 -Action RepairAllSafe
```

Apply read-only mode:

```powershell
.\Windows_USB_Storage_Access_Control_Toolkit.ps1 -Action SetReadOnly
```

Disable USB mass storage:

```powershell
.\Windows_USB_Storage_Access_Control_Toolkit.ps1 -Action DisableUsbStorage
```

## Safety

- Diagnostics are the default.
- Policy changes require administrator rights.
- Changes require typing `REPAIR` unless `-Yes` is supplied.
- `-DryRun` previews changes.
- Registry configuration is exported before modification.
- Domain or local Group Policy may override direct registry changes; the toolkit reports when a removable-storage policy key exists.
- Existing connected devices may require reconnection or a Windows restart.
- No password is hardcoded in the script.

## Validation status

The original USB storage lock action was tested successfully by the author on his own Windows machines. This repository preserves the working USBSTOR policy operation and adds the matching enable, read-only, repair, backup and verification workflows. Results can vary with Windows version, Group Policy, endpoint security software, storage drivers and device state.

## Output and rollback

Each run creates a timestamped desktop folder containing:

- `before.json` and `after.json`
- Connected USB storage inventory CSV files
- Registry exports for USBSTOR and storage policies
- `toolkit.log`

Registry exports provide rollback evidence. Review them before manual restoration.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully |
| 4 | Elevation required |
| 10 | User cancelled |
| 20 | Policy change or verification failed |
