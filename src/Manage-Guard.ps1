param([ValidateSet('Status','Disable','Enable','NormalThresholds','Uninstall')][string]$Action='Status')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
$name='ThermoSaver'
$notifier='ThermoSaver - Notification'
$watchdog='ThermoSaver - Watchdog'
$recovery='ThermoSaver - Recovery'
if ($Action -eq 'Status') {
    $path=Join-Path $env:ProgramData 'ThermoSaver\status.json'
    $status=Read-GuardJson $path
    $updated=([DateTime]$status.updatedUtc).ToUniversalTime()
    $fresh=([DateTime]::UtcNow-$updated).TotalSeconds -le 10
    [pscustomobject]@{Status=if($fresh){$status.state}else{'inactive / stale'};Updated=$updated.ToLocalTime();CPU=$status.cpuC;Fan=$status.fan;RPM=$status.fanRpm;Threshold=$status.thresholdC;TestMode=$status.testMode;Notification=$status.notification} | Format-List
    return
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$Action
    Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait
    return
}
switch ($Action) {
    'Disable' {
        foreach($taskName in @($recovery,$watchdog)) {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        }
        Disable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $name -ErrorAction Stop
        Disable-ScheduledTask -TaskName $notifier -ErrorAction SilentlyContinue | Out-Null
        Stop-ScheduledTask -TaskName $notifier -ErrorAction SilentlyContinue
        Write-GuardJson (Join-Path $env:ProgramData 'ThermoSaver\alert.json') @{active=$false}
    }
    'Enable' {
        Enable-ScheduledTask -TaskName $notifier -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $notifier -ErrorAction Stop
        Enable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $name -ErrorAction Stop
        foreach($taskName in @($watchdog,$recovery)) {
            Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
            Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        }
    }
    'NormalThresholds' {
        Stop-ScheduledTask -TaskName $watchdog -ErrorAction Stop
        Stop-ScheduledTask -TaskName $name -ErrorAction Stop
        $configurationPath=Join-Path $env:ProgramFiles 'ThermoSaver\config.json'
        $configuration=Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json
        $configuration.testThresholdC=0
        [IO.File]::WriteAllText($configurationPath,($configuration | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        Enable-ScheduledTask -TaskName $notifier -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $notifier -ErrorAction Stop
        Enable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $name -ErrorAction Stop
        Start-ScheduledTask -TaskName $watchdog -ErrorAction Stop
    }
    'Uninstall' {
        foreach($taskName in @($recovery,$watchdog)) {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        Disable-ScheduledTask -TaskName $name | Out-Null
        Stop-ScheduledTask -TaskName $name
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Stop-ScheduledTask -TaskName $notifier -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $notifier -Confirm:$false -ErrorAction SilentlyContinue
        # Preserve the installed files and logs for inspection; remove only the autostart task.
    }
}
