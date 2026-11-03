function Get-GuardPaused([string]$DataDirectory) {
    $path=Join-Path $DataDirectory 'requests\control-state.json'
    if(!(Test-Path -LiteralPath $path)) { return $false }
    try {
        if((Get-Item -LiteralPath $path).Length -gt 4096) { return $false }
        $state=Read-GuardJson $path
        return ($state.paused -is [bool] -and $state.paused)
    } catch { return $false }
}
function Set-GuardPaused([string]$DataDirectory,[bool]$Paused) {
    Write-GuardJson (Join-Path $DataDirectory 'requests\control-state.json') @{paused=$Paused;updatedUtc=[DateTime]::UtcNow.ToString('o')}
}
