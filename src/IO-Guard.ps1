function Read-GuardJson([string]$Path) {
    $stream = [IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = [IO.StreamReader]::new($stream)
    try { $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
}
function Write-GuardJson([string]$Path,$Value) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    for ($attempt=0;$attempt -lt 20;$attempt++) {
        try { [IO.File]::Move($temporary,$Path,$true); return }
        catch [IO.IOException] { if ($attempt -eq 19) { throw }; Start-Sleep -Milliseconds 25 }
        catch [UnauthorizedAccessException] { if ($attempt -eq 19) { throw }; Start-Sleep -Milliseconds 25 }
    }
}
