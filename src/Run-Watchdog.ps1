param([switch]$Once)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
$data=Join-Path $env:ProgramData 'ThermoSaver'
$heartbeat=Join-Path $data 'watchdog-status.json'
$log=Join-Path $data 'watchdog.log'
$mutex=$null
$owns=$false
function Restart-GuardTask([string]$Name,[string]$Reason) {
    Add-Content -LiteralPath $log -Value ([DateTime]::UtcNow.ToString('o')+' '+$Name+': '+$Reason)
    Stop-ScheduledTask -TaskName $Name -ErrorAction Stop
    Start-ScheduledTask -TaskName $Name -ErrorAction Stop
}
function Ensure-GuardTask([string]$Name,[string]$StatusPath,[int]$StaleSeconds) {
    $task=Get-ScheduledTask -TaskName $Name -ErrorAction Stop
    if ($task.State -eq 'Disabled') { return }
    if ($task.State -ne 'Running') { Start-ScheduledTask -TaskName $Name -ErrorAction Stop; return }
    # Give a newly started process time to initialize its sensors or desktop window.
    $info=Get-ScheduledTaskInfo -TaskName $Name -ErrorAction Stop
    if (([DateTime]::Now-$info.LastRunTime).TotalSeconds -lt 20) { return }
    if (!(Test-Path -LiteralPath $StatusPath)) { Restart-GuardTask $Name 'missing heartbeat'; return }
    $status=Read-GuardJson $StatusPath
    if (([DateTime]::UtcNow-([DateTime]$status.updatedUtc).ToUniversalTime()).TotalSeconds -gt $StaleSeconds -or $status.state -eq 'error') {
        Restart-GuardTask $Name 'stale heartbeat or error'
    }
}
try {
    if ($Once) {
        $boot=Get-WinEvent -LogName System -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-Kernel-Boot'] and EventID=27] and EventData[Data[@Name='BootType']='0' or Data[@Name='BootType']='1']]" -MaxEvents 1
        if ([DateTime]::UtcNow -lt $boot.TimeCreated.ToUniversalTime().AddMinutes(15)) { exit 0 }
        Ensure-GuardTask 'ThermoSaver - Watchdog' $heartbeat 30
        exit 0
    }
    $mutex=[Threading.Mutex]::new($false,'Global\ThermoSaverWatchdog')
    try { $owns=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owns=$true }
    if (!$owns) { exit 0 }
    while ($true) {
        try {
            Ensure-GuardTask 'ThermoSaver' (Join-Path $data 'status.json') 15
            $uiTask=Get-ScheduledTask -TaskName 'ThermoSaver - Notification' -ErrorAction Stop
            # Interactive tasks should only run while their user has a logged-in session.
            $userId=$uiTask.Principal.UserId
            if ($userId -like 'S-1-*') {
                $sid=[Security.Principal.SecurityIdentifier]::new($userId)
                $userName=$sid.Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
            } else { $userName=$userId.Split('\')[-1] }
            $session=Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty UserName
            if ($session -and $session.Split('\')[-1] -eq $userName) {
                Ensure-GuardTask $uiTask.TaskName (Join-Path $data 'requests\ui-status.json') 15
            }
            Write-GuardJson $heartbeat @{updatedUtc=[DateTime]::UtcNow.ToString('o');state='healthy';processId=$PID}
        } catch {
            Add-Content -LiteralPath $log -Value ([DateTime]::UtcNow.ToString('o')+' ERROR: '+$_.Exception.Message)
            Write-GuardJson $heartbeat @{updatedUtc=[DateTime]::UtcNow.ToString('o');state='error';error=$_.Exception.Message;processId=$PID}
        }
        Start-Sleep -Seconds 5
    }
} finally {
    if ($owns) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
