$guardLib = Join-Path $PSScriptRoot 'lib'
[Reflection.Assembly]::LoadFrom((Join-Path $guardLib 'HidSharp.dll')) | Out-Null
$guardReferences = @(Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
$guardReferences += Join-Path $guardLib 'HidSharp.dll'
Add-Type -Path (Join-Path $PSScriptRoot 'Guard.cs') -ReferencedAssemblies $guardReferences
