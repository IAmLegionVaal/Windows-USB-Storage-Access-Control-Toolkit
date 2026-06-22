#requires -Version 5.1
<#
.SYNOPSIS
    Guarded Windows USB mass-storage access-control and repair toolkit.
.DESCRIPTION
    Diagnoses USB storage policy by default. Repairs can enable or disable the
    USBSTOR driver, set or clear removable-storage write protection, back up
    registry state and request hardware rescanning.
.NOTES
    Created by Dewald Pretorius - L2 IT Support Engineer.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Diagnose','RepairAllSafe','DisableUsbStorage','EnableUsbStorage','SetReadOnly','ClearReadOnly','RescanDevices')]
    [string]$Action = 'Diagnose',
    [string]$OutputPath,
    [switch]$DryRun,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ExitCode = 0
$UsbStorKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$StoragePolicyKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
$RemovablePolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "USB_Storage_Access_Control_$Stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$BackupPath = Join-Path $OutputPath 'backup'
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
$LogPath = Join-Path $OutputPath 'toolkit.log'

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DRYRUN')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN' { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        'DRYRUN' { Write-Host "DRY RUN: $Message" -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This policy change requires an elevated PowerShell session.'
    }
}

function Confirm-PolicyChange {
    param([Parameter(Mandatory)][string]$Message)
    if ($DryRun -or $Yes) { return $true }
    return (Read-Host "$Message Type REPAIR to continue") -eq 'REPAIR'
}

function Get-RegistryValueSafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Get-UsbStorageDevices {
    return @(
        Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceType -eq 'USB' -or $_.PNPDeviceID -like 'USBSTOR*' } |
            Select-Object Model, SerialNumber, InterfaceType, MediaType, Size, Status, PNPDeviceID
    )
}

function Save-State {
    param([Parameter(Mandatory)][string]$Stage)

    $usbStart = Get-RegistryValueSafe -Path $UsbStorKey -Name Start
    $writeProtect = Get-RegistryValueSafe -Path $StoragePolicyKey -Name WriteProtect
    $policyExists = Test-Path -LiteralPath $RemovablePolicyKey
    $devices = @(Get-UsbStorageDevices)

    $state = [ordered]@{
        Stage = $Stage
        Generated = (Get-Date).ToString('o')
        ScriptVersion = $ScriptVersion
        Computer = $env:COMPUTERNAME
        IsAdministrator = (Test-IsAdministrator)
        UsbStorStart = $usbStart
        UsbStorageEnabled = if ($null -eq $usbStart) { $null } else { [int]$usbStart -ne 4 }
        WriteProtect = $writeProtect
        ReadOnlyPolicyEnabled = if ($null -eq $writeProtect) { $false } else { [int]$writeProtect -eq 1 }
        RemovableStorageGroupPolicyKeyPresent = $policyExists
        ConnectedUsbStorageDevices = $devices
    }

    $state | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $OutputPath "$Stage.json") -Encoding UTF8
    $devices | Export-Csv -LiteralPath (Join-Path $OutputPath "$Stage-usb-devices.csv") -NoTypeInformation -Encoding UTF8
    Write-Log "Saved $Stage USB storage policy state." 'SUCCESS'
    return $state
}

function Save-RegistryBackups {
    Require-Administrator
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR' (Join-Path $BackupPath 'USBSTOR.reg') /y | Out-Null
    if (Test-Path -LiteralPath $StoragePolicyKey) {
        & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies' (Join-Path $BackupPath 'StorageDevicePolicies.reg') /y | Out-Null
    }
    if (Test-Path -LiteralPath $RemovablePolicyKey) {
        & reg.exe export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices' (Join-Path $BackupPath 'RemovableStorageDevices-Policy.reg') /y | Out-Null
    }
    Write-Log 'Exported USB storage registry configuration.' 'SUCCESS'
}

function Invoke-RescanDevices {
    Require-Administrator
    if ($DryRun) {
        Write-Log 'Would request a Plug and Play device rescan.' 'DRYRUN'
        return
    }

    $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
    if (Test-Path -LiteralPath $pnputil) {
        & $pnputil /scan-devices 2>&1 | Add-Content -LiteralPath $LogPath
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Device rescan returned exit code $LASTEXITCODE. Reconnect the USB device or restart Windows." 'WARN'
        } else {
            Write-Log 'Requested a Plug and Play device rescan.' 'SUCCESS'
        }
    } else {
        Write-Log 'PnPUtil was unavailable. Reconnect the device or restart Windows to apply the policy.' 'WARN'
    }
}

