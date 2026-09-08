[CmdletBinding(DefaultParameterSetName = 'Production')]
param(
    [Parameter(Mandatory = $true)][switch]$Apply,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][switch]$Synthetic,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][string]$StateRoot,
    [Parameter(ParameterSetName = 'Synthetic')]
    [ValidateSet('None','AfterAudit','AfterArchive','AfterTerminal','BeforePendingRemoval')]
    [string]$FailurePoint = 'None'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Tollgate.HistoricalRecovery.ps1')

$utf8NoBom = New-Object Text.UTF8Encoding($false, $true)
$constants = Get-HistoricalRecoveryConstants

function Write-BytesAtomically {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes, [Parameter(Mandatory = $true)][string]$Destination)
    $directory = Split-Path -Parent $Destination
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary = Join-Path $directory ".$([IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        if (Test-Path -LiteralPath $Destination) { throw "Refusing to overwrite recovery artifact: $Destination" }
        [IO.File]::Move($temporary, $Destination)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Write-JsonAtomically {
    param([Parameter(Mandatory = $true)][object]$Value, [Parameter(Mandatory = $true)][string]$Destination)
    $json = $Value | ConvertTo-Json -Depth 30
    Write-BytesAtomically -Bytes $utf8NoBom.GetBytes($json) -Destination $Destination
    return [IO.File]::ReadAllText($Destination, $utf8NoBom) | ConvertFrom-Json
}

function Read-StrictJsonBytes {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = $utf8NoBom.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return [pscustomobject]@{ Bytes = $bytes; Sha256 = Get-RecoverySha256 $bytes; Value = ($text | ConvertFrom-Json) }
}

function Assert-ApprovalEnvelope {
    param([Parameter(Mandatory = $true)][object]$Envelope)
    if ([int](Get-RecoveryRequiredProperty $Envelope 'schema_version') -ne 1 -or
        [string](Get-RecoveryRequiredProperty $Envelope 'repository') -cne $constants.Repository -or
        [int](Get-RecoveryRequiredProperty $Envelope 'pr_number') -ne $constants.PrNumber -or
        [long](Get-RecoveryRequiredProperty $Envelope 'comment_id') -ne $constants.ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $Envelope 'author') -cne 'joker-bot0420' -or
        [string](Get-RecoveryRequiredProperty $Envelope 'marker') -cne '[TOLLGATE_APPROVED]' -or
        [string](Get-RecoveryRequiredProperty $Envelope 'status') -cne 'pending' -or
        -not ([string](Get-RecoveryRequiredProperty $Envelope 'body')).Contains($constants.TollgateId)) {
        throw 'Pending approval does not match TG-AUTO-02-EXT historical recovery.'
    }
}

function Get-ValidatedEvidence {
    param([Parameter(Mandatory = $true)][string]$Root)
    $pending = Join-Path $Root "pending\$($constants.ApprovalCommentId).json"
    $archive = Join-Path $Root "archive\pending\$($constants.ApprovalCommentId).json"
    $source = if (Test-Path -LiteralPath $pending -PathType Leaf) { $pending } elseif (Test-Path -LiteralPath $archive -PathType Leaf) { $archive } else { throw 'Historical pending envelope and archive are missing.' }
    $pendingData = Read-StrictJsonBytes $source
    Assert-ApprovalEnvelope $pendingData.Value
    $runtimeDirectory = Join-Path $Root "runtime\$($constants.ApprovalCommentId)"
    $iterationDirectories = @(Get-ChildItem -LiteralPath $runtimeDirectory -Directory -Filter 'iteration-*' -ErrorAction Stop)
    $expectedNames = @(1..$constants.Iterations | ForEach-Object { "iteration-$_" })
    $actualNames = @($iterationDirectories.Name | Sort-Object)
    if (@(Compare-Object -ReferenceObject ($expectedNames | Sort-Object) -DifferenceObject $actualNames).Count -ne 0) {
        throw "Historical runtime must contain exactly iteration-1 through iteration-5. Found: $($actualNames -join ', ')"
    }
    $iterations = @()
    for ($i = 1; $i -le $constants.Iterations; $i++) {
        $path = Join-Path $Root "runtime\$($constants.ApprovalCommentId)\iteration-$i\codex-result.json"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Historical iteration $i result is missing." }
        $data = Read-StrictJsonBytes $path
        $result = $data.Value
        if ([string](Get-RecoveryRequiredProperty $result 'status') -cne 'CONTINUE' -or
            [bool](Get-RecoveryRequiredProperty $result 'requires_user') -or
            [string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'summary')) -or
            [string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'next_action'))) {
            throw "Historical iteration $i is not a valid CONTINUE result."
        }
        foreach ($field in @('evidence','changed_files','tests')) { [void](Get-RecoveryRequiredProperty $result $field) }
        $iterations += [ordered]@{ iteration = $i; status = 'CONTINUE'; sha256 = $data.Sha256 }
    }
    return [pscustomobject]@{ PendingPath = $pending; PendingExists = (Test-Path -LiteralPath $pending -PathType Leaf); Pending = $pendingData; Iterations = $iterations }
}

