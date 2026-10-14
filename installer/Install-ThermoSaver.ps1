param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'IO-Guard.ps1')
$install=$PSScriptRoot
$data=Join-Path $env:ProgramData 'ThermoSaver'
$legacy=Join-Path $env:ProgramFiles 'Flydigi Thermal Guard'
$configuration=Join-Path $install 'config.json'
if($ValidateOnly) {
    . (Join-Path $install 'Import-GuardTypes.ps1')
    [Reflection.Assembly]::LoadFrom((Join-Path $install 'lib\LibreHardwareMonitorLib.dll')) | Out-Null
    $icon=[Drawing.Icon]::new((Join-Path $install 'assets\ThermoSaver.ico'))
    $icon.Dispose()
    foreach($file in Get-ChildItem (Join-Path $install 'tasks') -Filter '*.xml') { [xml]$definition=Get-Content $file.FullName -Raw }
    Write-Output 'Payload libraries, task XML and icon validated without registration or activation.'
    return
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator required.' }
Get-Service PawnIO -ErrorAction Stop | Out-Null
$legacyConfiguration=Join-Path $legacy 'config.json'
if((Test-Path -LiteralPath $legacyConfiguration) -and !(Test-Path -LiteralPath (Join-Path $data 'installation.json'))) {
    Copy-Item -LiteralPath $legacyConfiguration -Destination $configuration -Force
}
$config=Read-GuardJson $configuration
if(!$config.deviceMac) {
    $device=Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -eq 'FlyDigi BS3PRO' } | Select-Object -First 1
    if(!$device -or $device.InstanceId -notmatch 'DEV_([0-9A-F]{12})') { throw 'Pair Flydigi BS3 Pro with Windows Bluetooth first.' }
    $config.deviceMac=$Matches[1].ToLowerInvariant();Write-GuardJson $configuration $config
}
$desktopUser=(Get-CimInstance Win32_ComputerSystem).UserName
$userSid=if($desktopUser) { [Security.Principal.NTAccount]::new($desktopUser).Translate([Security.Principal.SecurityIdentifier]).Value } else { $identity.User.Value }
[IO.Directory]::CreateDirectory($data) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $data 'requests')) | Out-Null
foreach($directory in @($install,$data,(Join-Path $data 'requests'))) {
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    foreach($entry in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-32-545','ReadAndExecute'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($entry[0]),$entry[1],'ContainerInherit,ObjectInherit','None','Allow'))
    }
    if($directory.EndsWith('\requests')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($userSid),'Modify','ContainerInherit,ObjectInherit','None','Allow'))
    }
    Set-Acl -LiteralPath $directory -AclObject $acl
}
$names=@('ThermoSaver - Recovery','ThermoSaver - Watchdog','ThermoSaver','ThermoSaver - Notification')
$oldNames=@('Flydigi Thermal Guard - Recovery','Flydigi Thermal Guard - Watchdog','Flydigi Thermal Guard','Flydigi Thermal Guard - Notification')
foreach($name in @($names+$oldNames)) {
    $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if($task) { Disable-ScheduledTask $name -ErrorAction Stop | Out-Null;Stop-ScheduledTask $name -ErrorAction Stop }
}
try {
    foreach($entry in @(@('Main','ThermoSaver'),@('Notification','ThermoSaver - Notification'),@('Watchdog','ThermoSaver - Watchdog'),@('Recovery','ThermoSaver - Recovery'))) {
        [xml]$xml=Get-Content -LiteralPath (Join-Path $install ('tasks\'+$entry[0]+'.xml')) -Raw
        $xml.Task.Actions.Exec.Command=Join-Path $install 'runtime\pwsh.exe'
        $xml.Task.Actions.Exec.WorkingDirectory=$install
        $xml.Task.Actions.Exec.Arguments=$xml.Task.Actions.Exec.Arguments.Replace('C:\Program Files\ThermoSaver',$install)
        $settings=$xml.DocumentElement.SelectSingleNode("*[local-name()='Settings']")
        $enabled=$settings.SelectSingleNode("*[local-name()='Enabled']")
        if(!$enabled) {$enabled=$xml.CreateElement('Enabled',$xml.DocumentElement.NamespaceURI);$settings.AppendChild($enabled) | Out-Null};$enabled.InnerText='true'
        if($entry[0] -eq 'Notification') {
            $xml.Task.Principals.Principal.UserId=$userSid;$xml.Task.Triggers.LogonTrigger.UserId=$userSid
            Register-ScheduledTask -TaskName $entry[1] -Xml $xml.OuterXml -Force -ErrorAction Stop | Out-Null
        } else {
            if($entry[0] -eq 'Recovery') { $xml.Task.Triggers.TimeTrigger.StartBoundary=[DateTime]::Now.AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss') }
            Register-ScheduledTask -TaskName $entry[1] -Xml $xml.OuterXml -User SYSTEM -Force -ErrorAction Stop | Out-Null
        }
    }
    foreach($name in @('ThermoSaver - Notification','ThermoSaver','ThermoSaver - Watchdog')) { Start-ScheduledTask $name -ErrorAction Stop }
    foreach($name in $oldNames) { Unregister-ScheduledTask $name -Confirm:$false -ErrorAction SilentlyContinue }
    Write-GuardJson (Join-Path $data 'installation.json') @{installedUtc=[DateTime]::UtcNow.ToString('o');version='0.1.0';name='ThermoSaver';userSid=$userSid;configuration=$config}
} catch {
    foreach($name in $names) { Disable-ScheduledTask $name -ErrorAction SilentlyContinue | Out-Null;Stop-ScheduledTask $name -ErrorAction SilentlyContinue }
    foreach($name in $oldNames) { Enable-ScheduledTask $name -ErrorAction SilentlyContinue | Out-Null;Start-ScheduledTask $name -ErrorAction SilentlyContinue }
    throw
}