function Set-UsbStorageDriverState {
    param([Parameter(Mandatory)][ValidateSet(3,4)][int]$StartValue)

    Require-Administrator
    $description = if ($StartValue -eq 4) { 'Disable USB mass-storage access' } else { 'Enable USB mass-storage access' }
    if (-not (Confirm-PolicyChange "$description? USB keyboards and mice are not targeted.")) { throw 'User cancelled.' }

    Save-RegistryBackups
    if ($DryRun) {
        Write-Log "Would set USBSTOR Start to $StartValue." 'DRYRUN'
        return
    }

    New-Item -Path $UsbStorKey -Force | Out-Null
    New-ItemProperty -LiteralPath $UsbStorKey -Name Start -PropertyType DWord -Value $StartValue -Force | Out-Null
    $actual = Get-RegistryValueSafe -Path $UsbStorKey -Name Start
    if ([int]$actual -ne $StartValue) { throw 'USBSTOR policy verification failed.' }

    Write-Log "$description completed and verified." 'SUCCESS'
    Invoke-RescanDevices
}

function Set-UsbWriteProtection {
    param([Parameter(Mandatory)][ValidateSet(0,1)][int]$Value)

    Require-Administrator
    $description = if ($Value -eq 1) { 'Set USB storage to read-only' } else { 'Clear USB storage read-only policy' }
    if (-not (Confirm-PolicyChange "$description?")) { throw 'User cancelled.' }

    Save-RegistryBackups
    if ($DryRun) {
        Write-Log "Would set StorageDevicePolicies WriteProtect to $Value." 'DRYRUN'
        return
    }

    New-Item -Path $StoragePolicyKey -Force | Out-Null
    New-ItemProperty -LiteralPath $StoragePolicyKey -Name WriteProtect -PropertyType DWord -Value $Value -Force | Out-Null
    $actual = Get-RegistryValueSafe -Path $StoragePolicyKey -Name WriteProtect
    if ([int]$actual -ne $Value) { throw 'USB write-protection policy verification failed.' }

    Write-Log "$description completed and verified." 'SUCCESS'
    Invoke-RescanDevices
}

Write-Log "USB Storage Access Control Toolkit $ScriptVersion started. Action=$Action DryRun=$DryRun"
$before = Save-State -Stage 'before'

if ($before.RemovableStorageGroupPolicyKeyPresent) {
    Write-Log 'A removable-storage Group Policy key exists. Domain or local policy may override direct registry changes.' 'WARN'
}

try {
    switch ($Action) {
        'Diagnose' { }
        'RepairAllSafe' {
            Set-UsbStorageDriverState -StartValue 3
            Set-UsbWriteProtection -Value 0
        }
        'DisableUsbStorage' { Set-UsbStorageDriverState -StartValue 4 }
        'EnableUsbStorage' { Set-UsbStorageDriverState -StartValue 3 }
        'SetReadOnly' { Set-UsbWriteProtection -Value 1 }
        'ClearReadOnly' { Set-UsbWriteProtection -Value 0 }
        'RescanDevices' { Invoke-RescanDevices }
    }
} catch {
    if ($_.Exception.Message -eq 'User cancelled.') {
        $ExitCode = 10
        Write-Log 'Policy change cancelled by the user.' 'WARN'
    } elseif ($_.Exception.Message -match 'elevated') {
        $ExitCode = 4
        Write-Log $_.Exception.Message 'ERROR'
    } else {
        $ExitCode = 20
        Write-Log $_.Exception.Message 'ERROR'
    }
} finally {
    try { [void](Save-State -Stage 'after') } catch { Write-Log "Post-action snapshot failed: $($_.Exception.Message)" 'WARN' }
}

if ($ExitCode -eq 0) {
    Write-Log "Completed successfully. Output: $OutputPath" 'SUCCESS'
} else {
    Write-Log "Completed with exit code $ExitCode. Output: $OutputPath" 'ERROR'
}
exit $ExitCode
