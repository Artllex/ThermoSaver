@echo off
"C:\Program Files\ThermoSaver\runtime\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-Guard.ps1" -Action Status
pause
