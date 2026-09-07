Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.ToString() -notlike '5.1.*') { throw 'Requires Windows PowerShell 5.1.' }
$source = Split-Path $PSScriptRoot -Parent
$suite = Join-Path $PSScriptRoot ('state/integration-' + [guid]::NewGuid().ToString('N'))
$fixtureTools = Join-Path $suite 'tools/tollgate-orchestrator'
$fixtureBridge = Join-Path $suite 'tools/tollgate-bridge'
$state = Join-Path $suite '.tollgate-local'
foreach ($dir in @($fixtureTools,$fixtureBridge,(Join-Path $state 'pending'),(Join-Path $state 'completed'),(Join-Path $state 'failed'))) {
    [void][IO.Directory]::CreateDirectory($dir)
}
# Copy the actual entry and helpers unchanged; only bridge scripts are stand-ins.
foreach ($name in @('run-tollgate-orchestrator.ps1','Orchestrator.Lock.ps1','Orchestrator.BridgeStages.ps1','Orchestrator.ExecutorEnvironment.ps1')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $fixtureTools
    if ((Get-FileHash (Join-Path $source $name)).Hash -ne (Get-FileHash (Join-Path $fixtureTools $name)).Hash) { throw 'Fixture source mismatch.' }
}
$common = @'
$ErrorActionPreference = 'Stop'
$state = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.tollgate-local'
'@
[IO.File]::WriteAllText((Join-Path $fixtureBridge 'prepare-tollgate-task.ps1'), $common + @'

[IO.File]::AppendAllText((Join-Path $state 'calls'), "prepare`n")
if (Test-Path (Join-Path $state 'prepare-error')) { exit 12 }
'@)
[IO.File]::WriteAllText((Join-Path $fixtureBridge 'run-tollgate-task.ps1'), @'
param([switch]$RunPending,[string]$TaskFile,[int]$TimeoutSeconds)
'@ + "`n" + $common + @'

if (-not $RunPending -or $TimeoutSeconds -ne 90 -or -not (Test-Path -LiteralPath $TaskFile)) { exit 13 }
if ($env:GH_TOKEN -or $env:GITHUB_TOKEN) { exit 14 }
[IO.File]::AppendAllText((Join-Path $state 'calls'), "executor`n")
if (Test-Path (Join-Path $state 'executor-error')) { exit 15 }
[IO.File]::WriteAllText((Join-Path $state 'completed/result.json'), '{}')
'@)
[IO.File]::WriteAllText((Join-Path $fixtureBridge 'report-tollgate-result.ps1'), @'
param([switch]$Publish,[string]$ResultFile)
'@ + "`n" + $common + @'

if (-not $Publish -or -not (Test-Path -LiteralPath $ResultFile)) { exit 16 }
[IO.File]::AppendAllText((Join-Path $state 'calls'), "reporter`n")
if (Test-Path (Join-Path $state 'reporter-error')) { exit 17 }
'@)
$entry = Join-Path $fixtureTools 'run-tollgate-orchestrator.ps1'
$exe = Join-Path $suite 'codex.exe'
[IO.File]::WriteAllText($exe, 'Inert fixture: never executed.')
function Assert-Fails([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected stage failure.' }
}
# Missing CLI is harmless when no pending work exists.
$r = & $entry
if ($r.PendingInvoked -or $r.TerminalInvocations) { throw 'No-work failed.' }
$task = Join-Path $state 'pending/task.json'
[IO.File]::WriteAllText($task, '{}')
$hash = (Get-FileHash $task).Hash
Assert-Fails { & $entry }
if ((Get-FileHash $task).Hash -ne $hash) { throw 'Discovery failure altered pending.' }
$r = & $entry -CodexExecutable $exe -TimeoutSeconds 90
if (-not $r.PendingInvoked -or $r.TerminalInvocations -ne 1) { throw 'Production routing failed.' }
$calls = @(Get-Content (Join-Path $state 'calls'))
if (($calls -join ',') -ne 'prepare,prepare,prepare,executor,reporter') { throw 'Stage order failed.' }
[IO.File]::WriteAllText((Join-Path $state 'reporter-error'), 'fixture')
Assert-Fails { & $entry -CodexExecutable $exe -TimeoutSeconds 90 }
[IO.File]::WriteAllText((Join-Path $state 'executor-error'), 'fixture')
Assert-Fails { & $entry -CodexExecutable $exe -TimeoutSeconds 90 }
[IO.File]::WriteAllText((Join-Path $state 'prepare-error'), 'fixture')
Assert-Fails { & $entry -CodexExecutable $exe -TimeoutSeconds 90 }
if ((Get-FileHash $task).Hash -ne $hash -or (Test-Path (Join-Path $state 'reported'))) { throw 'False lifecycle mutation.' }
. (Join-Path $source 'Orchestrator.Lock.ps1')
$lock = Enter-TollgateOrchestratorLock (Join-Path $state 'orchestrator/orchestrator.lock')
$lock.Dispose()
Write-Output "PASS: unchanged entry/helper fixture, no-work, discovery failure, production stage order and arguments, all stage failures, pending preservation and lock release. Fixture: $suite"
