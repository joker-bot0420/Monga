Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bridge = Split-Path $PSScriptRoot -Parent
$repo = Split-Path (Split-Path $bridge -Parent) -Parent
$script = Join-Path $bridge 'settle-tollgate-history.ps1'
$common = Join-Path $bridge 'Tollgate.HistoricalRecovery.ps1'
$executor = Join-Path $bridge 'run-tollgate-task.ps1'
$lockModule = Join-Path (Split-Path $bridge -Parent) 'tollgate-orchestrator/Orchestrator.Lock.ps1'
. $common
. $lockModule
$suite = Join-Path $PSScriptRoot "state\historical-recovery-$([Guid]::NewGuid().ToString('N'))"
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$id = 5563219043L

function Write-Json([string]$Path, [object]$Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes(($Value | ConvertTo-Json -Depth 20)))
}

function Get-FileSha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-BodySha([string]$Body) { return Get-RecoverySha256 $utf8.GetBytes($Body) }

function New-Fixture([string]$Name) {
    $root = Join-Path $suite $Name
    $envelope = [ordered]@{
        schema_version=1; repository='joker-bot0420/Monga'; pr_number=23; comment_id=$id
        author='joker-bot0420'; created_at='2026-09-07T00:05:03Z'; marker='[TOLLGATE_APPROVED]'
        body='[TOLLGATE_APPROVED] TG-AUTO-02-EXT synthetic historical fixture'; status='pending'
    }
    Write-Json (Join-Path $root "pending\$id.json") $envelope
    1..5 | ForEach-Object {
        $result = [ordered]@{
            status='CONTINUE'; summary="iteration $_"; requires_user=$false; evidence=@("e$_")
            changed_files=@(); tests=@(); next_action="next $_"
        }
        Write-Json (Join-Path $root "runtime\$id\iteration-$_\codex-result.json") $result
    }
    $pendingPath = Join-Path $root "pending\$id.json"
    $manifest = [ordered]@{
        pending_sha256 = Get-FileSha $pendingPath
        iteration_sha256 = @(1..5 | ForEach-Object { Get-FileSha (Join-Path $root "runtime\$id\iteration-$_\codex-result.json") })
        approval = [ordered]@{ id=$id; author='joker-bot0420'; created_at='2026-09-07T00:05:03Z'; body_sha256=Get-BodySha $envelope.body }
        checkpoint = [ordered]@{ id=5566069227L; author='joker-bot0420'; created_at='2026-09-07T06:31:25Z'; body_sha256=('f' * 64) }
    }
    Write-Json (Join-Path $root 'evidence-manifest.json') $manifest
    return $root
}

