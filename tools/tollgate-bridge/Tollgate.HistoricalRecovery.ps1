Set-StrictMode -Version Latest

$script:HistoricalRecoveryConstants = [ordered]@{
    Repository = 'joker-bot0420/Monga'
    PrNumber = 23
    TollgateId = 'TG-AUTO-02-EXT'
    ApprovalCommentId = 5563219043L
    CheckpointCommentId = 5566069227L
    BaseCommit = '84d05941c86a34033749659207d435f6a3349b0f'
    BaseParent = '41fc85474a34a853b2901cf5e77d657fac0976ee'
    Iterations = 5
    ApprovalCommentAuthor = 'joker-bot0420'
    ApprovalCommentCreatedAt = '2026-09-07T00:05:03Z'
    ApprovalCommentBodySha256 = '9cf38618469c281ab7b9238f054f3b8ace33d829537f5473e983acdd75ec9ad7'
    CheckpointCommentAuthor = 'joker-bot0420'
    CheckpointCommentCreatedAt = '2026-09-07T06:31:25Z'
    CheckpointCommentBodySha256 = 'be8f67d852e1d7c314fe41e6b6120176873feac51dfbdd09da9cdbc01e413d18'
    PendingSha256 = 'c1a38025d51c0df53e41fb69dfbea7c259812053d7e03af06f496f267b827fd5'
    IterationSha256 = @(
        '6611bd33a12d587170204a4d16fc0341672cef3ca2b919d36a17ef73ca381791',
        'f85c288a09d93f1e21dff74937950a75c40d725b2ca56478429b71c335aed1eb',
        '650c804eac80a83ae16be13f943c70fec7e69ef4f374dbed42e9a6247c733d1a',
        '0e68ae8aa3f2e9c2fe145e678026f6c6d6d805772d45f43f85e5de5b6ae0d0e4',
        '0a5302bccc6db79220056fd25bbb4fe340b70bdc25cf3fe9a1fe861f32ed7d57'
    )
}

function Get-HistoricalRecoveryConstants {
    return $script:HistoricalRecoveryConstants
}

function ConvertTo-HistoricalRepositoryIdentity {
    param([Parameter(Mandatory = $true)][string]$RemoteUrl)
    $value = $RemoteUrl.Trim()
    $match = [regex]::Match($value, '^(?:https://github\.com/|ssh://git@github\.com/|git@github\.com:)(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw 'Git origin is not a supported GitHub repository URL.' }
    return "$($match.Groups['owner'].Value)/$($match.Groups['repo'].Value)"
}

function Get-HistoricalGitRepositoryRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $output = & git -C $Path rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve Git repository root for: $Path" }
    return [IO.Path]::GetFullPath(($output | Out-String).Trim()).TrimEnd('\')
}

function Assert-HistoricalRepositoryIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedIdentity
    )
    $origin = & git -C $RepositoryRoot remote get-url origin 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to read Git origin for: $RepositoryRoot" }
    $identity = ConvertTo-HistoricalRepositoryIdentity (($origin | Out-String).Trim())
    if (-not $identity.Equals($ExpectedIdentity, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Git repository identity is invalid: $identity"
    }
    return $identity
}

