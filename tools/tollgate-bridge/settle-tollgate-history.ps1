[CmdletBinding(DefaultParameterSetName = 'Production')]
param(
    [Parameter(Mandatory = $true)][switch]$Apply,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][switch]$Synthetic,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][string]$StateRoot,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][string]$EvidenceManifestPath,
    [Parameter(ParameterSetName = 'Synthetic')]
    [ValidateSet('None','AfterAudit','AfterArchive','AfterTerminal','BeforePendingRemoval')]
    [string]$FailurePoint = 'None'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Tollgate.HistoricalRecovery.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tollgate-orchestrator/Orchestrator.Lock.ps1')
$utf8NoBom = New-Object Text.UTF8Encoding($false, $true)
$constants = Get-HistoricalRecoveryConstants

function Write-BytesAtomically([byte[]]$Bytes,[string]$Destination) {
    $directory=Split-Path -Parent $Destination; [void][IO.Directory]::CreateDirectory($directory)
    $temporary=Join-Path $directory ".$([IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).tmp"
    try {[IO.File]::WriteAllBytes($temporary,$Bytes);if(Test-Path -LiteralPath $Destination){throw "Refusing to overwrite recovery artifact: $Destination"};[IO.File]::Move($temporary,$Destination)}
    finally {if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}}
}
function Get-JsonBytes([object]$Value){return $utf8NoBom.GetBytes(($Value|ConvertTo-Json -Depth 30))}
function Read-StrictJsonBytes([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$text=$utf8NoBom.GetString($bytes);if($text.Length-gt 0-and$text[0]-eq[char]0xFEFF){$text=$text.Substring(1)};return [pscustomobject]@{Bytes=$bytes;Sha256=(Get-RecoverySha256 $bytes);Value=($text|ConvertFrom-Json)}}
function Assert-NoReparsePath([string]$Root,[string]$Path){
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\');$cursor=[IO.Path]::GetFullPath($Path)
    if(-not($cursor-eq$rootFull-or$cursor.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Recovery path escapes its state root.'}
    while($cursor.Length-ge$rootFull.Length){if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw "Recovery path contains a reparse point: $cursor"}};if($cursor-eq$rootFull){break};$cursor=Split-Path $cursor -Parent}
}
function Get-ProductionManifest{return [pscustomobject]@{pending_sha256=$constants.PendingSha256;iteration_sha256=@($constants.IterationSha256);approval=[pscustomobject]@{id=$constants.ApprovalCommentId;author=$constants.ApprovalCommentAuthor;created_at=$constants.ApprovalCommentCreatedAt;body_sha256=$constants.ApprovalCommentBodySha256};checkpoint=[pscustomobject]@{id=$constants.CheckpointCommentId;author=$constants.CheckpointCommentAuthor;created_at=$constants.CheckpointCommentCreatedAt;body_sha256=$constants.CheckpointCommentBodySha256}}}
function Assert-Manifest([object]$Manifest){
    $hashes=@([string](Get-RecoveryRequiredProperty $Manifest 'pending_sha256'))+@((Get-RecoveryRequiredProperty $Manifest 'iteration_sha256'))+@([string](Get-RecoveryRequiredProperty (Get-RecoveryRequiredProperty $Manifest 'approval') 'body_sha256'))+@([string](Get-RecoveryRequiredProperty (Get-RecoveryRequiredProperty $Manifest 'checkpoint') 'body_sha256'))
    foreach($hash in $hashes){if($hash-notmatch'^[0-9a-fA-F]{64}$'){throw 'Evidence manifest contains an invalid SHA-256.'}}
    if(@(Get-RecoveryRequiredProperty $Manifest 'iteration_sha256').Count-ne 5){throw 'Evidence manifest must contain five iteration hashes.'}
}
function Assert-ApprovalEnvelope([object]$Envelope,[object]$Manifest){
    $approval=Get-RecoveryRequiredProperty $Manifest 'approval';$body=[string](Get-RecoveryRequiredProperty $Envelope 'body')
    if([int](Get-RecoveryRequiredProperty $Envelope 'schema_version')-ne 1-or[string](Get-RecoveryRequiredProperty $Envelope 'repository')-cne$constants.Repository-or[int](Get-RecoveryRequiredProperty $Envelope 'pr_number')-ne$constants.PrNumber-or[long](Get-RecoveryRequiredProperty $Envelope 'comment_id')-ne[long]$approval.id-or[string](Get-RecoveryRequiredProperty $Envelope 'author')-cne[string]$approval.author-or[string](Get-RecoveryRequiredProperty $Envelope 'created_at')-cne[string]$approval.created_at-or[string](Get-RecoveryRequiredProperty $Envelope 'marker')-cne'[TOLLGATE_APPROVED]'-or[string](Get-RecoveryRequiredProperty $Envelope 'status')-cne'pending'-or(Get-RecoverySha256 $utf8NoBom.GetBytes($body))-cne([string]$approval.body_sha256).ToLowerInvariant()){throw 'Pending approval does not match the immutable evidence manifest.'}
}
function Get-ValidatedEvidence([string]$Root,[object]$Manifest){
    $pending=Join-Path $Root "pending\$($constants.ApprovalCommentId).json";$archive=Join-Path $Root "archive\pending\$($constants.ApprovalCommentId).json";$source=if(Test-Path -LiteralPath $pending -PathType Leaf){$pending}elseif(Test-Path -LiteralPath $archive -PathType Leaf){$archive}else{throw 'Historical pending envelope and archive are missing.'}
    $pendingData=Read-StrictJsonBytes $source;if($pendingData.Sha256-cne([string]$Manifest.pending_sha256).ToLowerInvariant()){throw 'Historical pending exact-byte SHA-256 does not match the immutable manifest.'};Assert-ApprovalEnvelope $pendingData.Value $Manifest
    $runtime=Join-Path $Root "runtime\$($constants.ApprovalCommentId)";$names=@((Get-ChildItem -LiteralPath $runtime -Directory -Filter 'iteration-*' -ErrorAction Stop).Name|Sort-Object);$expected=@(1..5|ForEach-Object{"iteration-$_"}|Sort-Object);if(@(Compare-Object $expected $names).Count-ne 0){throw 'Historical runtime must contain exactly iteration-1 through iteration-5.'}
    $iterations=@();for($i=1;$i-le 5;$i++){$data=Read-StrictJsonBytes (Join-Path $runtime "iteration-$i\codex-result.json");if($data.Sha256-cne([string]@($Manifest.iteration_sha256)[$i-1]).ToLowerInvariant()){throw "Historical iteration $i exact-byte SHA-256 does not match the immutable manifest."};$result=$data.Value;if([string](Get-RecoveryRequiredProperty $result 'status')-cne'CONTINUE'-or[bool](Get-RecoveryRequiredProperty $result 'requires_user')-or[string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'summary'))-or[string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'next_action'))){throw "Historical iteration $i is not a valid CONTINUE result."};foreach($field in 'evidence','changed_files','tests'){[void](Get-RecoveryRequiredProperty $result $field)};$iterations+=[ordered]@{iteration=$i;status='CONTINUE';sha256=$data.Sha256}}
    return [pscustomobject]@{PendingPath=$pending;PendingExists=(Test-Path -LiteralPath $pending -PathType Leaf);Pending=$pendingData;Iterations=$iterations}
}
function Assert-ExactArtifact([string]$Path,[byte[]]$ExpectedBytes,[scriptblock]$Validator){$actual=Read-StrictJsonBytes $Path;if($null-ne$Validator){&$Validator $actual.Value};if($actual.Sha256-cne(Get-RecoverySha256 $ExpectedBytes)){throw "Conflicting recovery artifact: $Path"}}

