# ThermoSaver 0.1.0

Initial Windows release for Flydigi BS3 Pro.

- Default CPU thresholds: 90 C with fan stopped/unknown, 95 C with live fan RPM.
- Startup grace period: 15 minutes.
- Warning after 10 seconds continuously above the threshold.
- 20-second hibernation countdown, live CPU temperature and cancel/retry after one minute.
- Background monitor, watchdog and independent process recovery.
- Inno Setup installer; configuration preserved on upgrades.

Requirements: Windows 11 x64, paired BS3 Pro, installed PawnIO driver.
Installer unsigned. Save your work before real hibernation tests.
Validated: 64 logic tests, isolated install/uninstall and local real hibernation.