function Assert-ExistingJsonEquals {
    param([string]$Path, [object]$Expected, [scriptblock]$Validator)
    $actual = Read-StrictJsonBytes $Path
    if ($null -ne $Validator) { & $Validator $actual.Value }
    $expectedBytes = $utf8NoBom.GetBytes(($Expected | ConvertTo-Json -Depth 30))
    if ($actual.Sha256 -cne (Get-RecoverySha256 $expectedBytes)) { throw "Conflicting recovery artifact: $Path" }
}

try {
    if (-not $Apply) { throw '-Apply is required for the explicit one-shot recovery operation.' }
    $repositoryRoot = [IO.Path]::GetFullPath(((& git -C $PSScriptRoot rev-parse --show-toplevel) | Out-String).Trim())
    if ($LASTEXITCODE -ne 0) { throw 'Unable to locate repository root.' }
    if ($Synthetic) {
        $state = [IO.Path]::GetFullPath($StateRoot)
        $allowed = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'tools/tollgate-bridge/tests/state')) + [IO.Path]::DirectorySeparatorChar
        if (-not ($state + [IO.Path]::DirectorySeparatorChar).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Synthetic recovery state must be beneath tools/tollgate-bridge/tests/state/.'
        }
    } else {
        $state = Join-Path $repositoryRoot '.tollgate-local'
        if ($FailurePoint -cne 'None') { throw 'Failure injection is synthetic-only.' }
    }
    $state = [IO.Path]::GetFullPath($state)
    $id = $constants.ApprovalCommentId
    $completed = Join-Path $state "completed\$id.json"
    $existingFailed = Join-Path $state "failed\$id.json"
    $reported = Join-Path $state "reported\$id.json"
    if (Test-Path -LiteralPath $completed) { throw 'A completed record already exists; refusing historical recovery.' }
    if ((Test-Path -LiteralPath $reported) -and -not (Test-Path -LiteralPath $existingFailed)) {
        throw 'A reported record exists without a historical failed terminal; refusing recovery.'
    }

    $evidence = Get-ValidatedEvidence $state
    $recovery = [ordered]@{
        schema_version = 1; settlement_kind = 'historical_recovery'; termination_reason = 'MAX_ITERATIONS_REACHED'
        automatic_iterations = 5; last_automatic_result = 'CONTINUE'; requires_user = $true
        manual_work_is_out_of_band = $true; tollgate_id = $constants.TollgateId
        approval_comment_id = $constants.ApprovalCommentId; checkpoint_comment_id = $constants.CheckpointCommentId
        pending_sha256 = $evidence.Pending.Sha256; iteration_results = $evidence.Iterations
        base_commit = $constants.BaseCommit; base_parent = $constants.BaseParent; acceptance_satisfied = $false
        decision_required = 'A new user approval is required before any additional execution or acceptance decision.'
    }
    Assert-HistoricalRecoveryMetadata $recovery
    $audit = [ordered]@{
        schema_version = 1; recovery = $recovery
        pending_source = "pending/$id.json"; pending_archive = "archive/pending/$id.json"
        runtime_source = "runtime/$id"; terminal_target = "failed/$id.json"
    }
    $terminal = [ordered]@{
        schema_version = 1; comment_id = $id; original_approval = $evidence.Pending.Value
        terminal_status = 'STOP_REQUIRED'; iterations = 5; finished_at = [DateTimeOffset]::UtcNow.ToString('o')
        final_result = [ordered]@{
            status = 'STOP_REQUIRED'
            summary = 'Historical recovery recorded that five automatic CONTINUE iterations exhausted the budget without satisfying acceptance criteria.'
            requires_user = $true
            evidence = @('Iterations 1 through 5 were validated as CONTINUE.', 'MAX_ITERATIONS_REACHED is the historical termination reason.', 'Later manual concurrency and scheduler work is out-of-band and is not an automatic iteration.')
            changed_files = @(); tests = @(); next_action = $recovery.decision_required
        }
        recovery = $recovery
    }
    Assert-HistoricalRecoveryTerminalRecord $terminal

    $auditPath = Join-Path $state "audit\$id-recovery.json"
    $archivePath = Join-Path $state "archive\pending\$id.json"
    $failedPath = Join-Path $state "failed\$id.json"

    if (Test-Path -LiteralPath $auditPath) { Assert-ExistingJsonEquals $auditPath $audit { param($v) Assert-HistoricalRecoveryMetadata $v.recovery } }
    else { [void](Write-JsonAtomically $audit $auditPath) }
    if ($FailurePoint -eq 'AfterAudit') { throw 'SYNTHETIC_FAILURE_AFTER_AUDIT' }

    if (Test-Path -LiteralPath $archivePath) {
        if ((Get-RecoverySha256 ([IO.File]::ReadAllBytes($archivePath))) -cne $evidence.Pending.Sha256) { throw 'Archived pending bytes conflict with the source.' }
    } else { Write-BytesAtomically $evidence.Pending.Bytes $archivePath }
    if ((Get-RecoverySha256 ([IO.File]::ReadAllBytes($archivePath))) -cne $evidence.Pending.Sha256) { throw 'Archived pending hash verification failed.' }
    if ($FailurePoint -eq 'AfterArchive') { throw 'SYNTHETIC_FAILURE_AFTER_ARCHIVE' }

    if (Test-Path -LiteralPath $failedPath) {
        $existingTerminal = Read-StrictJsonBytes $failedPath
        Assert-HistoricalRecoveryTerminalRecord $existingTerminal.Value
        if (($existingTerminal.Value.recovery | ConvertTo-Json -Depth 20 -Compress) -cne ($recovery | ConvertTo-Json -Depth 20 -Compress)) {
            throw 'Existing historical terminal recovery metadata conflicts with validated evidence.'
        }
    } else { [void](Write-JsonAtomically $terminal $failedPath) }
    $terminalRoundTrip = Read-StrictJsonBytes $failedPath
    Assert-HistoricalRecoveryTerminalRecord $terminalRoundTrip.Value
    if ($FailurePoint -eq 'AfterTerminal') { throw 'SYNTHETIC_FAILURE_AFTER_TERMINAL' }

    $auditRoundTrip = Read-StrictJsonBytes $auditPath
    Assert-HistoricalRecoveryMetadata $auditRoundTrip.Value.recovery
    if ([string]$auditRoundTrip.Value.recovery.pending_sha256 -cne $evidence.Pending.Sha256) { throw 'Audit/pending hash mismatch.' }
    if ($FailurePoint -eq 'BeforePendingRemoval') { throw 'SYNTHETIC_FAILURE_BEFORE_PENDING_REMOVAL' }

    if (Test-Path -LiteralPath $reported) {
        $reportedValue = [IO.File]::ReadAllText($reported, $utf8NoBom) | ConvertFrom-Json
        if ([long](Get-RecoveryRequiredProperty $reportedValue 'approval_comment_id') -ne $id -or
            [string](Get-RecoveryRequiredProperty $reportedValue 'terminal_status') -cne 'STOP_REQUIRED' -or
            [string](Get-RecoveryRequiredProperty $reportedValue 'terminal_record_sha256') -cne $terminalRoundTrip.Sha256) {
            throw 'Conflicting reported record exists.'
        }
    }
    if ($evidence.PendingExists) { Remove-Item -LiteralPath $evidence.PendingPath -Force }
    Write-Output '[TOLLGATE_HISTORICAL_RECOVERY_SETTLED]'
    Write-Output "comment_id: $id"
    Write-Output 'terminal_status: STOP_REQUIRED'
    Write-Output 'termination_reason: MAX_ITERATIONS_REACHED'
    Write-Output "terminal_file: $failedPath"
} catch {
    [Console]::Error.WriteLine("TOLLGATE_HISTORICAL_RECOVERY_ERROR: $($_.Exception.Message)")
    exit 1
}
