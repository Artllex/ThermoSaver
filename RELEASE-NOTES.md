# ThermoSaver 0.1.1

Startup notifications and windowless background operation for Flydigi BS3 Pro.

- BatteryGuard-style startup notification near the tray, dismissed after 10 seconds.
- One notification per Windows sign-in; automatic recovery does not repeat it.
- Notification distinguishes active protection from the 15-minute startup delay.
- Windowless task host prevents the console flashing during startup and recovery.
- Child processes are terminated with their host; exit codes reach Task Scheduler.
- MIT license included in the repository and installer, alongside dependency notices.

Protection remains unchanged:

- Default CPU thresholds: 90 C with fan stopped/unknown, 95 C with live fan RPM.
- Startup grace period: 15 minutes.
- Warning after 10 seconds continuously above the threshold.
- 20-second hibernation countdown, live CPU temperature and cancel/retry after one minute.
- Background monitor, watchdog and independent process recovery.
- Inno Setup installer; configuration preserved on upgrades.

Requirements: Windows 11 x64, paired BS3 Pro, installed PawnIO driver.
Installer unsigned. Save your work before real hibernation tests.
Validated: 64 logic tests, all four host modes without a console, child cleanup,
exit-code propagation, installed process recovery and no duplicate startup notification.
Real hibernation was verified in the previous version; this update does not change it.