function Get-HistoricalProductionStateContext {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ProductionStateRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedRepositoryIdentity
    )
    if (-not [IO.Path]::IsPathRooted($ProductionStateRoot)) {
        throw '-ProductionStateRoot must be an absolute path.'
    }
    $candidateRoot = [IO.Path]::GetFullPath($CandidateRepositoryRoot).TrimEnd('\')
    $stateRoot = [IO.Path]::GetFullPath($ProductionStateRoot).TrimEnd('\')
    if ([IO.Path]::GetFileName($stateRoot) -cne '.tollgate-local') {
        throw '-ProductionStateRoot basename must be exactly .tollgate-local.'
    }
    if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
        throw '-ProductionStateRoot must be an existing directory.'
    }
    $stateOwnerRoot = [IO.Path]::GetDirectoryName($stateRoot).TrimEnd('\')
    $candidateGitRoot = Get-HistoricalGitRepositoryRoot $candidateRoot
    if (-not $candidateGitRoot.Equals($candidateRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Candidate script root is not the candidate Git top-level.'
    }
    $ownerGitRoot = Get-HistoricalGitRepositoryRoot $stateOwnerRoot
    if (-not $ownerGitRoot.Equals($stateOwnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw '-ProductionStateRoot parent must be the state-owner Git top-level.'
    }
    Assert-HistoricalNoReparsePath -TrustedAnchor $candidateRoot -Root $candidateRoot -Path $candidateRoot
    Assert-HistoricalNoReparsePath -TrustedAnchor $stateOwnerRoot -Root $stateRoot -Path $stateRoot
    $candidateIdentity = Assert-HistoricalRepositoryIdentity $candidateRoot $ExpectedRepositoryIdentity
    $ownerIdentity = Assert-HistoricalRepositoryIdentity $stateOwnerRoot $ExpectedRepositoryIdentity
    return [pscustomobject]@{
        CandidateRepositoryRoot = $candidateRoot
        CandidateRepositoryIdentity = $candidateIdentity
        ProductionStateRoot = $stateRoot
        StateOwnerRepositoryRoot = $stateOwnerRoot
        StateOwnerRepositoryIdentity = $ownerIdentity
    }
}

function Get-ProductionHistoricalEvidenceManifest {
    $c = Get-HistoricalRecoveryConstants
    return [pscustomobject]@{
        pending_sha256 = $c.PendingSha256
        iteration_sha256 = @($c.IterationSha256)
        approval = [pscustomobject]@{
            id = $c.ApprovalCommentId; author = $c.ApprovalCommentAuthor
            created_at = $c.ApprovalCommentCreatedAt; body_sha256 = $c.ApprovalCommentBodySha256
        }
        checkpoint = [pscustomobject]@{
            id = $c.CheckpointCommentId; author = $c.CheckpointCommentAuthor
            created_at = $c.CheckpointCommentCreatedAt; body_sha256 = $c.CheckpointCommentBodySha256
        }
    }
}

function Get-RecoverySha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-RecoveryRequiredProperty {
    param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($Object -is [Collections.IDictionary]) {
        if (-not $Object.Contains($Name)) { throw "Required recovery field is missing: $Name" }
        return $Object[$Name]
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Required recovery field is missing: $Name" }
    return $property.Value
}

function Assert-HistoricalRecoveryMetadataAgainstManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Recovery,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    $c = Get-HistoricalRecoveryConstants
    $manifestIterations = @(Get-RecoveryRequiredProperty $Manifest 'iteration_sha256')
    if ($manifestIterations.Count -ne $c.Iterations) { throw 'Historical evidence manifest must contain five iteration hashes.' }
    $approvalEvidence = Get-RecoveryRequiredProperty $Manifest 'approval'
    $checkpointEvidence = Get-RecoveryRequiredProperty $Manifest 'checkpoint'
    if ([long](Get-RecoveryRequiredProperty $approvalEvidence 'id') -ne $c.ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $approvalEvidence 'author') -cne $c.ApprovalCommentAuthor -or
        [string](Get-RecoveryRequiredProperty $approvalEvidence 'created_at') -cne $c.ApprovalCommentCreatedAt -or
        [long](Get-RecoveryRequiredProperty $checkpointEvidence 'id') -ne $c.CheckpointCommentId -or
        [string](Get-RecoveryRequiredProperty $checkpointEvidence 'author') -cne $c.CheckpointCommentAuthor -or
        [string](Get-RecoveryRequiredProperty $checkpointEvidence 'created_at') -cne $c.CheckpointCommentCreatedAt) {
        throw 'Historical evidence manifest identity is invalid.'
    }
    if ([int](Get-RecoveryRequiredProperty $Recovery 'schema_version') -ne 1 -or
        [string](Get-RecoveryRequiredProperty $Recovery 'settlement_kind') -cne 'historical_recovery' -or
        [string](Get-RecoveryRequiredProperty $Recovery 'termination_reason') -cne 'MAX_ITERATIONS_REACHED' -or
        [int](Get-RecoveryRequiredProperty $Recovery 'automatic_iterations') -ne $c.Iterations -or
        [string](Get-RecoveryRequiredProperty $Recovery 'last_automatic_result') -cne 'CONTINUE' -or
        -not [bool](Get-RecoveryRequiredProperty $Recovery 'requires_user') -or
        -not [bool](Get-RecoveryRequiredProperty $Recovery 'manual_work_is_out_of_band') -or
        [string](Get-RecoveryRequiredProperty $Recovery 'tollgate_id') -cne $c.TollgateId -or
        [long](Get-RecoveryRequiredProperty $Recovery 'approval_comment_id') -ne $c.ApprovalCommentId -or
        [long](Get-RecoveryRequiredProperty $Recovery 'checkpoint_comment_id') -ne $c.CheckpointCommentId -or
        [string](Get-RecoveryRequiredProperty $Recovery 'base_commit') -cne $c.BaseCommit -or
        [string](Get-RecoveryRequiredProperty $Recovery 'base_parent') -cne $c.BaseParent -or
        [bool](Get-RecoveryRequiredProperty $Recovery 'acceptance_satisfied')) {
        throw 'Historical recovery metadata does not match the approved settlement contract.'
    }
    $expectedPending = ([string](Get-RecoveryRequiredProperty $Manifest 'pending_sha256')).ToLowerInvariant()
    if ([string](Get-RecoveryRequiredProperty $Recovery 'pending_sha256') -cne $expectedPending) {
        throw 'Historical recovery pending SHA-256 does not match immutable evidence.'
    }
    $results = @(Get-RecoveryRequiredProperty $Recovery 'iteration_results')
    if ($results.Count -ne $c.Iterations) { throw 'Historical recovery must contain exactly five iteration hashes.' }
    for ($i = 1; $i -le $c.Iterations; $i++) {
        $item = $results[$i - 1]
        if ([int](Get-RecoveryRequiredProperty $item 'iteration') -ne $i -or
            [string](Get-RecoveryRequiredProperty $item 'status') -cne 'CONTINUE' -or
            [string](Get-RecoveryRequiredProperty $item 'sha256') -cne
                ([string]$manifestIterations[$i - 1]).ToLowerInvariant()) {
            throw "Historical recovery iteration metadata is invalid at iteration $i."
        }
    }
    if ([string](Get-RecoveryRequiredProperty $Recovery 'approval_body_sha256') -cne
            ([string](Get-RecoveryRequiredProperty $approvalEvidence 'body_sha256')).ToLowerInvariant() -or
        [string](Get-RecoveryRequiredProperty $Recovery 'checkpoint_body_sha256') -cne
            ([string](Get-RecoveryRequiredProperty $checkpointEvidence 'body_sha256')).ToLowerInvariant()) {
        throw 'Historical recovery comment evidence does not match immutable evidence.'
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $Recovery 'decision_required'))) {
        throw 'Historical recovery decision_required is empty.'
    }
}

