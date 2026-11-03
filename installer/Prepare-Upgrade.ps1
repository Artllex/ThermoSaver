param([Parameter(Mandatory)][string]$StatePath,[switch]$Restore)
$ErrorActionPreference='Stop'
function Restore-Tasks($Entries) {
    foreach($entry in $Entries) {
        $task=Get-ScheduledTask -TaskName $entry.name -ErrorAction SilentlyContinue
        if(!$task) { continue }
        if($entry.enabled) {
            Enable-ScheduledTask -TaskName $entry.name | Out-Null
            if($entry.running) { Start-ScheduledTask -TaskName $entry.name }
        } else { Disable-ScheduledTask -TaskName $entry.name | Out-Null }
    }
}
if($Restore) {
    if(Test-Path -LiteralPath $StatePath) { Restore-Tasks @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) }
    return
}
$entries=@()
foreach($prefix in @('ThermoSaver','Flydigi Thermal Guard')) {
    foreach($suffix in @(' - Recovery',' - Watchdog','',' - Notification')) {
        $task=Get-ScheduledTask -TaskName ($prefix+$suffix) -ErrorAction SilentlyContinue
        if($task) { $entries+=@{name=$task.TaskName;enabled=($task.State -ne 'Disabled');running=($task.State -eq 'Running')} }
    }
}
$entries | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $StatePath -Encoding UTF8
try {
    foreach($entry in $entries) {
        Disable-ScheduledTask -TaskName $entry.name | Out-Null
        if($entry.name -eq 'ThermoSaver - Notification') {
            try {
                $event=[Threading.EventWaitHandle]::OpenExisting('Local\ThermoSaverNotifierExit')
                $event.Set() | Out-Null
                $event.Dispose()
                Start-Sleep -Milliseconds 500
            } catch { }
        }
        Stop-ScheduledTask -TaskName $entry.name
    }
    Start-Sleep -Seconds 1
} catch {
    Restore-Tasks $entries
    throw
}
