# ThermoSaver 0.1.2

Tray controls and longer cancellation for Flydigi BS3 Pro.

- Tray menu: pause/resume control and turn off the application including its watchdog.
- Pausing is retained across process recovery until explicitly resumed.
- Cancel suppresses all warnings for 15 minutes, including cooling/reheating.
- Explicit shutdown removes the tray icon gracefully and preserves cancellation.
- Left and right clicks open the same menu without activating another window.
- Tray menu follows the Windows light/dark theme, with compact vertical spacing.
- Installer stops existing tasks before replacing running files and restarts protection.

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
- 20-second hibernation countdown and live CPU temperature.
- Background monitor, watchdog and independent process recovery.
- Inno Setup installer; configuration preserved on upgrades.

Requirements: Windows 11 x64, paired BS3 Pro, installed PawnIO driver.
Installer unsigned. Save your work before real hibernation tests.
Validated: 74 logic tests, all five host modes without a console, child cleanup,
exit-code propagation, installed process recovery and no duplicate startup notification.
Real hibernation was verified in the previous version; this update does not change it.
