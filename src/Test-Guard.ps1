$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Import-GuardTypes.ps1')
$now = [DateTime]::UtcNow
$armedAfter = $now.AddMinutes(-1)
$running = [ThermoSaver.FanReading]::new($now,1300,$false)
$stopped = [ThermoSaver.FanReading]::new($now,0,$true)
$tests = 0
function Assert([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    $script:tests++
}
function Evaluate($Temperature,$Fan,$Start=$armedAfter) {
    [ThermoSaver.Policy]::Evaluate($Temperature,$Fan,$now,$Start)
}
Assert (!(Evaluate 89.99 $stopped).Hibernate) 'Stopped below 90'
Assert (Evaluate 90.01 $stopped).Hibernate 'Stopped exactly 90'
Assert (Evaluate 94.99 $running).Threshold.Equals(95) 'Running uses 95'
Assert (!(Evaluate 94.99 $running).Hibernate) 'Running below 95'
Assert (Evaluate 95.01 $running).Hibernate 'Running exactly 95'
Assert (Evaluate 100 $running).Hibernate 'Running above threshold'
Assert (Evaluate 90.01 $null).Hibernate 'Unknown fan uses 90'
$stale = [ThermoSaver.FanReading]::new($now.AddSeconds(-6),1300,$false)
Assert (Evaluate 90.01 $stale).Hibernate 'Stale fan uses 90'
Assert (!(Evaluate 90 $stale).FanKnown) 'Stale fan not known'
$future = [ThermoSaver.FanReading]::new($now.AddSeconds(1),1300,$false)
Assert (!(Evaluate 90 $future).FanRunning) 'Future fan timestamp rejected'
$zero = [ThermoSaver.FanReading]::new($now,0,$false)
Assert (Evaluate 90.01 $zero).Hibernate 'Zero RPM uses 90'
$coasting = [ThermoSaver.FanReading]::new($now,1300,$true)
Assert (Evaluate 90.01 $coasting).Hibernate 'Switched-off fan coasting uses 90'
foreach ($invalid in @($null,0,[double]::NaN,[double]::PositiveInfinity,126)) {
    Assert (!(Evaluate $invalid $stopped).Hibernate) "Invalid CPU value $invalid"
}
Assert (!(Evaluate 100 $stopped ($now.AddSeconds(1))).Hibernate) 'Protection deferred before 15 minutes'
Assert (Evaluate 95.01 $running $now).Hibernate 'Protection active at delay boundary'
Assert (Evaluate 92 $running).Threshold.Equals(95) 'Fan turned on raises threshold'
Assert (Evaluate 92 $stopped).Hibernate 'Fan turned off lowers threshold immediately'
$bytes = [Convert]::FromHexString('015AA5EF0D280B011405140501016D0BDC0000000000000000')
$parsed = [ThermoSaver.ReportParser]::Parse($bytes,$bytes.Length,$now)
Assert ($null -ne $parsed -and $parsed.Rpm -eq 1300 -and !$parsed.Stopped) 'Real BS3 Pro heartbeat'
Assert ($null -eq [ThermoSaver.ReportParser]::Parse($bytes,12,$now)) 'Truncated report rejected'
$bytes[8] = 0
Assert ($null -eq [ThermoSaver.ReportParser]::Parse($bytes,$bytes.Length,$now)) 'Checksum mismatch rejected'
$bytes = [Convert]::FromHexString('015AA5EF0D290B010000000001016D0B000000000000000000')
$sum = 0
0..15 | ForEach-Object { $sum = ($sum + $bytes[$_]) -band 255 }
$bytes[16] = $sum
$parsed = [ThermoSaver.ReportParser]::Parse($bytes,$bytes.Length,$now)
Assert ($parsed.Stopped -and $parsed.Rpm -eq 0) 'Stopped heartbeat decoded'
$hot = Evaluate 95.01 $running
$cool = Evaluate 60 $running
$gate = [ThermoSaver.AlertGate]::new(0)
Assert ($gate.Advance($hot,$now) -eq 'alert') 'Hot CPU opens warning'
$alertId = $gate.AlertId
Assert (($gate.DeadlineUtc - $now).TotalSeconds -eq 20) '20-second countdown'
Assert ($gate.Advance($hot,$now.AddSeconds(19)) -eq 'countdown') 'No hibernation before deadline'
Assert ($gate.Advance($hot,$now.AddSeconds(20)) -eq 'hibernate') 'Deadline requests hibernation'
$gate = [ThermoSaver.AlertGate]::new(0)
$null = $gate.Advance($hot,$now)
$alertId = $gate.AlertId
Assert ($gate.Advance($hot,$now.AddSeconds(3),'cancel',$alertId) -eq 'cancelled') 'Cancel accepted'
Assert ($gate.Advance($hot,$now.AddSeconds(902)) -eq 'cooldown') 'Cancel suppresses warning for 15 minutes'
Assert ($gate.Advance($hot,$now.AddSeconds(903)) -eq 'alert') 'Warning repeats exactly 15 minutes after cancel'
Assert ($gate.AlertId -ne $alertId) 'New warning has new ID'
Assert ($gate.Advance($hot,$now.AddSeconds(904),'cancel',$alertId) -eq 'countdown') 'Old response cannot cancel new warning'
Assert ($gate.Advance($hot,$now.AddSeconds(905),'hibernate',$gate.AlertId) -eq 'hibernate') 'Hibernate button accepted immediately'
$gate = [ThermoSaver.AlertGate]::new(0)
$null = $gate.Advance($hot,$now)
Assert ($gate.Advance($cool,$now.AddSeconds(10)) -eq 'clear') 'Cooling cancels countdown'
Assert ($null -eq $gate.AlertId) 'Cooling removes warning'
Assert ($gate.Advance($hot,$now.AddSeconds(12)) -eq 'alert') 'A new temperature rise starts a new warning'
Assert ([ThermoSaver.Policy]::Evaluate(70.01,$running,$now,$armedAfter,70,70).Hibernate) 'Test threshold exactly 70'
Assert (![ThermoSaver.Policy]::Evaluate(69.99,$running,$now,$armedAfter,70,70).Hibernate) 'Test threshold below 70'
$gate = [ThermoSaver.AlertGate]::new(0)
$null=$gate.Advance($hot,$now)
$null=$gate.Advance($hot,$now.AddSeconds(1),'cancel',$gate.AlertId)
$invalidCpu=Evaluate $null $running
$null=$gate.Advance($invalidCpu,$now.AddSeconds(2))
Assert ($gate.Advance($hot,$now.AddSeconds(3)) -eq 'cooldown') 'CPU read failure does not undo cancellation'
$restored=[ThermoSaver.AlertGate]::new(0)
$restored.Restore($gate.AlertId,$gate.DeadlineUtc,$gate.RetryAfterUtc)
Assert ($restored.Advance($hot,$now.AddSeconds(5)) -eq 'cooldown') 'Restart retains cancellation period'
$null=$gate.Advance($hot,$now.AddSeconds(901))
$restored.Restore($gate.AlertId,$gate.DeadlineUtc,$gate.RetryAfterUtc)
Assert ($restored.Advance($hot,$now.AddSeconds(921)) -eq 'hibernate') 'Restart retains existing countdown deadline'
Assert ([ThermoSaver.Policy]::Evaluate(70.01,$stopped,$now,$armedAfter,70,95).Hibernate) 'New stopped-fan threshold 70'
Assert (![ThermoSaver.Policy]::Evaluate(69.99,$stopped,$now,$armedAfter,70,95).Hibernate) 'Below new stopped-fan threshold'
Assert (![ThermoSaver.Policy]::Evaluate(70.01,$running,$now,$armedAfter,70,95).Hibernate) 'Running fan retains 95 threshold'
Assert ([ThermoSaver.Policy]::Evaluate(95.01,$running,$now,$armedAfter,70,95).Hibernate) 'Running fan at 95'
$gate=[ThermoSaver.AlertGate]::new()
Assert ($gate.Advance($hot,$now) -eq 'qualifying') 'No immediate popup'
1..9 | ForEach-Object { Assert ($gate.Advance($hot,$now.AddSeconds($_)) -eq 'qualifying') "Still qualifying at $_ seconds" }
Assert ($gate.Advance($hot,$now.AddSeconds(10)) -eq 'alert') 'Popup after continuous 10 seconds'
Assert (($gate.DeadlineUtc-$now.AddSeconds(10)).TotalSeconds -eq 20) 'Countdown begins after qualification'
$gate=[ThermoSaver.AlertGate]::new()
0..5 | ForEach-Object { $null=$gate.Advance($hot,$now.AddSeconds($_)) }
$atThreshold=[ThermoSaver.Policy]::Evaluate(95,$running,$now,$armedAfter)
Assert ($gate.Advance($atThreshold,$now.AddSeconds(6)) -eq 'clear') 'Exact threshold resets continuity'
7..16 | ForEach-Object { $null=$gate.Advance($hot,$now.AddSeconds($_)) }
Assert ($null -eq $gate.AlertId) 'Brief drop requires another full 10 seconds'
Assert ($gate.Advance($hot,$now.AddSeconds(17)) -eq 'alert') 'Popup after restarted 10 seconds'
$gate=[ThermoSaver.AlertGate]::new()
$null=$gate.Advance($hot,$now)
Assert ($gate.Advance($hot,$now.AddSeconds(10)) -eq 'qualifying') 'Missing samples do not prove continuous heat'
$null=$gate.Advance($invalidCpu,$now.AddSeconds(11))
Assert ($gate.OverThresholdSinceUtc -eq [DateTime]::MinValue) 'Invalid CPU sample resets continuity'
$gate=[ThermoSaver.AlertGate]::new(0)
$null=$gate.Advance($hot,$now)
$null=$gate.Advance($hot,$now.AddSeconds(1),'cancel',$gate.AlertId)
$null=$gate.Advance($cool,$now.AddSeconds(2))
Assert ($gate.Advance($hot,$now.AddSeconds(3)) -eq 'cooldown') 'Cooling and reheating do not undo 15-minute suppression'
Assert (($gate.RetryAfterUtc-$now).TotalSeconds -eq 901) 'Cancel deadline remains intact'
$gate.Suspend()
Assert ($null -eq $gate.AlertId -and $gate.OverThresholdSinceUtc -eq [DateTime]::MinValue) 'Pause clears pending warning'
Assert ($gate.Advance($hot,$now.AddSeconds(900)) -eq 'cooldown') 'Pause and resume do not undo cancellation'
Assert ($gate.Advance($hot,$now.AddSeconds(901)) -eq 'alert') 'Warning allowed at the full 15-minute boundary'
$gate=[ThermoSaver.AlertGate]::new()
0..10 | ForEach-Object { $null=$gate.Advance($hot,$now.AddSeconds($_)) }
$gate.Suspend()
Assert ($gate.Advance($hot,$now.AddSeconds(11)) -eq 'qualifying') 'Resume starts a fresh continuous qualification'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
. (Join-Path $PSScriptRoot 'Control-Guard.ps1')
$controlTest=Join-Path ([IO.Path]::GetTempPath()) ('ThermoSaver-Control-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $controlTest 'requests'))
try {
    Assert (!(Get-GuardPaused $controlTest)) 'No pause by default'
    Set-GuardPaused $controlTest $true
    Assert (Get-GuardPaused $controlTest) 'Pause is persisted'
    Set-GuardPaused $controlTest $false
    Assert (!(Get-GuardPaused $controlTest)) 'Resume clears pause'
    Write-GuardJson (Join-Path $controlTest 'requests\control-state.json') @{paused='true'}
    Assert (!(Get-GuardPaused $controlTest)) 'Malformed pause flag cannot disable protection'
} finally {
    Remove-Item -LiteralPath (Join-Path $controlTest 'requests\control-state.json') -ErrorAction SilentlyContinue
    [IO.Directory]::Delete((Join-Path $controlTest 'requests'))
    [IO.Directory]::Delete($controlTest)
}
Write-Output "$tests tests passed. No hibernation performed."
