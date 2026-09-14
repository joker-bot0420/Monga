Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$entry = Join-Path (Split-Path $PSScriptRoot -Parent) 'run-tollgate-orchestrator.ps1'
$suite = Join-Path $PSScriptRoot ('state/routing-' + [guid]::NewGuid().ToString('N'))
$ok = { param($root, $file) 0 }
$never = { param($root, $file) throw 'Unexpected stage invocation.' }
function New-Case([string]$Name) {
    $path = Join-Path $suite $Name
    foreach ($dir in @('pending','completed','failed')) { [void][IO.Directory]::CreateDirectory((Join-Path $path $dir)) }
    return $path
}
function Assert-Fails([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected failure.' }
}
$root = New-Case 'no-work'
$r = & $entry -Synthetic -StateRoot $root -PrepareStage $ok -ExecutorStage $never -ReporterStage $never
if ($r.PendingInvoked -or $r.TerminalInvocations -ne 0) { throw 'No-work routing failed.' }
$root = New-Case 'pending'
[IO.File]::WriteAllText((Join-Path $root 'pending/1.json'), '{}')
$execute = { param($root, $file)
    if ($file -ne (Join-Path $root 'pending/1.json')) { throw 'Incorrect task path.' }
    [IO.File]::WriteAllText((Join-Path $root 'executor-called'), 'yes')
    0
}
$r = & $entry -Synthetic -StateRoot $root -PrepareStage $ok -ExecutorStage $execute -ReporterStage $never
if (-not $r.PendingInvoked -or -not (Test-Path (Join-Path $root 'executor-called'))) { throw 'Pending routing failed.' }
$root = New-Case 'terminal'
foreach ($dir in @('completed','failed')) { [IO.File]::WriteAllText((Join-Path $root "$dir/1.json"), '{}') }
$report = { param($root, $file) [IO.File]::AppendAllText((Join-Path $root 'report-calls'), "$file`n"); 0 }
$r = & $entry -Synthetic -StateRoot $root -PrepareStage $ok -ExecutorStage $never -ReporterStage $report
if ($r.TerminalInvocations -ne 2 -or @(Get-Content (Join-Path $root 'report-calls')).Count -ne 2) { throw 'Terminal routing failed.' }
$root = New-Case 'error'
$task = Join-Path $root 'pending/1.json'
[IO.File]::WriteAllText($task, '{}')
$before = (Get-FileHash $task).Hash
Assert-Fails { & $entry -Synthetic -StateRoot $root -PrepareStage { 7 } -ExecutorStage $never -ReporterStage $never }
Assert-Fails { & $entry -Synthetic -StateRoot $root -PrepareStage $ok -ExecutorStage { 9 } -ReporterStage $never }
if ((Get-FileHash $task).Hash -ne $before) { throw 'Pending changed on failure.' }
if (@(Get-ChildItem (Join-Path $root 'completed')).Count -or @(Get-ChildItem (Join-Path $root 'failed')).Count) { throw 'False terminal state.' }
# Success after failures also proves finally released the lock.
& $entry -Synthetic -StateRoot $root -PrepareStage $ok -ExecutorStage $ok -ReporterStage $never | Out-Null
$root = New-Case 'report-error'
[IO.File]::WriteAllText((Join-Path $root 'completed/1.json'), '{}')
Assert-Fails { & $entry -Synthetic -StateRoot $root -PrepareStage $ok -ExecutorStage $never -ReporterStage { 3 } }
if (Test-Path (Join-Path $root 'reported')) { throw 'False reported state.' }

# The descendant lock parent must be checked before the lock module can follow
# a junction outside the isolated state root.
$junctionRoot = New-Case 'lock-parent-junction'
$outside = Join-Path $suite 'junction-outside'
[void][IO.Directory]::CreateDirectory($outside)
$junction = Join-Path $junctionRoot 'orchestrator'
$mklink = & cmd.exe /c "mklink /J `"$junction`" `"$outside`"" 2>&1
if ($LASTEXITCODE -eq 0) {
    Assert-Fails { & $entry -Synthetic -StateRoot $junctionRoot -PrepareStage $ok -ExecutorStage $never -ReporterStage $never }
    if (Test-Path -LiteralPath (Join-Path $outside 'orchestrator.lock')) { throw 'Rejected reparse lock parent created an external lock file.' }
} else {
    Write-Output "SKIP: junction lock-parent fixture unavailable: $(@($mklink) -join ' ')"
}

# A junction above StateRoot must also be rejected, including when the lexical
# tests/state prefix remains valid.
foreach ($depth in @(1,2)) {
    $container = Join-Path $suite "ancestor-$depth"
    [void][IO.Directory]::CreateDirectory($container)
    $external = Join-Path $suite "ancestor-external-$depth"
    [void][IO.Directory]::CreateDirectory((Join-Path $external 'state-root'))
    $linkParent = if ($depth -eq 1) { $container } else { Join-Path $container 'level-one' }
    [void][IO.Directory]::CreateDirectory($linkParent)
    $link = Join-Path $linkParent 'link'
    $mklink = & cmd.exe /c "mklink /J `"$link`" `"$external`"" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $escapedRoot = Join-Path $link 'state-root'
        Assert-Fails { & $entry -Synthetic -StateRoot $escapedRoot -PrepareStage $ok -ExecutorStage $never -ReporterStage $never }
        if (Test-Path -LiteralPath (Join-Path $external 'state-root/orchestrator/orchestrator.lock')) {
            throw "Rejected ancestor junction at depth $depth created an external lock."
        }
    } else { Write-Output "SKIP: ancestor junction depth $depth unavailable: $(@($mklink) -join ' ')" }
}
Write-Output "PASS: no-work, pending, completed/failed routing, prepare/executor/reporter errors, lock release. Fixtures: $suite"
