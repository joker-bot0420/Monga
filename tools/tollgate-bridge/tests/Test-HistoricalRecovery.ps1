Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bridge = Split-Path $PSScriptRoot -Parent
$repo = Split-Path (Split-Path $bridge -Parent) -Parent
$script = Join-Path $bridge 'settle-tollgate-history.ps1'
$common = Join-Path $bridge 'Tollgate.HistoricalRecovery.ps1'
$executor = Join-Path $bridge 'run-tollgate-task.ps1'
$reporter = Join-Path $bridge 'report-tollgate-result.ps1'
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

function Invoke-HistoricalReporterDryRun([string]$Root) {
    $saved = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $reporter `
            -HistoricalRecovery -DryRun -ResultFile (Join-Path $Root "failed\$id.json") `
            -SyntheticHistoricalStateRoot $Root -SyntheticHistoricalManifestPath (Join-Path $Root 'evidence-manifest.json') 2>&1
        return [pscustomobject]@{ ExitCode=$LASTEXITCODE; Output=@($output) }
    } finally { $ErrorActionPreference = $saved }
}

function New-FakeGhAdapter([string]$Root) {
    $adapterScript = Join-Path $Root 'fake-gh.ps1'
    $escapedRoot = $Root.Replace("'", "''")
    $source = @"
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$Arguments)
`$utf8=[Text.UTF8Encoding]::new(`$false,`$true);[Console]::OutputEncoding=`$utf8
`$root='$escapedRoot';`$comments=Join-Path `$root 'mock-comments.json';`$count=Join-Path `$root 'mock-create-count.txt'
if(`$Arguments[0]-eq'auth'){exit 0}
if(`$Arguments[0]-eq'api'){
  `$endpoint=`$Arguments[-1]
  if(`$endpoint-eq'user'){Write-Output '{"login":"joker-bot0420"}';exit 0}
  if(`$endpoint-eq'repos/joker-bot0420/Monga/pulls/23'){Write-Output '{"number":23,"state":"closed","merged_at":"2026-09-07T00:31:07Z"}';exit 0}
  if(`$endpoint-like'repos/joker-bot0420/Monga/issues/23/comments*'){if(Test-Path `$comments){Get-Content `$comments -Raw}else{Write-Output '[]'};exit 0}
  if(`$endpoint-eq'repos/joker-bot0420/Monga/issues/comments/777'){`$all=Get-Content `$comments -Raw|ConvertFrom-Json;ConvertTo-Json -InputObject @(`$all)[0] -Depth 10 -Compress;exit 0}
  exit 4
}
if(`$Arguments[0]-eq'pr'-and`$Arguments[1]-eq'comment'){
  `$bodyFile=`$Arguments[([Array]::IndexOf(`$Arguments,'--body-file')+1)];`$body=[IO.File]::ReadAllText(`$bodyFile,[Text.UTF8Encoding]::new(`$false,`$true))
  `$item=[ordered]@{id=777;html_url='https://github.com/joker-bot0420/Monga/pull/23#issuecomment-777';issue_url='https://api.github.com/repos/joker-bot0420/Monga/issues/23';body=`$body;user=@{login='joker-bot0420'}}
  `$json=ConvertTo-Json -InputObject @(`$item) -Depth 10;[IO.File]::WriteAllText(`$comments,`$json,[Text.UTF8Encoding]::new(`$false,`$true));[IO.File]::AppendAllText(`$count,"1`n")
  Write-Output `$item.html_url;exit 0
}
exit 5
"@
    [IO.File]::WriteAllText($adapterScript, $source, $utf8)
    return $adapterScript
}

function Start-HistoricalReporterPublish([string]$Root,[string]$Adapter) {
    $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$reporter,'-HistoricalRecovery','-Publish','-ResultFile',(Join-Path $Root "failed\$id.json"),'-SyntheticHistoricalStateRoot',$Root,'-SyntheticHistoricalManifestPath',(Join-Path $Root 'evidence-manifest.json'),'-SyntheticGhExecutable',$Adapter)
    $token=[Guid]::NewGuid().ToString('N');$stdout=Join-Path $Root "$token.stdout";$stderr=Join-Path $Root "$token.stderr"
    $process=Start-Process powershell.exe -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return [pscustomobject]@{Process=$process;Stdout=$stdout;Stderr=$stderr}
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
    $normalManifest = Get-Content (Join-Path $normal 'evidence-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-HistoricalRecoveryTerminalRecordAgainstManifest $terminal $normalManifest
    Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest $terminal (Join-Path $normal "failed\$id.json") $normal $normalManifest
    $reporterResult = Invoke-HistoricalReporterDryRun $normal
    if ($reporterResult.ExitCode -ne 0 -or (@($reporterResult.Output) -join "`n") -notmatch '\[TOLLGATE_REPORT_READY\]') {
        throw "Historical reporter main-path DryRun failed: $(@($reporterResult.Output) -join ' | ')"
    }
    $production = Get-ProductionHistoricalEvidenceManifest
    if ([string]$production.pending_sha256 -cne 'c1a38025d51c0df53e41fb69dfbea7c259812053d7e03af06f496f267b827fd5' -or
        [string]$production.approval.body_sha256 -cne '9cf38618469c281ab7b9238f054f3b8ace33d829537f5473e983acdd75ec9ad7' -or
        [string]$production.checkpoint.body_sha256 -cne 'be8f67d852e1d7c314fe41e6b6120176873feac51dfbdd09da9cdbc01e413d18') { throw 'Production immutable manifest constants changed.' }
    $bypass=$false;try{Assert-HistoricalRecoveryTerminalRecord $terminal}catch{$bypass=$true};if(-not$bypass){throw 'Synthetic terminal bypassed production immutable evidence.'}
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
    foreach($artifact in @('audit', 'archive', 'failed')) {
        if (Test-Path (Join-Path $reportedOnly $artifact)) { throw "Reported-only refusal created $artifact state." }
    }

    $missingAudit=New-Fixture 'missing-audit';$mr=Invoke-Recovery $missingAudit;if($mr.ExitCode-ne 0){throw 'Unable to seed missing-audit fixture.'};Remove-Item (Join-Path $missingAudit "audit\$id-recovery.json") -Force
    $mt=Get-Content (Join-Path $missingAudit "failed\$id.json") -Raw -Encoding utf8|ConvertFrom-Json;$mm=Get-Content (Join-Path $missingAudit 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $blocked=$false;try{Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest $mt (Join-Path $missingAudit "failed\$id.json") $missingAudit $mm}catch{$blocked=$true};if(-not$blocked){throw 'Historical terminal without audit was accepted.'}
    $checkpointMismatch=New-Fixture 'checkpoint-mismatch';$cr=Invoke-Recovery $checkpointMismatch;if($cr.ExitCode-ne 0){throw 'Unable to seed checkpoint fixture.'};$ap=Join-Path $checkpointMismatch "audit\$id-recovery.json";$av=Get-Content $ap -Raw -Encoding utf8|ConvertFrom-Json;$av.checkpoint_evidence.body_sha256=('e'*64);Write-Json $ap $av
    $ct=Get-Content (Join-Path $checkpointMismatch "failed\$id.json") -Raw -Encoding utf8|ConvertFrom-Json;$cm=Get-Content (Join-Path $checkpointMismatch 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $blocked=$false;try{Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest $ct (Join-Path $checkpointMismatch "failed\$id.json") $checkpointMismatch $cm}catch{$blocked=$true};if(-not$blocked){throw 'Checkpoint evidence mismatch was accepted.'}

    $missingRuntime=New-Fixture 'missing-runtime';$rr=Invoke-Recovery $missingRuntime;if($rr.ExitCode-ne 0){throw 'Unable to seed missing-runtime fixture.'};Remove-Item (Join-Path $missingRuntime "runtime\$id") -Recurse -Force
    $rt=Get-Content (Join-Path $missingRuntime "failed\$id.json") -Raw -Encoding utf8|ConvertFrom-Json;$rm=Get-Content (Join-Path $missingRuntime 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $blocked=$false;try{Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest $rt (Join-Path $missingRuntime "failed\$id.json") $missingRuntime $rm}catch{$blocked=$true};if(-not$blocked){throw 'Historical terminal without runtime evidence was accepted.'}

    foreach($runtimeCase in @(
        @{Name='missing-iteration';Mutate={param($root)Remove-Item (Join-Path $root "runtime\$id\iteration-3") -Recurse -Force}},
        @{Name='extra-iteration';Mutate={param($root)[void][IO.Directory]::CreateDirectory((Join-Path $root "runtime\$id\iteration-6"))}},
        @{Name='changed-runtime';Mutate={param($root)[IO.File]::AppendAllText((Join-Path $root "runtime\$id\iteration-2\codex-result.json"),'x',$utf8)}}
    )){
        $root=New-Fixture $runtimeCase.Name;$seed=Invoke-Recovery $root;if($seed.ExitCode-ne 0){throw "Unable to seed $($runtimeCase.Name) fixture."};& $runtimeCase.Mutate $root
        $terminal=Get-Content (Join-Path $root "failed\$id.json") -Raw -Encoding utf8|ConvertFrom-Json;$manifest=Get-Content (Join-Path $root 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
        $blocked=$false;try{Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest $terminal (Join-Path $root "failed\$id.json") $root $manifest}catch{$blocked=$true};if(-not$blocked){throw "Runtime evidence case was accepted: $($runtimeCase.Name)"}
        $reporterResult = Invoke-HistoricalReporterDryRun $root
        if ($reporterResult.ExitCode -eq 0) { throw "Reporter main path accepted invalid runtime evidence: $($runtimeCase.Name)" }
    }

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

    function Invoke-DirectExecutor([string]$Root,[string]$Hook='') {
        $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$executor,'-RunPending','-SyntheticStateRoot',$Root,'-TaskFile',(Join-Path $Root "pending\$id.json"))
        if(-not[string]::IsNullOrWhiteSpace($Hook)){$arguments+=@('-SyntheticBeforeTaskLockHook',$Hook)}
        $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$output=& powershell.exe @arguments 2>&1;return [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=@($output)}}finally{$ErrorActionPreference=$saved}
    }
    foreach($mutation in @('body','replace','comment')) {
        $case=New-Fixture "executor-toctou-$mutation"
        $marker=Join-Path $case 'codex-called'
        $fake=Join-Path $case 'codex.cmd';[IO.File]::WriteAllText($fake,"@echo called>`"$marker`"`r`n@exit /b 9`r`n",[Text.Encoding]::ASCII)
        $hook=Join-Path $case 'mutate.ps1'
        $hookText = switch($mutation){
            'body' { 'param($TaskFile); $v=Get-Content -LiteralPath $TaskFile -Raw|ConvertFrom-Json;$v.body="changed";$v|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $TaskFile -Encoding utf8' }
            'replace' { 'param($TaskFile); $bytes=[IO.File]::ReadAllBytes($TaskFile);Start-Sleep -Milliseconds 20;[IO.File]::Delete($TaskFile);[IO.File]::WriteAllBytes($TaskFile,$bytes)' }
            'comment' { 'param($TaskFile); $v=Get-Content -LiteralPath $TaskFile -Raw|ConvertFrom-Json;$v.comment_id=5563219044;$v|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $TaskFile -Encoding utf8' }
        }
        [IO.File]::WriteAllText($hook,$hookText,$utf8)
        $oldPath=$env:PATH;try{$env:PATH="$case;$oldPath";$result=Invoke-DirectExecutor $case $hook}finally{$env:PATH=$oldPath}
        if($result.ExitCode-eq 0){throw "Executor accepted pending $mutation mutation."}
        if(Test-Path $marker){throw "Codex child ran after pending $mutation mutation."}
    }
    $identical=New-Fixture 'executor-identical-bytes';Write-Json (Join-Path $identical "failed\$id.json") @{comment_id=$id}
    $noChangeHook=Join-Path $identical 'noop.ps1';[IO.File]::WriteAllText($noChangeHook,'param($TaskFile); [void][IO.File]::ReadAllBytes($TaskFile)',$utf8)
    $identicalResult=Invoke-DirectExecutor $identical $noChangeHook
    if($identicalResult.ExitCode-ne 0-or(@($identicalResult.Output)-join"`n")-notmatch'TOLLGATE_TERMINAL_RECORD_ALREADY_EXISTS'){throw 'Identical pending bytes did not pass post-lock validation.'}

    $outside=Join-Path $suite 'junction-outside';[void][IO.Directory]::CreateDirectory($outside)
    $junctionFixture=Join-Path $suite 'junction-fixture';[void][IO.Directory]::CreateDirectory($junctionFixture)
    $junction=Join-Path $junctionFixture 'orchestrator';$mklink=& cmd.exe /c "mklink /J `"$junction`" `"$outside`"" 2>&1
    if($LASTEXITCODE-eq 0){
        $junctionTask=New-Fixture 'junction-fixture'
        $jr=Invoke-DirectExecutor $junctionTask
        if($jr.ExitCode-eq 0){throw 'Executor accepted a reparse-point lock parent.'}
    }else{Write-Output "SKIP: junction escape fixture unavailable: $(@($mklink)-join' ')"}

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

    $publishRoot=New-Fixture 'reporter-main-publish';$seed=Invoke-Recovery $publishRoot;if($seed.ExitCode-ne 0){throw 'Unable to seed reporter publish fixture.'};$adapter=New-FakeGhAdapter $publishRoot
    $r1=Start-HistoricalReporterPublish $publishRoot $adapter;$r2=Start-HistoricalReporterPublish $publishRoot $adapter
    $process1=$r1.Process;$process2=$r2.Process;$process1.WaitForExit();$process2.WaitForExit()
    $stderr1=Get-Content $r1.Stderr -Raw;$stderr2=Get-Content $r2.Stderr -Raw;$stdout1=Get-Content $r1.Stdout -Raw;$stdout2=Get-Content $r2.Stdout -Raw
    if(-not[string]::IsNullOrWhiteSpace($stderr1)-or-not[string]::IsNullOrWhiteSpace($stderr2)-or
       ($stdout1+$stdout2)-notmatch'TOLLGATE_REPORT_READY'-or($stdout1+$stdout2)-notmatch'TOLLGATE_RESULT_ALREADY_REPORTED'){
        throw "Concurrent historical reporter failed: $stderr1 | $stderr2 | $stdout1 | $stdout2"
    };$process1.Dispose();$process2.Dispose()
    $creates=@(Get-Content (Join-Path $publishRoot 'mock-create-count.txt'));if($creates.Count-ne 1){throw "Concurrent historical reporters created $($creates.Count) comments."}
    $reportedPath=Join-Path $publishRoot "reported\$id.json";if(-not(Test-Path $reportedPath -PathType Leaf)){throw 'Historical reporter main path did not atomically create reported state.'}

    Write-Output 'PASS: historical settlement validation, immutable manifest, full-terminal conflict refusal and idempotency.'
    Write-Output 'PASS: orchestrator/task lock contention blocks recovery and direct RunPending; process exit releases locks.'
    Write-Output 'PASS: direct RunPending exact-byte TOCTOU checks and lock-path reparse checks fail closed before Codex.'
    Write-Output 'PASS: normal open-PR behavior, merged-PR isolation, comment adoption and collision fail-closed behavior.'
    Write-Output 'PASS: historical reporter main-path DryRun and concurrent mocked Publish use runtime validation and exactly one create.'
    Write-Output 'PASS: no Codex child process, GitHub API, live queue or production state was used.'
} finally {
    if (Test-Path $suite) { Remove-Item $suite -Recurse -Force }
}