function ConvertTo-HistoricalUtcInstant {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($Value -is [DateTimeOffset]) {
        return ([DateTimeOffset]$Value).ToUniversalTime()
    }
    if ($Value -is [DateTime]) {
        $dateTime = [DateTime]$Value
        if ($dateTime.Kind -eq [DateTimeKind]::Unspecified) {
            throw 'Historical timestamp DateTime kind is ambiguous.'
        }
        return ([DateTimeOffset]$dateTime).ToUniversalTime()
    }
    if ($Value -isnot [string]) {
        throw 'Historical timestamp must be an ISO/RFC3339 string or an unambiguous date-time value.'
    }

    $text = [string]$Value
    if ($text -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
        throw 'Historical timestamp must use an explicit ISO/RFC3339 offset.'
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            $text,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsed)) {
        throw 'Historical timestamp is invalid.'
    }
    return $parsed.ToUniversalTime()
}

function Test-HistoricalTimestampInstantEqual {
    param(
        [Parameter(Mandatory = $true)][object]$Actual,
        [Parameter(Mandatory = $true)][object]$Expected
    )
    try {
        $actualInstant = ConvertTo-HistoricalUtcInstant $Actual
        $expectedInstant = ConvertTo-HistoricalUtcInstant $Expected
        return $actualInstant.UtcDateTime.Ticks -eq $expectedInstant.UtcDateTime.Ticks
    } catch {
        return $false
    }
}

