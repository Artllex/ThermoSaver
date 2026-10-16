param([string]$DataDirectory = (Join-Path $env:ProgramData 'ThermoSaver'), [int]$DemoSeconds = 0,
    [ValidateSet('None','Cancel','Hibernate')][string]$DemoClick = 'None', [switch]$StartupPreview)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
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
$script:startupChecked = $false
$script:startupCard = $null
function Show-StartupCard {
    $references = @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
    $references += [Windows.Forms.Form].Assembly.Location
    $references += [Drawing.Font].Assembly.Location
    $references += Join-Path $PSHOME 'System.Windows.Forms.Primitives.dll'
    Add-Type -Path (Join-Path $PSScriptRoot 'StartupCard.cs') -ReferencedAssemblies $references
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
    $script:startupCard = [ThermoSaverStartupCard]::new($text,(Join-Path $PSScriptRoot 'assets\ThermoSaver.ico'))
    $script:startupCard.Show()
    if (!$StartupPreview) { Write-GuardJson $markerPath @{logonId=$logonId;shownUtc=[DateTime]::UtcNow.ToString('o')} }
}
$started = [DateTime]::UtcNow
$script:lastHeartbeat = [DateTime]::MinValue
$script:demoClicked = $false
$timer.Add_Tick({
    try {
        $now = [DateTime]::UtcNow
        if (!$script:startupChecked) {
            $script:startupChecked = $true
            if ($DemoSeconds -eq 0 -or $StartupPreview) { Show-StartupCard }
        }
        if (($now - $script:lastHeartbeat).TotalSeconds -ge 5) {
            [IO.File]::WriteAllText((Join-Path $requests 'ui-status.json'),(@{updatedUtc=$now.ToString('o');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;visible=[GuardWindowVisibility]::IsWindowVisible($form.Handle)} | ConvertTo-Json))
            $script:lastHeartbeat = $now
        }
        if ($DemoSeconds -gt 0 -and ($now - $started).TotalSeconds -ge $DemoSeconds) { $context.ExitThread(); return }
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
    }
})
try {
    $timer.Start()
    [Windows.Forms.Application]::Run($context)
} finally {
    $timer.Stop();$timer.Dispose();$script:allowClose=$true;$form.Dispose();$context.Dispose()
    if ($null -ne $script:startupCard) { $script:startupCard.Dispose() }
    $mutex.ReleaseMutex();$mutex.Dispose()
}
