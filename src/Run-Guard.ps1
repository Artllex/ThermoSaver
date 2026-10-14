param([switch]$DryRun, [int]$ProbeSeconds = 0)
$ErrorActionPreference = 'Stop'
[Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'AboveNormal'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
$dataDirectory = Join-Path $env:ProgramData 'ThermoSaver'
[IO.Directory]::CreateDirectory($dataDirectory) | Out-Null
$statusName = if ($DryRun) { 'probe-status.json' } else { 'status.json' }
$logName = if ($DryRun) { 'probe.log' } else { 'guard.log' }
$logPath = Join-Path $dataDirectory $logName
$statusPath = Join-Path $dataDirectory $statusName
$alertPath = Join-Path $dataDirectory 'alert.json'
$requestPath = Join-Path $dataDirectory 'requests\command.json'
function Write-GuardLog([string]$Message) {
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 2MB) {
        Move-Item -LiteralPath $logPath -Destination ($logPath + '.old') -Force
    }
    Add-Content -LiteralPath $logPath -Value (([DateTime]::UtcNow.ToString('o')) + ' ' + $Message)
}
function Save-Status($Status) {
    Write-GuardJson $statusPath $Status
}
function Save-Alert($Alert) {
    if ($DryRun) { return }
    Write-GuardJson $alertPath $Alert
}
$mutex = [Threading.Mutex]::new($false, ('Global\ThermoSaver-' + $statusName))
$ownsMutex = $false
$computer = $null
$fanReader = $null
try {
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (!$ownsMutex) { exit 0 }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator or SYSTEM is required to read CPU temperature.'
    }
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    if ($config.stoppedThresholdC -notin @(70,90) -or $config.runningThresholdC -ne 95 -or $config.startupDelayMinutes -ne 15) {
        throw 'Unexpected protection configuration.'
    }
    # Kernel-Boot event 27 also records Fast Startup, unlike kernel uptime.
    $startEvent = Get-WinEvent -LogName System -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-Kernel-Boot'] and EventID=27] and EventData[Data[@Name='BootType']='0' or Data[@Name='BootType']='1']]" -MaxEvents 1
    $armedAfter = $startEvent.TimeCreated.ToUniversalTime().AddMinutes($config.startupDelayMinutes)
    Write-GuardLog "Starting; protection at $($armedAfter.ToString('o')); dryRun=$DryRun; identity=$($identity.Name)"
    while ([DateTime]::UtcNow -lt $armedAfter) {
        Save-Status ([ordered]@{state='waiting';armedAfterUtc=$armedAfter.ToString('o');updatedUtc=[DateTime]::UtcNow.ToString('o')})
        Start-Sleep -Seconds 1
    }
    $driver = Get-Service -Name PawnIO -ErrorAction Stop
    if ($driver.Status -ne 'Running') { Start-Service -Name PawnIO }
    $lib = Join-Path $PSScriptRoot 'lib'
    . (Join-Path $PSScriptRoot 'Import-GuardTypes.ps1')
    [Reflection.Assembly]::LoadFrom((Join-Path $lib 'LibreHardwareMonitorLib.dll')) | Out-Null
    $fanReader = [ThermoSaver.FanReader]::new($config.deviceMac)
    $computer = [LibreHardwareMonitor.Hardware.Computer]::new()
    $computer.IsCpuEnabled = $true
    $computer.Open()
    $probeStarted = [DateTime]::UtcNow
    $alertGate = [ThermoSaver.AlertGate]::new()
    if (!$DryRun -and (Test-Path -LiteralPath $alertPath)) {
        $saved = Read-GuardJson $alertPath
        if ($saved.updatedUtc -and ([DateTime]$saved.updatedUtc).ToUniversalTime() -gt $startEvent.TimeCreated.ToUniversalTime()) {
            $alertGate.Restore($saved.alertId,[DateTime]$saved.deadlineUtc,[DateTime]$saved.retryAfterUtc)
        }
    }
    $lastValidCpu = [DateTime]::UtcNow
    $lastSummary = [DateTime]::MinValue
    $previousState = ''
    while ($true) {
        $now = [DateTime]::UtcNow
        $temperature = $null
        $sensorName = $null
        $cpuError = $null
        try {
            foreach ($hardware in $computer.Hardware) {
                if ($hardware.HardwareType -ne 'Cpu') { continue }
                $hardware.Update()
                $sensor = $hardware.Sensors | Where-Object {
                    $_.SensorType -eq 'Temperature' -and $_.Name -in @('Core (Tctl/Tdie)', 'Core(Tctl/Tdie)', 'CPU Package')
                } | Select-Object -First 1
                if ($null -ne $sensor.Value) {
                    $temperature = [double]$sensor.Value
                    $sensorName = $sensor.Name
                }
            }
        } catch { $cpuError = $_.Exception.Message }
        $now = [DateTime]::UtcNow
        $fan = $fanReader.Current
        $stoppedLimit = [int]$config.stoppedThresholdC
        $runningLimit = [int]$config.runningThresholdC
        if ($config.testThresholdC -eq 70) { $stoppedLimit = 70; $runningLimit = 70 }
        $decision = [ThermoSaver.Policy]::Evaluate($temperature, $fan, $now, $armedAfter, $stoppedLimit, $runningLimit)
        $request = $null
        if (!$DryRun -and (Test-Path -LiteralPath $requestPath)) {
            try {
                if ((Get-Item -LiteralPath $requestPath).Length -le 4096) {
                    $request = Read-GuardJson $requestPath
                }
                Remove-Item -LiteralPath $requestPath -Force
            } catch { Write-GuardLog ('Invalid notification response: ' + $_.Exception.Message) }
        }
        $alertAction = $alertGate.Advance($decision,$now,$request.action,$request.alertId)
        if ($alertAction -eq 'alert') { Write-GuardLog "Warning opened: CPU=$temperature C, threshold=$($decision.Threshold) C; countdown=20 seconds" }
        if ($alertAction -eq 'cancelled') { Write-GuardLog 'Warning cancelled; retry in 60 seconds if still above threshold.' }
        Save-Alert @{
            active=($null -ne $alertGate.AlertId);alertId=$alertGate.AlertId
            deadlineUtc=$alertGate.DeadlineUtc.ToString('o');cpuC=$temperature
            thresholdC=$decision.Threshold;testMode=($config.testThresholdC -eq 70)
            retryAfterUtc=$alertGate.RetryAfterUtc.ToString('o');updatedUtc=$now.ToString('o')
        }
        $state = if ($decision.CpuValid) { 'armed' } else { 'cpu-unavailable' }
        if ($decision.CpuValid) { $lastValidCpu = $now }
        $fanState = if (!$decision.FanKnown) { 'unknown' } elseif ($decision.FanRunning) { 'running' } else { 'stopped' }
        $status = [ordered]@{
            state=$state;updatedUtc=$now.ToString('o');armedAfterUtc=$armedAfter.ToString('o')
            cpuC=$temperature;cpuSensor=$sensorName;cpuError=$cpuError;fan=$fanState
            fanRpm=if ($decision.FanKnown) { $fan.Rpm } else { $null }
            fanReportUtc=if ($null -ne $fan) { $fan.TimestampUtc.ToString('o') } else { $null }
            fanError=$fanReader.Error;thresholdC=$decision.Threshold;dryRun=[bool]$DryRun
            testMode=($config.testThresholdC -eq 70);notification=$alertAction
            retryAfterUtc=$alertGate.RetryAfterUtc.ToString('o')
            processId=$PID
            overThresholdSinceUtc=$alertGate.OverThresholdSinceUtc.ToString('o')
        }
        Save-Status $status
        $summaryState = "$state/$fanState/$($decision.Threshold)"
        if ($summaryState -ne $previousState -or ($now - $lastSummary).TotalSeconds -ge 30) {
            Write-GuardLog "state=$state CPU=$temperature C fan=$fanState RPM=$($status.fanRpm) threshold=$($decision.Threshold) C"
            $lastSummary = $now
            $previousState = $summaryState
        }
        if (($now - $lastValidCpu).TotalSeconds -gt 60) { throw 'CPU readings unavailable for 60 seconds; restarting monitor.' }
        if ($alertAction -eq 'hibernate') {
            Write-GuardLog "Hibernating: CPU=$temperature C, fan=$fanState, limit=$($decision.Threshold) C"
            if (!$DryRun) {
                $status.state = 'hibernating'
                Save-Status $status
                & "$env:SystemRoot\System32\shutdown.exe" /h
                if ($LASTEXITCODE -ne 0) { throw "Hibernation request failed: $LASTEXITCODE" }
                Write-GuardLog 'Hibernation requested successfully.'
            }
        }
        if ($ProbeSeconds -gt 0 -and ($now - $probeStarted).TotalSeconds -ge $ProbeSeconds) { break }
        Start-Sleep -Seconds 1
    }
} catch {
    Save-Alert @{active=$false}
    Write-GuardLog ('ERROR: ' + $_.Exception.Message)
    Save-Status ([ordered]@{state='error';updatedUtc=[DateTime]::UtcNow.ToString('o');error=$_.Exception.Message;dryRun=[bool]$DryRun})
    exit 1
} finally {
    if ($null -ne $fanReader) { $fanReader.Dispose() }
    if ($null -ne $computer) { $computer.Close() }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