function Invoke-Recovery([string]$Root, [string]$FailurePoint='None') {
    $saved = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script `
            -Apply -Synthetic -StateRoot $Root -EvidenceManifestPath (Join-Path $Root 'evidence-manifest.json') -FailurePoint $FailurePoint 2>&1
        return [pscustomobject]@{ ExitCode=$LASTEXITCODE; Output=@($output) }
    } finally { $ErrorActionPreference = $saved }
}

function Assert-Fails([scriptblock]$Action, [string]$Name) {
    $value = & $Action
    if ($value.ExitCode -eq 0) { throw "Expected failure: $Name" }
}

try {
    $normal = New-Fixture 'normal'
    $r = Invoke-Recovery $normal
    if ($r.ExitCode -ne 0 -or (Test-Path (Join-Path $normal "pending\$id.json")) -or
        -not (Test-Path (Join-Path $normal "archive\pending\$id.json")) -or
        -not (Test-Path (Join-Path $normal "audit\$id-recovery.json")) -or
        -not (Test-Path (Join-Path $normal "failed\$id.json"))) { throw "Normal settlement failed: $(@($r.Output) -join ' | ')" }
    $terminal = Get-Content (Join-Path $normal "failed\$id.json") -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-HistoricalRecoveryTerminalRecord $terminal
    $r = Invoke-Recovery $normal
    if ($r.ExitCode -ne 0) { throw 'Idempotent settlement failed.' }
    $terminalHash = (Get-FileHash (Join-Path $normal "failed\$id.json") -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Json (Join-Path $normal "reported\$id.json") @{schema_version=1;approval_comment_id=$id;terminal_status='STOP_REQUIRED';terminal_record_sha256=$terminalHash}
    $r = Invoke-Recovery $normal
    if ($r.ExitCode -ne 0) { throw 'Reported settlement idempotency failed.' }

    $four = New-Fixture 'four'; Remove-Item (Join-Path $four "runtime\$id\iteration-5") -Recurse -Force
    Assert-Fails { Invoke-Recovery $four } 'four iterations'
    $six = New-Fixture 'six'; Copy-Item (Join-Path $six "runtime\$id\iteration-5") (Join-Path $six "runtime\$id\iteration-6") -Recurse
    Assert-Fails { Invoke-Recovery $six } 'six iterations'
    $terminalMixed = New-Fixture 'terminal-mixed'; $p=Join-Path $terminalMixed "runtime\$id\iteration-3\codex-result.json"; $v=Get-Content $p -Raw|ConvertFrom-Json; $v.status='STOP_REQUIRED'; Write-Json $p $v
    Assert-Fails { Invoke-Recovery $terminalMixed } 'terminal result mixed in'
    $requires = New-Fixture 'requires-user'; $p=Join-Path $requires "runtime\$id\iteration-2\codex-result.json"; $v=Get-Content $p -Raw|ConvertFrom-Json; $v.requires_user=$true; Write-Json $p $v
    Assert-Fails { Invoke-Recovery $requires } 'requires_user mismatch'
    $emptyNext = New-Fixture 'empty-next'; $p=Join-Path $emptyNext "runtime\$id\iteration-5\codex-result.json"; $v=Get-Content $p -Raw|ConvertFrom-Json; $v.next_action=''; Write-Json $p $v
    Assert-Fails { Invoke-Recovery $emptyNext } 'empty next_action'
    $completed = New-Fixture 'completed'; Write-Json (Join-Path $completed "completed\$id.json") @{comment_id=$id}
    Assert-Fails { Invoke-Recovery $completed } 'completed collision'
    $reportedOnly = New-Fixture 'reported-only'; Write-Json (Join-Path $reportedOnly "reported\$id.json") @{approval_comment_id=$id}
    Assert-Fails { Invoke-Recovery $reportedOnly } 'reported without terminal'

    foreach($point in 'AfterAudit','AfterArchive','AfterTerminal','BeforePendingRemoval') {
        $partial = New-Fixture "partial-$point"
        Assert-Fails { Invoke-Recovery $partial $point } $point
        if (-not (Test-Path (Join-Path $partial "pending\$id.json"))) { throw "Pending lost at $point" }
        $resume = Invoke-Recovery $partial
        if ($resume.ExitCode -ne 0 -or (Test-Path (Join-Path $partial "pending\$id.json"))) { throw "Recovery resume failed at $point" }
    }

    $conflict = New-Fixture 'conflict'
    Assert-Fails { Invoke-Recovery $conflict 'AfterArchive' } 'seed partial conflict'
    [IO.File]::AppendAllText((Join-Path $conflict "archive\pending\$id.json"), 'x', $utf8)
    Assert-Fails { Invoke-Recovery $conflict } 'archive hash conflict'
    if (-not (Test-Path (Join-Path $conflict "pending\$id.json"))) { throw 'Conflict removed pending.' }

    $pendingHashCase = New-Fixture 'pending-hash-conflict'
    Assert-Fails { Invoke-Recovery $pendingHashCase 'AfterAudit' } 'seed audit'
    [IO.File]::AppendAllText((Join-Path $pendingHashCase "pending\$id.json"), ' ', $utf8)
    Assert-Fails { Invoke-Recovery $pendingHashCase } 'pending hash conflict'

    $iterationHashCase = New-Fixture 'iteration-hash-conflict'
    Assert-Fails { Invoke-Recovery $iterationHashCase 'AfterAudit' } 'seed iteration audit'
    [IO.File]::AppendAllText((Join-Path $iterationHashCase "runtime\$id\iteration-4\codex-result.json"), ' ', $utf8)
    Assert-Fails { Invoke-Recovery $iterationHashCase } 'iteration hash conflict'

    $initialPendingConflict = New-Fixture 'initial-pending-conflict'
    [IO.File]::AppendAllText((Join-Path $initialPendingConflict "pending\$id.json"), ' ', $utf8)
    Assert-Fails { Invoke-Recovery $initialPendingConflict } 'initial pending manifest mismatch'
    if (Test-Path (Join-Path $initialPendingConflict "audit\$id-recovery.json")) { throw 'Manifest mismatch created lifecycle artifacts.' }

    $initialIterationConflict = New-Fixture 'initial-iteration-conflict'
    $p=Join-Path $initialIterationConflict "runtime\$id\iteration-2\codex-result.json";$v=Get-Content $p -Raw|ConvertFrom-Json;$v.summary='tampered';Write-Json $p $v
    Assert-Fails { Invoke-Recovery $initialIterationConflict } 'initial iteration manifest mismatch'
    if (Test-Path (Join-Path $initialIterationConflict "audit\$id-recovery.json")) { throw 'Iteration mismatch created lifecycle artifacts.' }

    foreach($mutation in 'approval','finished','summary','evidence','changed','tests','next') {
        $case=New-Fixture "terminal-$mutation";Assert-Fails { Invoke-Recovery $case 'AfterTerminal' } "seed terminal $mutation"
        $tp=Join-Path $case "failed\$id.json";$tv=Get-Content $tp -Raw -Encoding utf8|ConvertFrom-Json
        switch($mutation){'approval'{$tv.original_approval.body='changed'};'finished'{$tv.finished_at='bad'};'summary'{$tv.final_result.summary='changed'};'evidence'{$tv.final_result.evidence=@('changed')};'changed'{$tv.final_result.changed_files=@('x')};'tests'{$tv.final_result.tests=@('x')};'next'{$tv.final_result.next_action='changed'}}
        Write-Json $tp $tv;Assert-Fails { Invoke-Recovery $case } "terminal conflict $mutation"
        if(-not(Test-Path (Join-Path $case "pending\$id.json"))){throw "Terminal conflict removed pending: $mutation"}
    }

    $orchestratorLocked = New-Fixture 'orchestrator-lock-contention'
    $lock = Enter-TollgateOrchestratorLock (Join-Path $orchestratorLocked 'orchestrator/orchestrator.lock')
    try { Assert-Fails { Invoke-Recovery $orchestratorLocked } 'orchestrator lock contention' }
    finally { $lock.Dispose() }
    if (Test-Path (Join-Path $orchestratorLocked "audit\$id-recovery.json")) { throw 'Lock contention wrote recovery state.' }

    $taskLocked = New-Fixture 'task-lock-contention'
    $lock = Enter-TollgateOrchestratorLock (Join-Path $taskLocked "orchestrator/task-$id.lock")
    try { Assert-Fails { Invoke-Recovery $taskLocked } 'task lock contention' }
    finally { $lock.Dispose() }
    if (Test-Path (Join-Path $taskLocked "audit\$id-recovery.json")) { throw 'Task lock contention wrote recovery state.' }

    $executorLocked = New-Fixture 'executor-lock-contention'
    $lock = Enter-TollgateOrchestratorLock (Join-Path $executorLocked "orchestrator/task-$id.lock")
    try {
        $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try {$output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $executor `
            -RunPending -SyntheticStateRoot $executorLocked -TaskFile (Join-Path $executorLocked "pending\$id.json") 2>&1;$executorExit=$LASTEXITCODE}
        finally {$ErrorActionPreference=$savedPreference}
        if ($executorExit -eq 0) { throw 'Direct RunPending bypassed the task lock.' }
        if ((@($output) -join "`n") -notmatch 'being used by another process|cannot access the file') { throw 'Direct RunPending did not fail at lock acquisition.' }
    } finally { $lock.Dispose() }
    if ((Test-Path (Join-Path $executorLocked "completed\$id.json")) -or (Test-Path (Join-Path $executorLocked "failed\$id.json"))) { throw 'Lock-blocked executor wrote terminal state.' }

    $releasePath=Join-Path $suite 'process-failure/orchestrator.lock';[void][IO.Directory]::CreateDirectory((Split-Path $releasePath -Parent))
    $escaped=$releasePath.Replace("'","''");$code=". '$($lockModule.Replace("'","''"))'; `$h=Enter-TollgateOrchestratorLock '$escaped'; exit 7"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code));& powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded
    if($LASTEXITCODE-ne 7){throw 'Lock-holder failure process did not exit as expected.'};$reacquired=Enter-TollgateOrchestratorLock $releasePath;$reacquired.Dispose()

    $issue='https://api.github.com/repos/joker-bot0420/Monga/issues/23'
    Assert-ReporterPrState ([pscustomobject]@{number=23;state='open';merged_at=$null})
    $blocked=$false; try { Assert-ReporterPrState ([pscustomobject]@{number=23;state='closed';merged_at='2026-09-07T00:31:07Z'}) } catch { $blocked=$true }
    if (-not $blocked) { throw 'Normal reporter accepted a merged PR.' }
    Assert-ReporterPrState ([pscustomobject]@{number=23;state='closed';merged_at='2026-09-07T00:31:07Z'}) -HistoricalRecovery
    $blocked=$false; try { Assert-ReporterPrState ([pscustomobject]@{number=22;state='closed';merged_at='x'}) -HistoricalRecovery } catch { $blocked=$true }
    if (-not $blocked) { throw 'Recovery reporter accepted the wrong PR.' }

    $key='TG-AUTO-02-EXT/5563219043/' + ('a' * 64); $body="[STOP_REQUIRED]`nSettlement key: $key"
    $comment=[pscustomobject]@{id=1;html_url='https://example/1';issue_url=$issue;body=$body;user=[pscustomobject]@{login='joker-bot0420'}}
    $adopted=Find-HistoricalRecoveryComment @($comment) $key $body 'joker-bot0420' $issue
    if ($adopted.id -ne 1) { throw 'Existing comment adoption failed.' }
    $collision=[pscustomobject]@{id=2;issue_url=$issue;body="$body conflict";user=[pscustomobject]@{login='joker-bot0420'}}
    $blocked=$false; try { [void](Find-HistoricalRecoveryComment @($collision) $key $body 'joker-bot0420' $issue) } catch { $blocked=$true }
    if (-not $blocked) { throw 'Settlement body collision was accepted.' }
    $blocked=$false; try { [void](Find-HistoricalRecoveryComment @($comment,$comment) $key $body 'joker-bot0420' $issue) } catch { $blocked=$true }
    if (-not $blocked) { throw 'Ambiguous duplicate comments were accepted.' }
    $reportedFixture=[pscustomobject]@{approval_comment_id=$id;terminal_status='STOP_REQUIRED';settlement_key=$key;rendered_comment_sha256=('d' * 64)}
    Assert-HistoricalReportedRecord $reportedFixture $id $key ('d' * 64)
    $blocked=$false; try { Assert-HistoricalReportedRecord $reportedFixture $id $key ('e' * 64) } catch { $blocked=$true }
    if (-not $blocked) { throw 'Conflicting historical reported hash was accepted.' }

    Write-Output 'PASS: historical settlement validation, immutable manifest, full-terminal conflict refusal and idempotency.'
    Write-Output 'PASS: orchestrator/task lock contention blocks recovery and direct RunPending; process exit releases locks.'
    Write-Output 'PASS: normal open-PR behavior, merged-PR isolation, comment adoption and collision fail-closed behavior.'
    Write-Output 'PASS: no Codex child process, GitHub API, live queue or production state was used.'
} finally {
    if (Test-Path $suite) { Remove-Item $suite -Recurse -Force }
}
