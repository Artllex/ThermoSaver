$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$test=Join-Path $root ('work\host-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $test 'runtime') -Force | Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe /platform:x64 ("/out:"+(Join-Path $test 'ThermoSaver.Host.exe')) (Join-Path $root 'src\Host.cs')
if($LASTEXITCODE -ne 0) { throw 'Host compilation failed.' }
& $csc /nologo /target:exe /platform:x64 ("/out:"+(Join-Path $test 'runtime\pwsh.exe')) (Join-Path $PSScriptRoot 'HostProbe.cs')
if($LASTEXITCODE -ne 0) { throw 'Probe compilation failed.' }
foreach($mode in @('guard','notifier','watchdog','recovery')) {
    $result=Join-Path $test 'probe.txt'
    if(Test-Path $result) { Remove-Item -LiteralPath $result }
    $hostProcess=Start-Process -FilePath (Join-Path $test 'ThermoSaver.Host.exe') -ArgumentList $mode -PassThru
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    while(!(Test-Path $result) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if(!(Test-Path $result)) { throw "Child did not start for $mode." }
    $probe=(Get-Content $result -Raw).Split('|')
    if($probe[1] -ne '0') { throw "Console allocated for $mode." }
    if($mode -eq 'recovery' -and !$probe[2].EndsWith(' -Once')) { throw 'Recovery lost -Once.' }
    if($mode -eq 'notifier') {
        $hostProcess.Kill();$hostProcess.WaitForExit()
        Start-Sleep -Milliseconds 500
        if(Get-Process -Id ([int]$probe[0]) -ErrorAction SilentlyContinue) { throw 'Terminating host left its child alive.' }
    } else {
        $hostProcess.WaitForExit()
        if($hostProcess.ExitCode -ne 7) { throw "Exit code not propagated for $mode." }
    }
}
Write-Output 'Host tests passed: four modes without a console; exit codes preserved; child cleanup verified.'
