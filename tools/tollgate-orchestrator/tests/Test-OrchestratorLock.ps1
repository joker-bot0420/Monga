[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Orchestrator.Lock.ps1')

$fixtureRoot = Join-Path $PSScriptRoot ('state/lock-' + [Guid]::NewGuid().ToString('N'))
$lockPath = Join-Path $fixtureRoot 'orchestrator.lock'
$handle = Enter-TollgateOrchestratorLock -LockPath $lockPath
try {
    $denied = $false
    try {
        $duplicate = Enter-TollgateOrchestratorLock -LockPath $lockPath
        $duplicate.Dispose()
    } catch [System.IO.IOException] { $denied = $true }
    if (-not $denied) { throw 'A duplicate lock acquisition succeeded.' }

    # A separate Windows PowerShell process must also be excluded.
    $escapedPath = $lockPath.Replace("'", "''")
    $childCode = "try { `$h = [IO.File]::Open('$escapedPath', 'OpenOrCreate', 'ReadWrite', 'None'); `$h.Dispose(); exit 9 } catch [IO.IOException] { exit 0 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
    & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -NonInteractive -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw 'Cross-process exclusion failed.' }
} finally { $handle.Dispose() }

$reacquired = Enter-TollgateOrchestratorLock -LockPath $lockPath
$reacquired.Dispose()
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw 'Lock file was removed.' }
Write-Output 'PASS: duplicate handle excluded; concurrent process excluded; release permits reacquisition.'
Write-Output "Fixture retained: $fixtureRoot"