$orchestratorLock=$null;$taskLock=$null
try{
    if(-not$Apply){throw '-Apply is required for the explicit one-shot recovery operation.'}
    $repositoryRoot=[IO.Path]::GetFullPath(((&git -C $PSScriptRoot rev-parse --show-toplevel)|Out-String).Trim());if($LASTEXITCODE-ne 0){throw 'Unable to locate repository root.'}
    if($Synthetic){$state=[IO.Path]::GetFullPath($StateRoot);$allowed=[IO.Path]::GetFullPath((Join-Path $repositoryRoot 'tools/tollgate-bridge/tests/state'));if(-not($state+'\').StartsWith($allowed.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Synthetic recovery state must be beneath tools/tollgate-bridge/tests/state/.'};$manifest=(Read-StrictJsonBytes ([IO.Path]::GetFullPath($EvidenceManifestPath))).Value}
    else{$state=[IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tollgate-local'));if($FailurePoint-cne'None'){throw 'Failure injection is synthetic-only.'};&git -C $repositoryRoot cat-file -e "$($constants.BaseCommit)^{commit}" 2>$null;if($LASTEXITCODE-ne 0){throw 'Historical base commit is unavailable.'};$parent=((&git -C $repositoryRoot show -s --format=%P $constants.BaseCommit)|Out-String).Trim();if($parent-cne$constants.BaseParent){throw 'Historical base commit parent does not match the recovery contract.'};$manifest=Get-ProductionManifest}
    Assert-Manifest $manifest;Assert-NoReparsePath $state $state
    $orchestratorLock=Enter-TollgateOrchestratorLock (Join-Path $state 'orchestrator/orchestrator.lock');$taskLock=Enter-TollgateOrchestratorLock (Join-Path $state "orchestrator/task-$($constants.ApprovalCommentId).lock")
    $id=$constants.ApprovalCommentId;$completed=Join-Path $state "completed\$id.json";$reported=Join-Path $state "reported\$id.json";if(Test-Path -LiteralPath $completed){throw 'A completed record already exists; refusing historical recovery.'}
    $evidence=Get-ValidatedEvidence $state $manifest;$auditPath=Join-Path $state "audit\$id-recovery.json";$archivePath=Join-Path $state "archive\pending\$id.json";$failedPath=Join-Path $state "failed\$id.json";foreach($p in @($auditPath,$archivePath,$failedPath,$reported,$evidence.PendingPath)){Assert-NoReparsePath $state $p}
    $settledAt=if(Test-Path -LiteralPath $auditPath){[string](Get-RecoveryRequiredProperty (Read-StrictJsonBytes $auditPath).Value 'settled_at')}else{[DateTimeOffset]::UtcNow.ToString('o')}
    $recovery=[ordered]@{schema_version=1;settlement_kind='historical_recovery';termination_reason='MAX_ITERATIONS_REACHED';automatic_iterations=5;last_automatic_result='CONTINUE';requires_user=$true;manual_work_is_out_of_band=$true;tollgate_id=$constants.TollgateId;approval_comment_id=$id;checkpoint_comment_id=$constants.CheckpointCommentId;pending_sha256=$evidence.Pending.Sha256;iteration_results=$evidence.Iterations;base_commit=$constants.BaseCommit;base_parent=$constants.BaseParent;acceptance_satisfied=$false;decision_required='A new user approval is required before any additional execution or acceptance decision.'};Assert-HistoricalRecoveryMetadata $recovery
    $terminal=[ordered]@{schema_version=1;comment_id=$id;original_approval=$evidence.Pending.Value;terminal_status='STOP_REQUIRED';iterations=5;finished_at=$settledAt;final_result=[ordered]@{status='STOP_REQUIRED';summary='Historical recovery recorded that five automatic CONTINUE iterations exhausted the budget without satisfying acceptance criteria.';requires_user=$true;evidence=@('Iterations 1 through 5 were validated as CONTINUE.','MAX_ITERATIONS_REACHED is the historical termination reason.','Later manual concurrency and scheduler work is out-of-band and is not an automatic iteration.');changed_files=@();tests=@();next_action=$recovery.decision_required};recovery=$recovery};Assert-HistoricalRecoveryTerminalRecord $terminal;$terminalBytes=Get-JsonBytes $terminal;$terminalSha=Get-RecoverySha256 $terminalBytes
    $audit=[ordered]@{schema_version=1;settled_at=$settledAt;terminal_sha256=$terminalSha;approval_evidence=$manifest.approval;checkpoint_evidence=$manifest.checkpoint;recovery=$recovery;pending_source="pending/$id.json";pending_archive="archive/pending/$id.json";runtime_source="runtime/$id";terminal_target="failed/$id.json"};$auditBytes=Get-JsonBytes $audit
    if(Test-Path $auditPath){Assert-ExactArtifact $auditPath $auditBytes {param($v)Assert-HistoricalRecoveryMetadata $v.recovery}}else{Write-BytesAtomically $auditBytes $auditPath};if($FailurePoint-eq'AfterAudit'){throw 'SYNTHETIC_FAILURE_AFTER_AUDIT'}
    if(Test-Path $archivePath){if((Get-RecoverySha256 ([IO.File]::ReadAllBytes($archivePath)))-cne$evidence.Pending.Sha256){throw 'Archived pending bytes conflict with the source.'}}else{Write-BytesAtomically $evidence.Pending.Bytes $archivePath};if($FailurePoint-eq'AfterArchive'){throw 'SYNTHETIC_FAILURE_AFTER_ARCHIVE'}
    if(Test-Path $failedPath){Assert-ExactArtifact $failedPath $terminalBytes {param($v)Assert-HistoricalRecoveryTerminalRecord $v}}else{Write-BytesAtomically $terminalBytes $failedPath};if($FailurePoint-eq'AfterTerminal'){throw 'SYNTHETIC_FAILURE_AFTER_TERMINAL'}
    $fresh=Get-ValidatedEvidence $state $manifest;if($fresh.Pending.Sha256-cne$evidence.Pending.Sha256){throw 'Pending changed after validation.'};Assert-ExactArtifact $auditPath $auditBytes {param($v)Assert-HistoricalRecoveryMetadata $v.recovery};Assert-ExactArtifact $failedPath $terminalBytes {param($v)Assert-HistoricalRecoveryTerminalRecord $v};if((Get-RecoverySha256 ([IO.File]::ReadAllBytes($archivePath)))-cne$evidence.Pending.Sha256){throw 'Archive changed before pending removal.'};if($FailurePoint-eq'BeforePendingRemoval'){throw 'SYNTHETIC_FAILURE_BEFORE_PENDING_REMOVAL'}
    if(Test-Path $reported){$rv=(Read-StrictJsonBytes $reported).Value;if([long](Get-RecoveryRequiredProperty $rv 'approval_comment_id')-ne$id-or[string](Get-RecoveryRequiredProperty $rv 'terminal_status')-cne'STOP_REQUIRED'-or[string](Get-RecoveryRequiredProperty $rv 'terminal_record_sha256')-cne$terminalSha){throw 'Conflicting reported record exists.'}}
    if($fresh.PendingExists){Remove-Item -LiteralPath $fresh.PendingPath -Force}
    Write-Output '[TOLLGATE_HISTORICAL_RECOVERY_SETTLED]';Write-Output "comment_id: $id";Write-Output 'terminal_status: STOP_REQUIRED';Write-Output 'termination_reason: MAX_ITERATIONS_REACHED';Write-Output "terminal_file: $failedPath"
}catch{[Console]::Error.WriteLine("TOLLGATE_HISTORICAL_RECOVERY_ERROR: $($_.Exception.Message)");exit 1}
finally{if($null-ne$taskLock){$taskLock.Dispose()};if($null-ne$orchestratorLock){$orchestratorLock.Dispose()}}
