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

function Assert-HistoricalRecoveryMetadata {
    param([Parameter(Mandatory = $true)][object]$Recovery)
    $c = Get-HistoricalRecoveryConstants
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
    if ([string](Get-RecoveryRequiredProperty $Recovery 'pending_sha256') -notmatch '^[0-9a-f]{64}$') {
        throw 'Historical recovery pending SHA-256 is invalid.'
    }
    $results = @(Get-RecoveryRequiredProperty $Recovery 'iteration_results')
    if ($results.Count -ne $c.Iterations) { throw 'Historical recovery must contain exactly five iteration hashes.' }
    for ($i = 1; $i -le $c.Iterations; $i++) {
        $item = $results[$i - 1]
        if ([int](Get-RecoveryRequiredProperty $item 'iteration') -ne $i -or
            [string](Get-RecoveryRequiredProperty $item 'status') -cne 'CONTINUE' -or
            [string](Get-RecoveryRequiredProperty $item 'sha256') -notmatch '^[0-9a-f]{64}$') {
            throw "Historical recovery iteration metadata is invalid at iteration $i."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-RecoveryRequiredProperty $Recovery 'decision_required'))) {
        throw 'Historical recovery decision_required is empty.'
    }
}

function Assert-HistoricalRecoveryTerminalRecord {
    param([Parameter(Mandatory = $true)][object]$Record)
    $c = Get-HistoricalRecoveryConstants
    if ([int](Get-RecoveryRequiredProperty $Record 'schema_version') -ne 1 -or
        [long](Get-RecoveryRequiredProperty $Record 'comment_id') -ne $c.ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $Record 'terminal_status') -cne 'STOP_REQUIRED' -or
        [int](Get-RecoveryRequiredProperty $Record 'iterations') -ne $c.Iterations) {
        throw 'Terminal record is not the expected historical STOP_REQUIRED settlement.'
    }
    $approval = Get-RecoveryRequiredProperty $Record 'original_approval'
    if ([string](Get-RecoveryRequiredProperty $approval 'repository') -cne $c.Repository -or
        [int](Get-RecoveryRequiredProperty $approval 'pr_number') -ne $c.PrNumber -or
        [long](Get-RecoveryRequiredProperty $approval 'comment_id') -ne $c.ApprovalCommentId -or
        [string](Get-RecoveryRequiredProperty $approval 'status') -cne 'pending' -or
        [string](Get-RecoveryRequiredProperty $approval 'author') -cne $c.ApprovalCommentAuthor -or
        [string](Get-RecoveryRequiredProperty $approval 'marker') -cne '[TOLLGATE_APPROVED]' -or
        [string](Get-RecoveryRequiredProperty $approval 'created_at') -cne $c.ApprovalCommentCreatedAt) {
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
    Assert-HistoricalRecoveryMetadata -Recovery (Get-RecoveryRequiredProperty $Record 'recovery')
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
        [string]$_.user.login -ceq $TrustedUser -and
        [string]$_.issue_url -ceq $ExpectedIssueUrl -and
        ([string]$_.body).Contains($needle)
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
