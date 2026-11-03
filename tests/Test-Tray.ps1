param([Parameter(Mandatory)][string]$Payload)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$data=Join-Path $root ('work\tray-test-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $data 'requests'))
& (Join-Path $Payload 'runtime\pwsh.exe') -NoProfile -NonInteractive -STA -File (Join-Path $Payload 'Run-Notifier.ps1') -DataDirectory $data -DemoSeconds 12 -DemoClick Tray
if($LASTEXITCODE -ne 0) { throw 'Notifier preview failed.' }
$result=Get-Content (Join-Path $data 'tray-test.json') -Raw | ConvertFrom-Json
if(!$result.paused -or !$result.resumed -or !$result.visible -or $result.menu.Count -ne 2) { throw 'Tray interaction test failed.' }
if(!$result.leftClick -or !$result.rightClick -or !$result.foregroundPreserved) { throw 'Tray click/focus regression.' }
$errors=Join-Path $data 'requests\notifier-errors.log'
if((Test-Path $errors) -and (Get-Item $errors).Length -gt 0) { throw (Get-Content $errors -Raw) }
Write-Output ('Tray pause/resume/menu passed. Screenshot: '+(Join-Path $data 'tray-menu.png'))
