param(
    [Parameter(Mandatory)][string]$DependencyDirectory,
    [Parameter(Mandatory)][string]$PowerShellDirectory,
    [string]$Compiler="${env:LOCALAPPDATA}\Programs\Inno Setup 7\ISCC.exe"
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$payload=Join-Path $root 'build\payload'
[IO.Directory]::CreateDirectory($payload) | Out-Null
Copy-Item -Path (Join-Path $root 'src\*') -Destination $payload -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'assets') -Destination $payload -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'licenses') -Destination $payload -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'THIRD-PARTY-NOTICES.md') -Destination $payload -Force
[IO.Directory]::CreateDirectory((Join-Path $payload 'lib')) | Out-Null
Copy-Item -Path (Join-Path $DependencyDirectory '*.dll') -Destination (Join-Path $payload 'lib') -Force
[IO.Directory]::CreateDirectory((Join-Path $payload 'runtime')) | Out-Null
Copy-Item -Path (Join-Path $PowerShellDirectory '*') -Destination (Join-Path $payload 'runtime') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-ThermoSaver.ps1'),(Join-Path $PSScriptRoot 'Uninstall-ThermoSaver.ps1') -Destination $payload -Force
& (Join-Path $PowerShellDirectory 'pwsh.exe') -NoProfile -File (Join-Path $payload 'Test-Guard.ps1')
if($LASTEXITCODE -ne 0) { throw 'Logic tests failed.' }
& $Compiler (Join-Path $PSScriptRoot 'ThermoSaver.iss')
if($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