function Assert-HistoricalNoReparsePath {
    param(
        [Parameter(Mandatory = $true)][string]$TrustedAnchor,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $anchorFull = [IO.Path]::GetFullPath($TrustedAnchor).TrimEnd('\')
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not ($rootFull -eq $anchorFull -or $rootFull.StartsWith($anchorFull + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Historical recovery state root escapes its trusted anchor.'
    }
    if (-not ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Historical recovery path escapes the state root.'
    }
    $current = $pathFull
    while ($current -and $current.Length -ge $anchorFull.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not permitted in historical recovery paths: $current"
            }
        }
        if ($current.Equals($anchorFull, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    if (-not $current -or -not $current.Equals($anchorFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Historical recovery path could not be traced to its trusted anchor.'
    }
}

function Initialize-HistoricalTrustedDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$TrustedAnchor,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Directory
    )
    Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $Directory
    [void][IO.Directory]::CreateDirectory($Directory)
    Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $Directory
}

function Write-HistoricalBytesAtomically {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$TrustedAnchor,
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$RefuseOverwrite
    )
    $directory = Split-Path -Parent $Destination
    Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $Destination
    Initialize-HistoricalTrustedDirectory -TrustedAnchor $TrustedAnchor -Root $Root -Directory $directory
    Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $Destination
    $temporary = Join-Path $directory ".$([IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).tmp"
    Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $temporary
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $temporary
        Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $Destination
        if ($RefuseOverwrite -and (Test-Path -LiteralPath $Destination)) {
            throw "Refusing to overwrite recovery artifact: $Destination"
        }
        [IO.File]::Move($temporary, $Destination)
        Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $Root -Path $Destination
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Enter-HistoricalReporterTaskLock {
    param([Parameter(Mandatory = $true)][string]$LockPath, [int]$TimeoutMilliseconds = 30000)
    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ($true) {
        try { return Enter-TollgateOrchestratorLock -LockPath $LockPath }
        catch [IO.IOException] {
            if ([DateTimeOffset]::UtcNow -ge $deadline) {
                throw 'Timed out waiting for the historical reporter task lock; no GitHub write was attempted.'
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Assert-HistoricalRecoveryMetadata {
    param([Parameter(Mandatory = $true)][object]$Recovery)
    Assert-HistoricalRecoveryMetadataAgainstManifest -Recovery $Recovery `
        -Manifest (Get-ProductionHistoricalEvidenceManifest)
}

function Assert-HistoricalRecoveryTerminalRecordAgainstManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    $c = Get-HistoricalRecoveryConstants
    if ([int](Get-RecoveryRequiredProperty $Record 'schema_version') -ne 1 -or
        [long](Get-RecoveryRequiredProperty $Record 'comment_id') -ne $c.ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $Record 'terminal_status') -cne 'STOP_REQUIRED' -or
        [int](Get-RecoveryRequiredProperty $Record 'iterations') -ne $c.Iterations) {
        throw 'Terminal record is not the expected historical STOP_REQUIRED settlement.'
    }
    $approval = Get-RecoveryRequiredProperty $Record 'original_approval'
    $approvalBody = [string](Get-RecoveryRequiredProperty $approval 'body')
    $approvalEvidence = Get-RecoveryRequiredProperty $Manifest 'approval'
    $approvalCreatedAtMatches = Test-HistoricalTimestampInstantEqual `
        (Get-RecoveryRequiredProperty $approval 'created_at') `
        (Get-RecoveryRequiredProperty $approvalEvidence 'created_at')
    if ([string](Get-RecoveryRequiredProperty $approval 'repository') -cne $c.Repository -or
        [int](Get-RecoveryRequiredProperty $approval 'pr_number') -ne $c.PrNumber -or
        [long](Get-RecoveryRequiredProperty $approval 'comment_id') -ne $c.ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $approval 'status') -cne 'pending' -or
        [string](Get-RecoveryRequiredProperty $approval 'author') -cne $c.ApprovalCommentAuthor -or
        [string](Get-RecoveryRequiredProperty $approval 'marker') -cne '[TOLLGATE_APPROVED]' -or
        -not $approvalCreatedAtMatches -or
        (Get-RecoverySha256 ([Text.UTF8Encoding]::new($false, $true).GetBytes($approvalBody))) -cne
            ([string](Get-RecoveryRequiredProperty $approvalEvidence 'body_sha256')).ToLowerInvariant()) {
        throw 'Historical terminal approval binding is invalid.'
    }
    $finishedAt = [string](Get-RecoveryRequiredProperty $Record 'finished_at')
    $parsedFinishedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParseExact($finishedAt, 'o', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedFinishedAt)) {
        throw 'Historical terminal finished_at is invalid.'
    }
    $result = Get-RecoveryRequiredProperty $Record 'final_result'
    if ([string](Get-RecoveryRequiredProperty $result 'status') -cne 'STOP_REQUIRED' -or
        -not [bool](Get-RecoveryRequiredProperty $result 'requires_user') -or
        [string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'summary')) -or
        [string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'next_action'))) {
        throw 'Historical terminal final_result is invalid.'
    }
    foreach ($field in @('evidence','changed_files','tests')) {
        $value = Get-RecoveryRequiredProperty $result $field
        # Windows PowerShell 5.1 collapses an empty JSON array to $null. The
        # exact terminal byte comparison enforces the expected [] representation.
        if ($value -is [string]) { throw "Historical terminal final_result.$field must be an array." }
        [void]@($value)
    }
    Assert-HistoricalRecoveryMetadataAgainstManifest -Recovery (Get-RecoveryRequiredProperty $Record 'recovery') -Manifest $Manifest
}

function Assert-HistoricalRecoveryTerminalRecord {
    param([Parameter(Mandatory = $true)][object]$Record)
    Assert-HistoricalRecoveryTerminalRecordAgainstManifest -Record $Record `
        -Manifest (Get-ProductionHistoricalEvidenceManifest)
}

function Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$TerminalPath,
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$TrustedAnchor,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    Assert-HistoricalRecoveryTerminalRecordAgainstManifest -Record $Record -Manifest $Manifest
    $c = Get-HistoricalRecoveryConstants
    $terminalFull = [IO.Path]::GetFullPath($TerminalPath)
    $expectedTerminal = [IO.Path]::GetFullPath((Join-Path $StateRoot "failed/$($c.ApprovalCommentId).json"))
    if (-not $terminalFull.Equals($expectedTerminal, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Historical terminal must be the approval-specific failed artifact.'
    }
    $auditPath = Join-Path $StateRoot "audit/$($c.ApprovalCommentId)-recovery.json"
    $archivePath = Join-Path $StateRoot "archive/pending/$($c.ApprovalCommentId).json"
    foreach ($evidencePath in @($terminalFull, $auditPath, $archivePath)) {
        Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $StateRoot -Path $evidencePath
    }
    if (-not (Test-Path -LiteralPath $auditPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw 'Historical recovery audit and archived pending evidence are required.'
    }
    $terminalHash = Get-RecoverySha256 ([IO.File]::ReadAllBytes($terminalFull))
    $archiveHash = Get-RecoverySha256 ([IO.File]::ReadAllBytes($archivePath))
    if ($archiveHash -cne ([string](Get-RecoveryRequiredProperty $Manifest 'pending_sha256')).ToLowerInvariant()) { throw 'Archived pending evidence hash is invalid.' }
    $auditBytes = [IO.File]::ReadAllBytes($auditPath)
    $auditText = [Text.UTF8Encoding]::new($false, $true).GetString($auditBytes).TrimStart([char]0xFEFF)
    $audit = $auditText | ConvertFrom-Json
    if ([string](Get-RecoveryRequiredProperty $audit 'terminal_sha256') -cne $terminalHash -or
        [string](Get-RecoveryRequiredProperty $audit 'settled_at') -cne [string](Get-RecoveryRequiredProperty $Record 'finished_at') -or
        [string](Get-RecoveryRequiredProperty $audit 'pending_source') -cne "pending/$($c.ApprovalCommentId).json" -or
        [string](Get-RecoveryRequiredProperty $audit 'pending_archive') -cne "archive/pending/$($c.ApprovalCommentId).json" -or
        [string](Get-RecoveryRequiredProperty $audit 'runtime_source') -cne "runtime/$($c.ApprovalCommentId)" -or
        [string](Get-RecoveryRequiredProperty $audit 'terminal_target') -cne "failed/$($c.ApprovalCommentId).json") {
        throw 'Historical recovery audit is not bound to the terminal lifecycle artifacts.'
    }
    $approvalAudit = Get-RecoveryRequiredProperty $audit 'approval_evidence'
    $checkpointAudit = Get-RecoveryRequiredProperty $audit 'checkpoint_evidence'
    $manifestApproval = Get-RecoveryRequiredProperty $Manifest 'approval'
    $manifestCheckpoint = Get-RecoveryRequiredProperty $Manifest 'checkpoint'
    if ([long](Get-RecoveryRequiredProperty $approvalAudit 'id') -ne [long](Get-RecoveryRequiredProperty $manifestApproval 'id') -or
        [string](Get-RecoveryRequiredProperty $approvalAudit 'author') -cne [string](Get-RecoveryRequiredProperty $manifestApproval 'author') -or
        [string](Get-RecoveryRequiredProperty $approvalAudit 'created_at') -cne [string](Get-RecoveryRequiredProperty $manifestApproval 'created_at') -or
        [string](Get-RecoveryRequiredProperty $approvalAudit 'body_sha256') -cne ([string](Get-RecoveryRequiredProperty $manifestApproval 'body_sha256')).ToLowerInvariant() -or
        [long](Get-RecoveryRequiredProperty $checkpointAudit 'id') -ne [long](Get-RecoveryRequiredProperty $manifestCheckpoint 'id') -or
        [string](Get-RecoveryRequiredProperty $checkpointAudit 'author') -cne [string](Get-RecoveryRequiredProperty $manifestCheckpoint 'author') -or
        [string](Get-RecoveryRequiredProperty $checkpointAudit 'created_at') -cne [string](Get-RecoveryRequiredProperty $manifestCheckpoint 'created_at') -or
        [string](Get-RecoveryRequiredProperty $checkpointAudit 'body_sha256') -cne ([string](Get-RecoveryRequiredProperty $manifestCheckpoint 'body_sha256')).ToLowerInvariant()) {
        throw 'Historical recovery audit comment evidence is invalid.'
    }
    $auditRecovery = Get-RecoveryRequiredProperty $audit 'recovery'
    Assert-HistoricalRecoveryMetadataAgainstManifest -Recovery $auditRecovery -Manifest $Manifest
    if (($auditRecovery | ConvertTo-Json -Depth 30 -Compress) -cne
        ((Get-RecoveryRequiredProperty $Record 'recovery') | ConvertTo-Json -Depth 30 -Compress)) {
        throw 'Historical recovery audit metadata does not match the terminal record.'
    }

    # The audit's runtime_source is descriptive metadata, not evidence.  Re-read
    # the immutable runtime results so a fabricated audit/archive/terminal trio
    # cannot bypass the five automatic-iteration record.
    $runtimePath = Join-Path $StateRoot "runtime/$($c.ApprovalCommentId)"
    Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $StateRoot -Path $runtimePath
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) {
        throw 'Historical runtime evidence directory is required.'
    }
    $runtimeDirectories = @(Get-ChildItem -LiteralPath $runtimePath -Directory -Force | Sort-Object Name)
    $expectedNames = @(1..$c.Iterations | ForEach-Object { "iteration-$_" })
    $actualNames = @($runtimeDirectories | ForEach-Object { $_.Name })
    if (@(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count -ne 0) {
        throw 'Historical runtime must contain exactly iteration-1 through iteration-5.'
    }
    $manifestIterations = @(Get-RecoveryRequiredProperty $Manifest 'iteration_sha256')
    $auditIterations = @(Get-RecoveryRequiredProperty $auditRecovery 'iteration_results')
    for ($i = 1; $i -le $c.Iterations; $i++) {
        $resultPath = Join-Path $runtimePath "iteration-$i/codex-result.json"
        Assert-HistoricalNoReparsePath -TrustedAnchor $TrustedAnchor -Root $StateRoot -Path $resultPath
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            throw "Historical runtime result is missing at iteration $i."
        }
        $resultBytes = [IO.File]::ReadAllBytes($resultPath)
        $resultHash = Get-RecoverySha256 $resultBytes
        $expectedHash = ([string]$manifestIterations[$i - 1]).ToLowerInvariant()
        if ($resultHash -cne $expectedHash -or
            [string](Get-RecoveryRequiredProperty $auditIterations[$i - 1] 'sha256') -cne $expectedHash) {
            throw "Historical runtime exact-byte SHA-256 is invalid at iteration $i."
        }
        $resultText = [Text.UTF8Encoding]::new($false, $true).GetString($resultBytes).TrimStart([char]0xFEFF)
        $result = $resultText | ConvertFrom-Json
        if ([string](Get-RecoveryRequiredProperty $result 'status') -cne 'CONTINUE' -or
            [bool](Get-RecoveryRequiredProperty $result 'requires_user') -or
            [string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'summary')) -or
            [string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $result 'next_action'))) {
            throw "Historical runtime result contract is invalid at iteration $i."
        }
        foreach ($field in @('evidence','changed_files','tests')) {
            [void](Get-RecoveryRequiredProperty $result $field)
        }
    }
}

function Assert-HistoricalRecoveryEvidenceArtifacts {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$TerminalPath,
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$StateOwnerRepositoryRoot,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest -Record $Record -TerminalPath $TerminalPath `
        -StateRoot $StateRoot -TrustedAnchor $StateOwnerRepositoryRoot `
        -Manifest $Manifest
}

function Get-HistoricalSettlementKey {
    param([Parameter(Mandatory = $true)][string]$TerminalSha256)
    if ($TerminalSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Terminal SHA-256 is invalid.' }
    $c = Get-HistoricalRecoveryConstants
    return "$($c.TollgateId)/$($c.ApprovalCommentId)/$($TerminalSha256.ToLowerInvariant())"
}

function Find-HistoricalRecoveryComment {
    param(
        [Parameter(Mandatory = $true)][object[]]$Comments,
        [Parameter(Mandatory = $true)][string]$SettlementKey,
        [Parameter(Mandatory = $true)][string]$ExpectedBody,
        [Parameter(Mandatory = $true)][string]$TrustedUser,
        [Parameter(Mandatory = $true)][string]$ExpectedIssueUrl
    )
    $needle = "Settlement key: $SettlementKey"
    $matches = @($Comments | Where-Object {
        $userProperty = $_.PSObject.Properties['user']
        $issueProperty = $_.PSObject.Properties['issue_url']
        $bodyProperty = $_.PSObject.Properties['body']
        if ($null -eq $userProperty -or $null -eq $issueProperty -or $null -eq $bodyProperty -or $null -eq $userProperty.Value) { return $false }
        $loginProperty = $userProperty.Value.PSObject.Properties['login']
        $null -ne $loginProperty -and [string]$loginProperty.Value -ceq $TrustedUser -and
        [string]$issueProperty.Value -ceq $ExpectedIssueUrl -and
        ([string]$bodyProperty.Value).Contains($needle)
    })
    if ($matches.Count -gt 1) { throw 'Multiple historical recovery comments use the same settlement key.' }
    if ($matches.Count -eq 0) { return $null }
    if ([string]$matches[0].body -cne $ExpectedBody) {
        throw 'Historical recovery settlement key exists with a conflicting body.'
    }
    return $matches[0]
}

function Assert-ReporterPrState {
    param([Parameter(Mandatory = $true)][object]$Pr, [switch]$HistoricalRecovery)
    if ($HistoricalRecovery) {
        if ([string]$Pr.state -cne 'closed' -or $null -eq $Pr.merged_at -or [int]$Pr.number -ne 23) {
            throw 'Historical recovery target must be the merged PR #23.'
        }
    } elseif ([string]$Pr.state -cne 'open') {
        throw 'Target PR is not open.'
    }
}

function Assert-HistoricalReportedRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][long]$ApprovalCommentId,
        [Parameter(Mandatory = $true)][string]$SettlementKey,
        [Parameter(Mandatory = $true)][string]$RenderedSha256
    )
    if ([long](Get-RecoveryRequiredProperty $Record 'approval_comment_id') -ne $ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $Record 'terminal_status') -cne 'STOP_REQUIRED' -or
        [string](Get-RecoveryRequiredProperty $Record 'settlement_key') -cne $SettlementKey -or
        [string](Get-RecoveryRequiredProperty $Record 'rendered_comment_sha256') -cne $RenderedSha256) {
        throw 'Historical reported state does not match the settlement key and rendered body.'
    }
}
