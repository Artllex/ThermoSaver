param([Parameter(Mandatory)][string]$Payload)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::SystemAware) | Out-Null
$refs=@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
$refs += [Windows.Forms.Form].Assembly.Location
$refs += [Drawing.Font].Assembly.Location
$refs += Join-Path $PSHOME 'System.Windows.Forms.Primitives.dll'
Add-Type -Path (Join-Path $Payload 'StartupCard.cs') -ReferencedAssemblies $refs
$root=Split-Path $PSScriptRoot
$menu=[ThermoSaverTrayMenu]::new()
$null=$menu.Items.Add('Wstrzymaj kontrolę')
$null=$menu.Items.Add('Wyłącz')
try {
    $menu.Show([Drawing.Point]::new(20,20))
    [Windows.Forms.Application]::DoEvents()
    foreach($dark in @($false,$true)) {
        $menu.ApplyTheme($dark)
        [Windows.Forms.Application]::DoEvents()
        if($menu.DarkTheme -ne $dark -or $menu.Items[0].Padding.Top -lt 3 -or $menu.Items[0].Padding.Bottom -lt 3) { throw 'Theme or spacing incorrect.' }
        $bitmap=[Drawing.Bitmap]::new($menu.Width,$menu.Height)
        $menu.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$menu.Width,$menu.Height))
        $name=if($dark){'dark'}else{'light'}
        $bitmap.Save((Join-Path $root ('work\tray-menu-'+$name+'.png')))
        $bitmap.Dispose()
    }
    $menu.RefreshSystemTheme()
    Write-Output ('Both themes and vertical spacing passed. Current system theme: '+$menu.DarkTheme)
} finally { $menu.Dispose() }
