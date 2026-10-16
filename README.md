# ThermoSaver

Windows CPU temperature protection for a laptop using a Flydigi BS3 Pro cooler.

## Download

Download the installer from [Releases](https://github.com/Artllex/ThermoSaver/releases).
Windows 11 x64, Bluetooth pairing with BS3 Pro and an installed PawnIO driver
(provided by Flydigi Space Station) are required. Installation requires admin rights.
The installer is unsigned and may trigger a Windows SmartScreen warning.

## Behavior

- Default threshold: 90 C when the cooler fan is stopped or its state is unknown;
  95 C when live RPM reports confirm that the fan is running.
- Monitoring arms 15 minutes after Windows startup.
- A dark BatteryGuard-style notification appears near the tray for 10 seconds,
  once per Windows sign-in. It distinguishes active protection from the startup delay.
- Scheduled tasks use a windowless host, so PowerShell does not flash a console.
- A warning opens after at least 10 seconds continuously above the active threshold.
  A reading at or below the threshold resets this qualification period.
- The warning counts down 20 seconds before real hibernation. Its CPU reading updates
  every 5 seconds. You can hibernate immediately or cancel.
- Cancel postpones the next warning by one minute while the temperature remains high.
- Monitoring runs in the background as SYSTEM with AboveNormal priority.
  A watchdog and scheduled recovery restart missing or stale processes.
- Existing configuration is preserved during upgrades. The fan state is read directly
  from Bluetooth HID reports; Flydigi's application does not need to remain open.

This is supplementary protection, not a replacement for firmware thermal protection.
Sensor or software failures can prevent it from working. Save your work before testing
real hibernation. Currently tested on one ASUS ProArt P16 with BS3 Pro; other systems
and CPU sensor names are not guaranteed to work.

## Source And Build

Application sources are in `src/`; Inno Setup sources are in `installer/`.
PowerShell 7.6, Inno Setup 7 and the dependencies listed in `THIRD-PARTY-NOTICES.md`
are required to build the installer. Dependencies and the PowerShell runtime are not
committed to Git. Provide directories containing the DLLs and a full Windows x64
PowerShell distribution:

```powershell
./installer/Build.ps1 -DependencyDirectory C:/dependencies/lib -PowerShellDirectory C:/dependencies/pwsh
```

Run the logic tests (no hibernation performed):

```powershell
pwsh -NoProfile -File ./src/Test-Guard.ps1
```

Tests require HidSharp.dll in `src/lib`. Version 0.1.1 has 64 passing logic tests.
Run `./tests/Test-Host.ps1` to verify windowless startup, child cleanup and exit codes.
The installer and uninstaller were tested in an isolated directory; actual hibernation
and the cooler-dependent threshold were also tested locally.

ThermoSaver is not affiliated with Flydigi.

## License

ThermoSaver is licensed under the [MIT License](LICENSE), copyright 2026 Artllex.
The installer includes the license. Dependencies retain their separate licenses;
see [Third-Party Notices](THIRD-PARTY-NOTICES.md).
