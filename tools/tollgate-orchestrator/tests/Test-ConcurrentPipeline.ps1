[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.ToString() -notlike '5.1.*') { throw 'Requires Windows PowerShell 5.1.' }
$source = Split-Path $PSScriptRoot -Parent
$entry = Join-Path $source 'run-tollgate-orchestrator.ps1'
. (Join-Path $source 'Orchestrator.Lock.ps1')
$suite = Join-Path $PSScriptRoot ('state/concurrent-' + [guid]::NewGuid().ToString('N'))
# Validate ancestors before creating any fixture files, including the worker.
$cursor = $suite
while ($cursor) {
    if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse fixture ancestor.' }
    $cursor = [IO.Path]::GetDirectoryName($cursor)
}
[void][IO.Directory]::CreateDirectory($suite)
$worker = Join-Path $suite 'worker.ps1'
[IO.File]::WriteAllText($worker, @'
param([string]$Entry,[string]$StateRoot,[string]$Role,[string]$Mode)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Record-Call([string]$Stage) {
    [IO.File]::AppendAllText((Join-Path $StateRoot ($Role + '.calls')), "$Stage`n")
}
$prepare = { param($root,$file) Record-Call 'prepare'; 0 }
$executor = { param($root,$file)
    Record-Call 'executor'
    if ($file -cne (Join-Path $root 'pending/synthetic-task.json')) { throw 'Wrong pending task.' }
    # Independent invocation evidence: a duplicate cannot overwrite the winner's log.
    [IO.File]::WriteAllText((Join-Path $root ($Role + '.executor')), "$PID|$file")
    if ($Role -eq 'winner') {
        [IO.File]::WriteAllText((Join-Path $root 'executor-entered'), [string]$PID)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath (Join-Path $root 'release-executor'))) {
            if ($timer.Elapsed.TotalSeconds -gt 30) { throw 'Executor handshake timeout.' }
            Start-Sleep -Milliseconds 25
        }
    }
    if ($Mode -eq 'executor-throw') { throw 'Injected executor failure.' }
    if ($Mode -eq 'executor-nonzero') { return [int]9 }
    0
}
$reporter = { param($root,$file)
    Record-Call 'reporter'
    if ($file -cne (Join-Path $root 'completed/prior-task.json')) { throw 'Wrong terminal task.' }
    if ($Mode -eq 'reporter-throw') { throw 'Injected reporter failure.' }
    0
}
try {
    $result = & $Entry -Synthetic -StateRoot $StateRoot -PrepareStage $prepare -ExecutorStage $executor -ReporterStage $reporter
    @{ Success = $true; Pid = $PID; Result = $result } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StateRoot ($Role + '.outcome.json'))
    exit 0
} catch {
    $exception = $_.Exception
    $codes = @()
    while ($exception) { $codes += ($exception.HResult -band 65535); $exception = $exception.InnerException }
    @{ Success = $false; Pid = $PID; Message = $_.Exception.Message; Codes = $codes } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StateRoot ($Role + '.outcome.json'))
    exit 1
}
'@)
function Literal([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
function Start-Worker([string]$Root,[string]$Role,[string]$Mode) {
    $code = '& ' + (Literal $worker) + ' -Entry ' + (Literal $entry) + ' -StateRoot ' + (Literal $Root) + ' -Role ' + (Literal $Role) + ' -Mode ' + (Literal $Mode)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { $process.Dispose(); throw 'Worker did not start.' }
    return $process
}
function Snapshot([string]$Root) {
    foreach ($directory in @('pending','completed','failed','reported')) {
        Get-ChildItem -LiteralPath (Join-Path $Root $directory) -File -Recurse | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($Root.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
}
foreach ($mode in @('success','executor-nonzero','executor-throw','reporter-throw')) {
    $root = Join-Path $suite $mode
    foreach ($directory in @('pending','completed','failed','reported','orchestrator')) { [void][IO.Directory]::CreateDirectory((Join-Path $root $directory)) }
    [IO.File]::WriteAllText((Join-Path $root 'pending/synthetic-task.json'), '{"id":"synthetic-task","status":"pending"}')
    [IO.File]::WriteAllText((Join-Path $root 'completed/prior-task.json'), '{"id":"prior-task","status":"completed"}')
    [IO.File]::WriteAllText((Join-Path $root 'reported/prior-task.json'), '{"id":"prior-task","fixture":true}')
    $before = @(Snapshot $root)
    $lockPath = Join-Path $root 'orchestrator/orchestrator.lock'
    [IO.File]::WriteAllText($lockPath, 'persistent fixture lock identity')
    $lockHash = (Get-FileHash -LiteralPath $lockPath).Hash
    $winner = $null
    $loser = $null
    try {
        $winner = Start-Worker $root 'winner' $mode
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath (Join-Path $root 'executor-entered'))) {
            if ($winner.HasExited -or $timer.Elapsed.TotalSeconds -gt 15) { throw "Winner did not enter executor: $mode" }
            Start-Sleep -Milliseconds 25
        }
        $loser = Start-Worker $root 'loser' $mode
        if (-not $loser.WaitForExit(15000)) { throw "Contender did not fail promptly: $mode" }
        if ($winner.HasExited) { throw 'Winner stopped before contention was verified.' }
        $outcome = Get-Content -LiteralPath (Join-Path $root 'loser.outcome.json') -Raw | ConvertFrom-Json
        if ($loser.ExitCode -ne 1 -or $outcome.Success -or (32 -notin $outcome.Codes -and 33 -notin $outcome.Codes)) { throw 'Loser did not fail with a sharing/lock violation.' }
        if ($outcome.Pid -eq $winner.Id -or $outcome.Pid -ne $loser.Id) { throw 'Workers are not distinct processes.' }
        if (Test-Path -LiteralPath (Join-Path $root 'loser.calls')) { throw 'Loser entered a pipeline stage.' }
        if (@(Get-ChildItem -LiteralPath $root -Filter '*.executor').Count -ne 1) { throw 'Duplicate executor invocation during contention.' }
        # Also prove the handle is still held after the losing process exits.
        $denied = $false
        try { $probe = Enter-TollgateOrchestratorLock $lockPath; $probe.Dispose() } catch [IO.IOException] { $denied = $true }
        if (-not $denied) { throw 'Pipeline released its lock inside executor.' }
        if (Compare-Object $before @(Snapshot $root)) { throw 'State changed during contention.' }
        [IO.File]::WriteAllText((Join-Path $root 'release-executor'), 'release')
        if (-not $winner.WaitForExit(15000)) { throw 'Winner did not finish after release.' }
        $outcome = Get-Content -LiteralPath (Join-Path $root 'winner.outcome.json') -Raw | ConvertFrom-Json
        $expectedExit = if ($mode -eq 'success') { 0 } else { 1 }
        if ($winner.ExitCode -ne $expectedExit -or $outcome.Success -ne ($mode -eq 'success')) { throw "Wrong winner outcome: $mode" }
        if ($mode -eq 'success') {
            if (-not $outcome.Result.PendingInvoked -or $outcome.Result.TerminalInvocations -ne 1) { throw 'Incorrect pipeline result.' }
        } else {
            $expectedMessage = switch ($mode) {
                'executor-nonzero' { 'Stage failed: expected exactly one integer exit code 0.' }
                'executor-throw' { 'Injected executor failure.' }
                'reporter-throw' { 'Injected reporter failure.' }
            }
            if ($outcome.Message -cne $expectedMessage) { throw "Unexpected failure: $($outcome.Message)" }
        }
        $expectedCalls = if ($mode -like 'executor-*') { 'prepare,executor' } else { 'prepare,executor,reporter' }
        if (((Get-Content -LiteralPath (Join-Path $root 'winner.calls')) -join ',') -cne $expectedCalls) { throw 'Wrong pipeline stage order/count.' }
        if (@(Get-ChildItem -LiteralPath $root -Filter '*.executor').Count -ne 1 -or (Test-Path -LiteralPath (Join-Path $root 'loser.calls'))) { throw 'Duplicate processing after release.' }
        if (Compare-Object $before @(Snapshot $root)) { throw 'False lifecycle mutation after pipeline completion.' }
        $probe = Enter-TollgateOrchestratorLock $lockPath
        $probe.Dispose()
        if ((Get-FileHash -LiteralPath $lockPath).Hash -cne $lockHash) { throw 'Persistent lock file changed.' }
        Write-Output "PASS: $mode; one executor; loser excluded before prepare; state preserved; lock released."
    } finally {
        # Only these test-owned child processes are eligible for timeout cleanup.
        foreach ($process in @($loser,$winner)) {
            if ($null -ne $process) {
                if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
                $process.Dispose()
            }
        }
    }
}
Write-Output "Fixtures retained: $suite"
# This proves overlapping invocations are excluded, not permanent exactly-once
# semantics: a later run may retry a task that an executor leaves pending.
