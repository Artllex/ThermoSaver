param([string]$DataDirectory = (Join-Path $env:ProgramData 'ThermoSaver'), [int]$DemoSeconds = 0,
    [ValidateSet('None','Cancel','Hibernate','Tray')][string]$DemoClick = 'None', [switch]$StartupPreview)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
. (Join-Path $PSScriptRoot 'Control-Guard.ps1')
[Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'Normal'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::SystemAware) | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GuardWindowVisibility {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int command);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public static void Reveal(IntPtr window) {
        ShowWindow(window,5);
        SetWindowPos(window,new IntPtr(-1),0,0,0,0,0x43);
        SetForegroundWindow(window);
    }
}
'@
$mutexName = if ($DemoSeconds -gt 0) { 'Local\ThermoSaverPreview-' + [Guid]::NewGuid().ToString('N') } else { 'Local\ThermoSaverNotifier' }
$mutex = [Threading.Mutex]::new($false,$mutexName)
if (!$mutex.WaitOne(0)) { $mutex.Dispose(); exit 0 }
$requests = Join-Path $DataDirectory 'requests'
$alertPath = Join-Path $DataDirectory 'alert.json'
$commandPath = Join-Path $requests 'command.json'
$script:currentAlert = $null
$script:ignoredAlertId = $null
$script:allowClose = $false
$script:lastTemperatureUpdate = [DateTime]::MinValue
$script:temperatureAlertId = $null
$form = [Windows.Forms.Form]::new()
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::None
$null = $form.Handle
$scale = $form.DeviceDpi / 96.0
function Point([int]$X,[int]$Y) { [Drawing.Point]::new([int]($X*$scale),[int]($Y*$scale)) }
function Size([int]$Width,[int]$Height) { [Drawing.Size]::new([int]($Width*$scale),[int]($Height*$scale)) }
$form.Text = 'ThermoSaver'
if ($DemoSeconds -gt 0) { $form.Text = 'Podgląd ostrzeżenia' }
$form.ClientSize = Size 375 170
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.Font = [Drawing.Font]::new('Segoe UI',9)
$form.Icon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'assets\ThermoSaver.ico'))
$message = [Windows.Forms.Label]::new()
$message.Location = Point 16 12
$message.Size = Size 343 24
$message.Font = [Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
$temperature = [Windows.Forms.Label]::new()
$temperature.Location = Point 16 38
$temperature.Size = Size 343 24
$explanation = [Windows.Forms.Label]::new()
$explanation.Location = Point 16 72
$explanation.Size = Size 343 40
$explanation.Text = 'Dla bezpieczeństwa urządzenie przejdzie w stan hibernacji.'
$hibernate = [Windows.Forms.Button]::new()
$hibernate.Text = 'Hibernuj'
$hibernate.Location = Point 109 128
$hibernate.Size = Size 120 30
$cancel = [Windows.Forms.Button]::new()
$cancel.Text = 'Anuluj'
$cancel.Location = Point 239 128
$cancel.Size = Size 120 30
$form.CancelButton = $cancel
$form.Controls.AddRange(@($message,$temperature,$explanation,$hibernate,$cancel))
function Send-Response([string]$Action) {
    if ($null -eq $script:currentAlert) { return }
    $response = @{action=$Action;alertId=$script:currentAlert.alertId}
    $temporary = Join-Path $requests ('command-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary,($response | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$commandPath,$true)
    $script:ignoredAlertId = $script:currentAlert.alertId
    $form.Hide()
}
$hibernate.Add_Click({ Send-Response 'hibernate' })
$cancel.Add_Click({ Send-Response 'cancel' })
$form.Add_FormClosing({
    param($sender,$eventArgs)
    if (!$script:allowClose) { $eventArgs.Cancel=$true; Send-Response 'cancel'; $form.Hide() }
})
$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 250
$context = [Windows.Forms.ApplicationContext]::new()
$references = @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
$references += [Windows.Forms.Form].Assembly.Location
$references += [Drawing.Font].Assembly.Location
$references += Join-Path $PSHOME 'System.Windows.Forms.Primitives.dll'
Add-Type -Path (Join-Path $PSScriptRoot 'StartupCard.cs') -ReferencedAssemblies $references
$exitEventName=if($DemoSeconds -gt 0){'Local\ThermoSaverNotifierExit-'+[Guid]::NewGuid().ToString('N')}else{'Local\ThermoSaverNotifierExit'}
$exitEvent=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$exitEventName)
$tray=[Windows.Forms.NotifyIcon]::new()
$tray.Icon=$form.Icon
$tray.Text='ThermoSaver'
$trayMenu=[ThermoSaverTrayMenu]::new()
$pauseItem=[Windows.Forms.ToolStripMenuItem]::new('Wstrzymaj kontrolę')
$disableItem=[Windows.Forms.ToolStripMenuItem]::new('Wyłącz')
$null=$trayMenu.Items.Add($pauseItem)
$null=$trayMenu.Items.Add($disableItem)
$tray.Add_MouseUp({
    param($sender,$eventArgs)
    if($eventArgs.Button -in @([Windows.Forms.MouseButtons]::Left,[Windows.Forms.MouseButtons]::Right)) {
        if(!$trayMenu.Visible) { $trayMenu.Show([Windows.Forms.Cursor]::Position) }
    }
})
$tray.Visible=($DemoSeconds -eq 0 -or $DemoClick -eq 'Tray')
$pauseItem.Add_Click({
    try {
        $pause=!(Get-GuardPaused $DataDirectory)
        Set-GuardPaused $DataDirectory $pause
        if($pause) { $form.Hide() }
    } catch { [Windows.Forms.MessageBox]::Show('Nie udało się zmienić stanu kontroli.','ThermoSaver') | Out-Null }
})
$disableItem.Add_Click({
    try {
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSScriptRoot 'ThermoSaver.Host.exe'),'disable')
        $info.UseShellExecute=$true
        $info.Verb='runas'
        $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        $null=[Diagnostics.Process]::Start($info)
    } catch { if($_.Exception.NativeErrorCode -ne 1223 -and $_.Exception.InnerException.NativeErrorCode -ne 1223) { [Windows.Forms.MessageBox]::Show('Nie udało się wyłączyć ochrony.','ThermoSaver') | Out-Null } }
})
$script:startupChecked = $false
$script:startupCard = $null
function Show-StartupCard {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $logonId = [ThermoSaverStartupCard]::LogonId($identity.Token) } finally { $identity.Dispose() }
    $markerPath = Join-Path $requests 'startup-notification.json'
    if (!$StartupPreview -and (Test-Path $markerPath)) {
        $marker = Read-GuardJson $markerPath
        if ($marker.logonId -eq $logonId) { return }
    }
    $config = Read-GuardJson (Join-Path $PSScriptRoot 'config.json')
    $text = 'Ochrona temperatury włączy się 15 min po starcie systemu.'
    $statusPath = Join-Path $DataDirectory 'status.json'
    if (Test-Path $statusPath) {
        $status = Read-GuardJson $statusPath
        $fresh = ([DateTime]::UtcNow - ([DateTime]$status.updatedUtc).ToUniversalTime()).TotalSeconds -le 10
        if ($fresh -and $status.state -eq 'armed') { $text = 'Ochrona temperatury jest aktywna.' }
        elseif ($fresh -and $status.state -notin @('waiting','armed')) { $text = 'Odczyt temperatury jest chwilowo niedostępny.' }
    }
    $text += "`nProgi: $($config.stoppedThresholdC)°C / $($config.runningThresholdC)°C."
    if(Get-GuardPaused $DataDirectory) { $text="Kontrola temperatury jest wstrzymana.`nWznów ją z menu ikony w zasobniku." }
    $script:startupCard = [ThermoSaverStartupCard]::new($text,(Join-Path $PSScriptRoot 'assets\ThermoSaver.ico'))
    $script:startupCard.Show()
    if (!$StartupPreview) { Write-GuardJson $markerPath @{logonId=$logonId;shownUtc=[DateTime]::UtcNow.ToString('o')} }
}
$started = [DateTime]::UtcNow
$script:lastHeartbeat = [DateTime]::MinValue
$script:demoClicked = $false
$script:trayTestStage = 0
$script:lastTrayPaused = $null
$timer.Add_Tick({
    try {
        $now = [DateTime]::UtcNow
        if($exitEvent.WaitOne(0)) { $context.ExitThread(); return }
        if ($DemoSeconds -gt 0 -and ($now - $started).TotalSeconds -ge $DemoSeconds) { $context.ExitThread(); return }
        if($DemoSeconds -gt 0 -and $DemoClick -eq 'Tray') {
            $elapsed=($now-$started).TotalSeconds
            if($script:trayTestStage -eq 0 -and $elapsed -ge 2) {
                $pauseItem.PerformClick()
                if(!(Get-GuardPaused $DataDirectory)) { throw 'Tray pause did not take effect.' }
                $script:trayTestStage=1
            } elseif($script:trayTestStage -eq 1 -and $elapsed -ge 4) {
                $pauseItem.PerformClick()
                if(Get-GuardPaused $DataDirectory) { throw 'Tray resume did not take effect.' }
                $script:trayTestStage=2
            } elseif($script:trayTestStage -eq 2 -and $elapsed -ge 5) {
                $script:trayForeground=[GuardWindowVisibility]::GetForegroundWindow()
                $mouseUp=[Windows.Forms.NotifyIcon].GetMethod('OnMouseUp',[Reflection.BindingFlags]'Instance,NonPublic')
                $null=$mouseUp.Invoke($tray,@([Windows.Forms.MouseEventArgs]::new([Windows.Forms.MouseButtons]::Left,1,0,0,0)))
                if(!$trayMenu.Visible -or [GuardWindowVisibility]::GetForegroundWindow() -ne $script:trayForeground) { throw 'Left click did not open menu without activation.' }
                $bitmap=[Drawing.Bitmap]::new($trayMenu.Width,$trayMenu.Height)
                $trayMenu.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$trayMenu.Width,$trayMenu.Height))
                $bitmap.Save((Join-Path $DataDirectory 'tray-menu.png'))
                $bitmap.Dispose()
                $script:trayTestStage=3
            } elseif($script:trayTestStage -eq 3 -and $elapsed -ge 7) {
                $trayMenu.Close()
                $script:trayTestStage=4
            } elseif($script:trayTestStage -eq 4 -and $elapsed -ge 8) {
                $script:trayForeground=[GuardWindowVisibility]::GetForegroundWindow()
                $mouseUp=[Windows.Forms.NotifyIcon].GetMethod('OnMouseUp',[Reflection.BindingFlags]'Instance,NonPublic')
                $null=$mouseUp.Invoke($tray,@([Windows.Forms.MouseEventArgs]::new([Windows.Forms.MouseButtons]::Right,1,0,0,0)))
                if(!$trayMenu.Visible -or [GuardWindowVisibility]::GetForegroundWindow() -ne $script:trayForeground) { throw 'Right click did not open menu without activation.' }
                $script:trayTestStage=5
            } elseif($script:trayTestStage -eq 5 -and $elapsed -ge 10) {
                Write-GuardJson (Join-Path $DataDirectory 'tray-test.json') @{paused=$true;resumed=$true;visible=$tray.Visible;leftClick=$true;rightClick=$true;foregroundPreserved=$true;menu=@($pauseItem.Text,$disableItem.Text)}
                $script:trayTestStage=6
            }
        }
        $paused=Get-GuardPaused $DataDirectory
        if($script:lastTrayPaused -ne $paused -and !$trayMenu.Visible) {
            $pauseItem.Text=if($paused){'Wznów kontrolę'}else{'Wstrzymaj kontrolę'}
            $pauseItem.Checked=$paused
            $tray.Text=if($paused){'ThermoSaver - kontrola wstrzymana'}else{'ThermoSaver - kontrola temperatury'}
            $script:lastTrayPaused=$paused
        }
        if (!$script:startupChecked) {
            $script:startupChecked = $true
            if ($DemoSeconds -eq 0 -or $StartupPreview) { Show-StartupCard }
        }
        if (($now - $script:lastHeartbeat).TotalSeconds -ge 5) {
            [IO.File]::WriteAllText((Join-Path $requests 'ui-status.json'),(@{updatedUtc=$now.ToString('o');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;visible=[GuardWindowVisibility]::IsWindowVisible($form.Handle)} | ConvertTo-Json))
            $script:lastHeartbeat = $now
        }
        if ($DemoSeconds -gt 0 -and ($now - $started).TotalSeconds -ge $DemoSeconds) { $context.ExitThread(); return }
        if($paused) { $form.Hide(); return }
        if (!(Test-Path -LiteralPath $alertPath)) { $form.Hide(); return }
        $alert = Read-GuardJson $alertPath
        $deadline = [DateTime]$alert.deadlineUtc
        if ($DemoSeconds -gt 0) {
            $cycle = [Math]::Floor(($now - $started).TotalSeconds / 20) + 1
            $deadline = $started.AddSeconds(20 * $cycle)
        }
        if (!$alert.active -or $alert.alertId -eq $script:ignoredAlertId -or $deadline.ToUniversalTime() -le $now) {
            $form.Hide(); return
        }
        $script:currentAlert = $alert
        if ($DemoSeconds -eq 0) { $form.Text = if ($alert.testMode) { 'ThermoSaver - test' } else { 'ThermoSaver' } }
        $message.Text = 'Uwaga! Przekroczono temperaturę ' + $alert.thresholdC + '°C.'
        if ($script:temperatureAlertId -ne $alert.alertId -or ($now - $script:lastTemperatureUpdate).TotalSeconds -ge 5) {
            $temperature.Text = 'Temperatura CPU: ' + ([Math]::Round([double]$alert.cpuC,1)) + '°C.'
            $script:lastTemperatureUpdate = $now
            $script:temperatureAlertId = $alert.alertId
        }
        $seconds = [Math]::Max(0,[Math]::Ceiling(($deadline.ToUniversalTime() - $now).TotalSeconds))
        $hibernate.Text = 'Hibernuj (' + $seconds + 's)'
        if (!$form.Visible) {
            $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $form.StartPosition = 'Manual'
            $form.Location = [Drawing.Point]::new(
                [int]($area.Left + ($area.Width - $form.Width)/2),
                [int]($area.Top + ($area.Height - $form.Height)/2))
            $form.Show(); $form.BringToFront(); $form.Activate()
            [GuardWindowVisibility]::Reveal($form.Handle)
        }
        if ($DemoSeconds -gt 0 -and !(Test-Path -LiteralPath (Join-Path $DataDirectory 'dialog.png'))) {
            $bitmap = [Drawing.Bitmap]::new($form.Width,$form.Height)
            $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height))
            $bitmap.Save((Join-Path $DataDirectory 'dialog.png'),[Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()
        }
        if ($DemoSeconds -gt 0 -and !$script:demoClicked -and ($now - $started).TotalSeconds -ge 2) {
            $script:demoClicked = $true
            if ($DemoClick -eq 'Cancel') { $cancel.PerformClick() }
            if ($DemoClick -eq 'Hibernate') { $hibernate.PerformClick() }
        }
    } catch {
        Add-Content -LiteralPath (Join-Path $requests 'notifier-errors.log') -Value $_.Exception.Message
        if($DemoSeconds -gt 0) { $context.ExitThread() }
    }
})
try {
    $timer.Start()
    [Windows.Forms.Application]::Run($context)
} finally {
    $timer.Stop();$timer.Dispose();$script:allowClose=$true;$form.Dispose();$context.Dispose()
    $tray.Visible=$false;$tray.Dispose();$trayMenu.Dispose()
    $exitEvent.Dispose()
    if ($null -ne $script:startupCard) { $script:startupCard.Dispose() }
    $mutex.ReleaseMutex();$mutex.Dispose()
}
