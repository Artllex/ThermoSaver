$ErrorActionPreference='Stop'
foreach($name in @('ThermoSaver - Recovery','ThermoSaver - Watchdog','ThermoSaver','ThermoSaver - Notification')) {
    $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if($task) { Disable-ScheduledTask $name -ErrorAction Stop | Out-Null;Stop-ScheduledTask $name -ErrorAction Stop;Unregister-ScheduledTask $name -Confirm:$false -ErrorAction Stop }
}
