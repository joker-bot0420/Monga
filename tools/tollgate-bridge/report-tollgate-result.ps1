[CmdletBinding()]
param(
    [string]$ResultFile,
    [switch]$DryRun,
    [switch]$Publish,
    [switch]$HistoricalRecovery,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = 'joker-bot0420/Monga'
$prNumber = 23
$trustedUser = 'joker-bot0420'
$approvalMarker = '[TOLLGATE_APPROVED]'
$reservedMarkers = @(
    '[TOLLGATE_APPROVED]',
    '[CLOVER_NEXT]',
    '[CODEX_RESULT]',
    '[TOLLGATE_REACHED]',
    '[STOP_REQUIRED]'
)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
$ghExecutable = 'gh'

function Invoke-GhJsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

    try {
        $process = Start-Process `
            -FilePath $ghExecutable `
            -ArgumentList @('api', '--method', 'GET', $Endpoint) `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $json = [System.IO.File]::ReadAllText($stdoutPath, $utf8Strict).Trim()
        $details = [System.IO.File]::ReadAllText($stderrPath, $utf8Strict).Trim()

        if ($process.ExitCode -ne 0) {
            throw "gh api failed for '$Endpoint': $details"
        }

        if ([string]::IsNullOrWhiteSpace($json)) {
            throw "gh api returned an empty response for '$Endpoint'."
        }

        return ConvertFrom-Json -InputObject $json
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-AllIssueCommentsWithFetcher {
    param([Parameter(Mandatory = $true)][string]$Repository,[Parameter(Mandatory = $true)][int]$PrNumber,[Parameter(Mandatory = $true)][scriptblock]$Fetcher)
    $all = @()
    for ($page = 1; $page -le 100; $page++) {
        $items = @(& $Fetcher "repos/$Repository/issues/$PrNumber/comments?per_page=100&page=$page")
        $all += $items
        if ($items.Count -lt 100) { return $all }
    }
    throw 'Historical comment discovery exceeded 100 pages; refusing an incomplete search.'
}
function Get-AllIssueCommentsUtf8 {
    param([Parameter(Mandatory = $true)][string]$Repository, [Parameter(Mandatory = $true)][int]$PrNumber)
    return @(Get-AllIssueCommentsWithFetcher $Repository $PrNumber { param($endpoint) Invoke-GhJsonUtf8 -Endpoint $endpoint })
}

function Resolve-HistoricalRecoveryPublication {
    param(
        [object[]]$ExistingComments,
        [string]$SettlementKey,
        [string]$ExpectedBody,
        [string]$ExpectedIssueUrl,
        [scriptblock]$CreateComment,
        [scriptblock]$RediscoverComments
    )
    $comment = $null
    if (@($ExistingComments).Count -gt 0) {
        $comment = Find-HistoricalRecoveryComment -Comments $ExistingComments -SettlementKey $SettlementKey `
            -ExpectedBody $ExpectedBody -TrustedUser $trustedUser -ExpectedIssueUrl $ExpectedIssueUrl
    }
    if ($null -ne $comment) { return $comment }
    try { $comment = & $CreateComment } catch { $comment = $null }
    if ($null -eq $comment) {
        $rediscovered = @(& $RediscoverComments)
        if ($rediscovered.Count -gt 0) {
            $comment = Find-HistoricalRecoveryComment -Comments $rediscovered -SettlementKey $SettlementKey `
                -ExpectedBody $ExpectedBody -TrustedUser $trustedUser -ExpectedIssueUrl $ExpectedIssueUrl
        }
    }
    if ($null -eq $comment) { throw 'GitHub comment creation had an uncertain or failed outcome; no retry was attempted.' }
    $commentUser = Get-RecoveryRequiredProperty $comment 'user'
    if ([string](Get-RecoveryRequiredProperty $commentUser 'login') -cne $trustedUser -or
        [string](Get-RecoveryRequiredProperty $comment 'issue_url') -cne $ExpectedIssueUrl -or
        [string](Get-RecoveryRequiredProperty $comment 'body') -cne $ExpectedBody) {
        throw 'Published GitHub comment verification failed.'
    }
    return $comment
}
function Fail-Reporter {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine("TOLLGATE_REPORTER_ERROR: $Message")
    exit 1
}

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-DirectJsonChild {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedParents
    )
    if ([System.IO.Path]::GetExtension($Path) -cne '.json') { return $false }
    $actualParent = Get-NormalizedPath -Path ([System.IO.Path]::GetDirectoryName($Path))
    foreach ($parent in $AllowedParents) {
        if ($actualParent.Equals((Get-NormalizedPath -Path $parent), [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-BytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha256.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Write-Utf8NoBomAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $directory = Split-Path -Parent $Destination
    [void](New-Item -ItemType Directory -Path $directory -Force)
    $temporaryFile = Join-Path $directory ".$([System.IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).tmp"
    $backupFile = Join-Path $directory ".$([System.IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).bak"

    try {
        [System.IO.File]::WriteAllBytes($temporaryFile, $utf8NoBom.GetBytes($Text))

        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            [System.IO.File]::Replace($temporaryFile, $Destination, $backupFile)
        }
        else {
            [System.IO.File]::Move($temporaryFile, $Destination)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
            Remove-Item -LiteralPath $backupFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $json = $Value | ConvertTo-Json -Depth 20
    Write-Utf8NoBomAtomically -Text $json -Destination $Destination
    [void](Get-Content -LiteralPath $Destination -Raw -Encoding utf8 | ConvertFrom-Json)
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Required field is missing: $Name" }
    return $property.Value
}

function Assert-StringArray {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $value = Get-RequiredProperty -Object $Object -Name $Name
    foreach ($item in @($value)) {
        if ($item -isnot [string]) { throw "$Name must contain only strings." }
    }
}

function Assert-TerminalRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$RecordPath
    )
    if ([int](Get-RequiredProperty $Record 'schema_version') -ne 1) { throw 'Terminal schema_version must be 1.' }
    $approval = Get-RequiredProperty $Record 'original_approval'
    if ([int](Get-RequiredProperty $approval 'schema_version') -ne 1) { throw 'Approval schema_version must be 1.' }
    if ([string](Get-RequiredProperty $approval 'repository') -cne $repository) { throw 'Approval repository is invalid.' }
    if ([int](Get-RequiredProperty $approval 'pr_number') -ne $prNumber) { throw 'Approval PR number is invalid.' }
    if ([string](Get-RequiredProperty $approval 'author') -cne $trustedUser) { throw 'Approval author is not trusted.' }
    if ([string](Get-RequiredProperty $approval 'marker') -cne $approvalMarker) { throw 'Approval marker is invalid.' }
    if ([string]::IsNullOrWhiteSpace([string](Get-RequiredProperty $approval 'body'))) { throw 'Approval body is empty.' }
    $commentId = [long](Get-RequiredProperty $approval 'comment_id')
    if ($commentId -le 0 -or [long](Get-RequiredProperty $Record 'comment_id') -ne $commentId) { throw 'Comment ID is invalid.' }
    if ([System.IO.Path]::GetFileName($RecordPath) -cne "$commentId.json") { throw 'Terminal filename does not match comment ID.' }

    $terminalStatus = [string](Get-RequiredProperty $Record 'terminal_status')
    if ($terminalStatus -notin @('TOLLGATE_REACHED', 'STOP_REQUIRED')) { throw 'Terminal status is invalid.' }
    if ([int](Get-RequiredProperty $Record 'iterations') -le 0) { throw 'Iterations must be positive.' }
    $finishedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string](Get-RequiredProperty $Record 'finished_at'), [ref]$finishedAt)) {
        throw 'finished_at is invalid.'
    }

    $result = Get-RequiredProperty $Record 'final_result'
    if ([string](Get-RequiredProperty $result 'status') -cne $terminalStatus) { throw 'Final result status mismatch.' }
    if ((Get-RequiredProperty $result 'summary') -isnot [string]) { throw 'Final summary must be a string.' }
    foreach ($name in @('evidence', 'changed_files', 'tests')) { Assert-StringArray -Object $result -Name $name }
    if ((Get-RequiredProperty $result 'next_action') -isnot [string]) { throw 'next_action must be a string.' }
    $requiresUser = Get-RequiredProperty $result 'requires_user'
    if ($requiresUser -isnot [bool]) { throw 'requires_user must be boolean.' }
    if ($terminalStatus -eq 'TOLLGATE_REACHED' -and [bool]$requiresUser) { throw 'TOLLGATE_REACHED requires_user mismatch.' }
    if ($terminalStatus -eq 'STOP_REQUIRED' -and -not [bool]$requiresUser) { throw 'STOP_REQUIRED requires_user mismatch.' }
}

function ConvertTo-SafeReportText {
    param([AllowEmptyString()][string]$Text)
    $safe = if ($null -eq $Text) { '' } else { $Text }
    foreach ($marker in $reservedMarkers) {
        $neutralized = $marker.Replace('[', '［').Replace(']', '］')
        $safe = $safe.Replace($marker, $neutralized)
    }
    return $safe
}

function Format-ReportList {
    param([object[]]$Items)
    $lines = @($Items | ForEach-Object { "- $(ConvertTo-SafeReportText -Text ([string]$_))" })
    if ($lines.Count -eq 0) { return '- none' }
    return $lines -join "`n"
}

function New-RenderedComment {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [string]$SettlementKey
    )
    $status = [string]$Record.terminal_status
    $result = $Record.final_result
    $summary = ConvertTo-SafeReportText -Text ([string]$result.summary)
    $nextAction = ConvertTo-SafeReportText -Text ([string]$result.next_action)
    $evidence = Format-ReportList -Items @($result.evidence)
    $changedFiles = Format-ReportList -Items @($result.changed_files)
    $tests = Format-ReportList -Items @($result.tests)

    if ($status -eq 'TOLLGATE_REACHED') {
        return @"
[TOLLGATE_REACHED]

Tollgate execution completed.

Approval comment: #$([long]$Record.comment_id)
Iterations: $([int]$Record.iterations)
Finished at: $([string]$Record.finished_at)

Summary:
$summary

Evidence:
$evidence

Changed files:
$changedFiles

Tests:
$tests

Next action:
$nextAction

Bridge verification:
- terminal record validated
- pending lifecycle completed
- result published by local tollgate reporter
"@
    }

    $testsSection = if ([string]::IsNullOrWhiteSpace($SettlementKey)) { $tests } else {
@"
$tests

Historical recovery:
- The five automatic iterations all returned CONTINUE.
- MAX_ITERATIONS_REACHED exhausted the automatic budget without satisfying acceptance criteria.
- Later manual work is out-of-band and is not an additional automatic iteration.
- Settlement key: $SettlementKey
"@
    }
    return @"
[STOP_REQUIRED]

Tollgate execution stopped for user review.

Approval comment: #$([long]$Record.comment_id)
Iterations: $([int]$Record.iterations)
Finished at: $([string]$Record.finished_at)

Reason:
$summary

Evidence:
$evidence

Changed files:
$changedFiles

Tests:
$testsSection

User decision required:
$nextAction

Bridge verification:
- terminal record validated
- further autonomous execution stopped
"@
}

function Assert-OnlyLeadingControlMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Rendered,
        [Parameter(Mandatory = $true)][string]$ExpectedMarker
    )
    $firstLine = ($Rendered -split "`r?`n", 2)[0]
    if ($firstLine -cne $ExpectedMarker) { throw 'Rendered control marker is invalid.' }
    foreach ($marker in $reservedMarkers) {
        $matches = [regex]::Matches($Rendered, [regex]::Escape($marker)).Count
        $expectedCount = if ($marker -ceq $ExpectedMarker) { 1 } else { 0 }
        if ($matches -ne $expectedCount) { throw "Reserved marker was not safely neutralized: $marker" }
    }
}

function Assert-ReportedState {
    param(
        [Parameter(Mandatory = $true)][string]$ReportedFile,
        [Parameter(Mandatory = $true)][string]$ExpectedTerminalHash
    )
    if (-not (Test-Path -LiteralPath $ReportedFile -PathType Leaf)) { return $false }
    $reported = Get-Content -LiteralPath $ReportedFile -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$reported.terminal_record_sha256 -cne $ExpectedTerminalHash) {
        throw 'Terminal record changed after it was reported.'
    }
    return $true
}

function Invoke-ReporterSelfTest {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "monga-reporter-$([Guid]::NewGuid().ToString('N'))"
    [void](New-Item -ItemType Directory -Path $testRoot -Force)
    try {
        $record = [pscustomobject]@{
            schema_version = 1; comment_id = 99L; terminal_status = 'STOP_REQUIRED'; iterations = 1
            finished_at = '2026-09-05T00:00:00Z'
            original_approval = [pscustomobject]@{ schema_version = 1; repository = $repository; pr_number = $prNumber; comment_id = 99L; author = $trustedUser; marker = $approvalMarker; body = '한국어'; status = 'pending' }
            final_result = [pscustomobject]@{ status = 'STOP_REQUIRED'; summary = 'Need [STOP_REQUIRED] and [TOLLGATE_REACHED] test'; requires_user = $true; evidence = @('[CODEX_RESULT]'); changed_files = @('[TOLLGATE_APPROVED]'); tests = @('[CLOVER_NEXT]'); next_action = '사용자 결정' }
        }
        $recordFile = Join-Path $testRoot '99.json'
        Write-JsonAtomically -Value $record -Destination $recordFile
        $roundTrip = Get-Content -LiteralPath $recordFile -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-TerminalRecord -Record $roundTrip -RecordPath $recordFile
        $rendered = New-RenderedComment -Record $roundTrip
        Assert-OnlyLeadingControlMarker -Rendered $rendered -ExpectedMarker '[STOP_REQUIRED]'
        if (-not $rendered.Contains('한국어') -and -not ([string]$roundTrip.original_approval.body).Contains('한국어')) {
            throw 'UTF-8 Korean round-trip failed.'
        }
        Write-Output 'RESERVED_MARKER_SANITIZATION_TEST_OK'
        Write-Output 'UTF8_REPORTER_TEST_OK'

        $bytes = [System.IO.File]::ReadAllBytes($recordFile)
        $hash1 = Get-BytesSha256 -Bytes $bytes
        $hash2 = Get-BytesSha256 -Bytes $bytes
        if ($hash1 -cne $hash2) { throw 'Terminal SHA-256 is unstable.' }
        Write-Output 'TERMINAL_SHA256_TEST_OK'

        $reportedFile = Join-Path $testRoot 'reported/99.json'
        $reported = [ordered]@{ schema_version = 1; terminal_record_sha256 = $hash1 }
        Write-JsonAtomically -Value $reported -Destination $reportedFile
        if (-not (Assert-ReportedState -ReportedFile $reportedFile -ExpectedTerminalHash $hash1)) {
            throw 'Reported duplicate detection failed.'
        }
        Write-Output 'REPORTED_DUPLICATE_TEST_OK'
        Write-Output 'ATOMIC_REPORTED_WRITE_TEST_OK'

        $c = Get-HistoricalRecoveryConstants
        $historicalApprovalBody = 'TG-AUTO-02-EXT'
        $historicalApprovalHash = Get-RecoverySha256 ([Text.UTF8Encoding]::new($false, $true).GetBytes($historicalApprovalBody))
        $historicalManifest = [pscustomobject]@{
            pending_sha256=('a' * 64); iteration_sha256=@(1..5 | ForEach-Object { 'b' * 64 })
            approval=[pscustomobject]@{id=$c.ApprovalCommentId;author=$c.ApprovalCommentAuthor;created_at=$c.ApprovalCommentCreatedAt;body_sha256=$historicalApprovalHash}
            checkpoint=[pscustomobject]@{id=$c.CheckpointCommentId;author=$c.CheckpointCommentAuthor;created_at=$c.CheckpointCommentCreatedAt;body_sha256=('d' * 64)}
        }
        $recovery = [ordered]@{
            schema_version=1; settlement_kind='historical_recovery'; termination_reason='MAX_ITERATIONS_REACHED'
            automatic_iterations=5; last_automatic_result='CONTINUE'; requires_user=$true
            manual_work_is_out_of_band=$true; tollgate_id=$c.TollgateId
            approval_comment_id=$c.ApprovalCommentId; checkpoint_comment_id=$c.CheckpointCommentId
            pending_sha256=('a' * 64); iteration_results=@(1..5 | ForEach-Object { [ordered]@{iteration=$_;status='CONTINUE';sha256=('b' * 64)} })
            approval_body_sha256=$historicalApprovalHash; checkpoint_body_sha256=('d' * 64)
            base_commit=$c.BaseCommit; base_parent=$c.BaseParent; acceptance_satisfied=$false; decision_required='new approval'
        }
        $historical = [pscustomobject]@{
            schema_version=1; comment_id=$c.ApprovalCommentId; terminal_status='STOP_REQUIRED'; iterations=5
            finished_at='2026-09-07T06:31:25.0000000+00:00'
            original_approval=[pscustomobject]@{schema_version=1;repository=$repository;pr_number=23;comment_id=$c.ApprovalCommentId;author=$trustedUser;created_at=$c.ApprovalCommentCreatedAt;marker=$approvalMarker;body=$historicalApprovalBody;status='pending'}
            final_result=[pscustomobject]@{status='STOP_REQUIRED';summary='budget exhausted';requires_user=$true;evidence=@();changed_files=@();tests=@();next_action='new approval'}
            recovery=$recovery
        }
        Assert-HistoricalRecoveryTerminalRecordAgainstManifest $historical $historicalManifest
        $rejectedProductionBypass = $false
        try { Assert-HistoricalRecoveryTerminalRecord $historical } catch { $rejectedProductionBypass = $true }
        if (-not $rejectedProductionBypass) { throw 'Synthetic historical terminal bypassed production immutable evidence.' }
        $settlementKey = Get-HistoricalSettlementKey ('c' * 64)
        $historicalBody = New-RenderedComment $historical $settlementKey
        Assert-OnlyLeadingControlMarker $historicalBody '[STOP_REQUIRED]'
        $issueUrl = "https://api.github.com/repos/$repository/issues/$prNumber"
        $existing = [pscustomobject]@{id=123;html_url='https://example/123';issue_url=$issueUrl;body=$historicalBody;user=[pscustomobject]@{login=$trustedUser}}
        if ((Find-HistoricalRecoveryComment @($existing) $settlementKey $historicalBody $trustedUser $issueUrl).id -ne 123) { throw 'Historical comment adoption failed.' }
        $counts=[pscustomobject]@{Create=0;Rediscover=0}
        $adopted=Resolve-HistoricalRecoveryPublication @($existing) $settlementKey $historicalBody $issueUrl { $counts.Create++;$null } { $counts.Rediscover++;@() }
        if($adopted.id-ne 123-or$counts.Create-ne 0-or$counts.Rediscover-ne 0){throw 'Existing historical comment was not adopted without publish.'}
        $counts=[pscustomobject]@{Create=0;Rediscover=0}
        $published=Resolve-HistoricalRecoveryPublication @() $settlementKey $historicalBody $issueUrl { $counts.Create++;$existing } { $counts.Rediscover++;@() }
        if($published.id-ne 123-or$counts.Create-ne 1-or$counts.Rediscover-ne 0){throw 'Mock historical publish success path failed.'}
        $counts=[pscustomobject]@{Create=0;Rediscover=0}
        $recovered=Resolve-HistoricalRecoveryPublication @() $settlementKey $historicalBody $issueUrl { $counts.Create++;$null } { $counts.Rediscover++;@($existing) }
        if($recovered.id-ne 123-or$counts.Create-ne 1-or$counts.Rediscover-ne 1){throw 'Ambiguous publish rediscovery failed.'}
        $blocked=$false;try{[void](Resolve-HistoricalRecoveryPublication @() $settlementKey $historicalBody $issueUrl { $null } { @() })}catch{$blocked=$true};if(-not$blocked){throw 'Ambiguous publish without rediscovery evidence was accepted.'}
        $pagination=[pscustomobject]@{Calls=0};$paged=@(Get-AllIssueCommentsWithFetcher $repository $prNumber {param($endpoint);$pagination.Calls++;if($pagination.Calls-eq 1){@(1..100|ForEach-Object{[pscustomobject]@{id=$_}})}else{@([pscustomobject]@{id=101})}})
        if($paged.Count-ne 101-or$pagination.Calls-ne 2){throw 'Historical comment pagination failed.'}
        $reportedWriteFailed=$false;try{Write-JsonAtomically @{id=1} $testRoot}catch{$reportedWriteFailed=$true};if(-not$reportedWriteFailed){throw 'Reported-state write failure fixture did not fail.'}
        $counts=[pscustomobject]@{Create=0};$retryAdopted=Resolve-HistoricalRecoveryPublication @($existing) $settlementKey $historicalBody $issueUrl { $counts.Create++;$null } { @() }
        if($retryAdopted.id-ne 123-or$counts.Create-ne 0){throw 'Post-write-failure retry would duplicate the published comment.'}
        Assert-ReporterPrState ([pscustomobject]@{number=23;state='open';merged_at=$null})
        Assert-ReporterPrState ([pscustomobject]@{number=23;state='closed';merged_at='2026-09-07T00:31:07Z'}) -HistoricalRecovery
        Write-Output 'HISTORICAL_RECOVERY_REPORTER_TEST_OK'
    } finally {
        if (Test-Path -LiteralPath $testRoot -PathType Container) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

$historicalTaskLock = $null
try {
    if ($DryRun -and $Publish) { throw '-DryRun and -Publish are mutually exclusive.' }
    if ($HistoricalRecovery -and -not ($DryRun -or $Publish)) { throw '-HistoricalRecovery requires -DryRun or -Publish.' }
    if ($SelfTest -and ($DryRun -or $Publish -or $HistoricalRecovery -or -not [string]::IsNullOrWhiteSpace($ResultFile))) {
        throw '-SelfTest cannot be combined with reporter execution options.'
    }
    . (Join-Path $PSScriptRoot 'Tollgate.HistoricalRecovery.ps1')
    if ($HistoricalRecovery -or $SelfTest) {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'tollgate-orchestrator/Orchestrator.Lock.ps1')
    }
    if ($SelfTest) { Invoke-ReporterSelfTest; exit 0 }

    $repositoryRootOutput = & git -C $PSScriptRoot rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Unable to locate repository root.' }
    $repositoryRoot = Get-NormalizedPath -Path (($repositoryRootOutput | Out-String).Trim())
    $stateRoot = Join-Path $repositoryRoot '.tollgate-local'
    $completedDirectory = Join-Path $stateRoot 'completed'
    $failedDirectory = Join-Path $stateRoot 'failed'
    $reportedDirectory = Join-Path $stateRoot 'reported'
    foreach ($path in @($stateRoot, $completedDirectory, $failedDirectory, $reportedDirectory)) {
        Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $path
    }

    if ([string]::IsNullOrWhiteSpace($ResultFile)) {
        $terminalFiles = @(
            foreach ($directory in @($completedDirectory, $failedDirectory)) {
                if (Test-Path -LiteralPath $directory -PathType Container) {
                    Get-ChildItem -LiteralPath $directory -Filter '*.json' -File
                }
            }
        )
        $unreported = @()
        foreach ($file in $terminalFiles) {
            Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $file.FullName
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hash = Get-BytesSha256 -Bytes $bytes
            $reportedFile = Join-Path $reportedDirectory $file.Name
            Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $reportedFile
            if (-not (Assert-ReportedState -ReportedFile $reportedFile -ExpectedTerminalHash $hash)) {
                $unreported += $file
            }
        }
        if ($unreported.Count -eq 0) { Write-Output 'NO_UNREPORTED_TOLLGATE_RESULT'; exit 0 }
        if ($unreported.Count -gt 1) { [Console]::Error.WriteLine('MULTIPLE_UNREPORTED_TOLLGATE_RESULTS'); exit 2 }
        $resolvedResultFile = Get-NormalizedPath -Path $unreported[0].FullName
    } else {
        if (-not (Test-Path -LiteralPath $ResultFile -PathType Leaf)) { throw "Result file not found: $ResultFile" }
        $resolvedResultFile = Get-NormalizedPath -Path (Resolve-Path -LiteralPath $ResultFile)
    }

    if (-not (Test-DirectJsonChild -Path $resolvedResultFile -AllowedParents @($completedDirectory, $failedDirectory))) {
        throw 'Result file must be a canonical direct JSON child of completed/ or failed/.'
    }
    Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $resolvedResultFile
    $terminalBytes = [System.IO.File]::ReadAllBytes($resolvedResultFile)
    $terminalHash = Get-BytesSha256 -Bytes $terminalBytes

    $terminalText = $utf8NoBom.GetString($terminalBytes)
    if ($terminalText.Length -gt 0 -and $terminalText[0] -eq [char]0xFEFF) {
        $terminalText = $terminalText.Substring(1)
    }

    $record = ConvertFrom-Json -InputObject $terminalText
    Assert-TerminalRecord -Record $record -RecordPath $resolvedResultFile
    $hasRecovery = $null -ne $record.PSObject.Properties['recovery']
    if ($HistoricalRecovery) {
        if (-not $hasRecovery) { throw 'Historical recovery mode requires a recovery terminal record.' }
        Assert-HistoricalRecoveryEvidenceArtifacts -Record $record -TerminalPath $resolvedResultFile -StateRoot $stateRoot
    } elseif ($hasRecovery) {
        throw 'Historical recovery records require explicit -HistoricalRecovery mode.'
    }
    $commentId = [long]$record.comment_id
    if ($HistoricalRecovery) {
        $taskLockPath = Join-Path $stateRoot "orchestrator/task-$commentId.lock"
        Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $taskLockPath
        [void][IO.Directory]::CreateDirectory((Split-Path $taskLockPath -Parent))
        Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $taskLockPath
        # Serialize discovery, optional publication, verification, and the
        # reported-state commit with settlement and direct executor users of
        # the same approval-specific lock identity.
        $historicalTaskLock = Enter-HistoricalReporterTaskLock -LockPath $taskLockPath
    }
    $reportedFile = Join-Path $reportedDirectory "$commentId.json"
    Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $reportedFile
    $alreadyReported = Assert-ReportedState -ReportedFile $reportedFile -ExpectedTerminalHash $terminalHash
    if ($alreadyReported -and -not $HistoricalRecovery) {
        Write-Output "TOLLGATE_RESULT_ALREADY_REPORTED: $commentId"
        exit 0
    }

    $settlementKey = if ($HistoricalRecovery) { Get-HistoricalSettlementKey -TerminalSha256 $terminalHash } else { '' }
    $rendered = New-RenderedComment -Record $record -SettlementKey $settlementKey
    $expectedMarker = "[$([string]$record.terminal_status)]"
    Assert-OnlyLeadingControlMarker -Rendered $rendered -ExpectedMarker $expectedMarker
    $renderedBytes = $utf8NoBom.GetBytes($rendered)
    $renderedHash = Get-BytesSha256 -Bytes $renderedBytes
    if ($alreadyReported) {
        $reportedRecord = Get-Content -LiteralPath $reportedFile -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-HistoricalReportedRecord -Record $reportedRecord -ApprovalCommentId $commentId `
            -SettlementKey $settlementKey -RenderedSha256 $renderedHash
        Write-Output "TOLLGATE_RESULT_ALREADY_REPORTED: $commentId"
        exit 0
    }
    $runtimeDirectory = Join-Path (Join-Path $stateRoot 'runtime/reporter') "$commentId"
    Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $runtimeDirectory
    Initialize-HistoricalTrustedDirectory -TrustedAnchor $repositoryRoot -Root $stateRoot -Directory $runtimeDirectory
    $reportFile = Join-Path $runtimeDirectory 'github-comment.txt'
    $metadataFile = Join-Path $runtimeDirectory 'report-metadata.json'
    foreach ($path in @($runtimeDirectory,$reportFile,$metadataFile)) {
        Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $path
    }
    [System.IO.File]::WriteAllBytes($reportFile, $renderedBytes)
    $metadata = [ordered]@{
        source_terminal_record = $resolvedResultFile
        source_terminal_record_sha256 = $terminalHash
        rendered_comment_utf8_byte_length = $renderedBytes.Length
        rendered_comment_sha256 = $renderedHash
        intended_marker = $expectedMarker
        dry_run = -not $Publish.IsPresent
    }
    Write-JsonAtomically -Value $metadata -Destination $metadataFile

    if ($Publish) {
        if ($null -eq (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue)) { throw 'gh is unavailable.' }
        & $ghExecutable auth status *> $null
        if ($LASTEXITCODE -ne 0) { throw 'gh authentication failed.' }
        $user = Invoke-GhJsonUtf8 -Endpoint 'user'
        $login = [string]$user.login
        if ($login -cne $trustedUser) { throw 'Authenticated GitHub user is invalid.' }

        $pr = Invoke-GhJsonUtf8 -Endpoint "repos/$repository/pulls/$prNumber"
        Assert-ReporterPrState -Pr $pr -HistoricalRecovery:$HistoricalRecovery

        $comment = $null
        if ($HistoricalRecovery) {
            $comments = @(Get-AllIssueCommentsUtf8 -Repository $repository -PrNumber $prNumber)
            $createHistorical = {
                $url = (& $ghExecutable pr comment $prNumber --repo $repository --body-file $reportFile | Out-String).Trim()
                if ($LASTEXITCODE -ne 0 -or $url -notmatch 'issuecomment-(\d+)$') { return $null }
                return Invoke-GhJsonUtf8 -Endpoint "repos/$repository/issues/comments/$([long]$Matches[1])"
            }
            $rediscoverHistorical = { @(Get-AllIssueCommentsUtf8 -Repository $repository -PrNumber $prNumber) }
            $comment = Resolve-HistoricalRecoveryPublication -ExistingComments $comments -SettlementKey $settlementKey `
                -ExpectedBody $rendered -ExpectedIssueUrl "https://api.github.com/repos/$repository/issues/$prNumber" `
                -CreateComment $createHistorical -RediscoverComments $rediscoverHistorical
        } else {
            $commentUrl = (& $ghExecutable pr comment $prNumber --repo $repository --body-file $reportFile | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $commentUrl -notmatch 'issuecomment-(\d+)$') { throw 'GitHub comment creation failed.' }
            $githubCommentId = [long]$Matches[1]
            $comment = Invoke-GhJsonUtf8 -Endpoint "repos/$repository/issues/comments/$githubCommentId"
        }
        $githubCommentId = [long]$comment.id
        $commentUrl = [string]$comment.html_url
        $publishedUser = Get-RecoveryRequiredProperty $comment 'user'
        if ([string](Get-RecoveryRequiredProperty $publishedUser 'login') -cne $trustedUser -or
            [string](Get-RecoveryRequiredProperty $comment 'issue_url') -cne "https://api.github.com/repos/$repository/issues/$prNumber" -or
            [string](Get-RecoveryRequiredProperty $comment 'body') -cne $rendered) {
            throw 'Published GitHub comment verification failed.'
        }
        $reported = [ordered]@{
            schema_version = 1; repository = $repository; pr_number = $prNumber
            approval_comment_id = $commentId; terminal_status = [string]$record.terminal_status
            terminal_record_sha256 = $terminalHash; github_comment_id = $githubCommentId
            github_comment_url = $commentUrl; reported_at = [DateTimeOffset]::UtcNow.ToString('o')
        }
        if ($HistoricalRecovery) {
            $reported.settlement_key = $settlementKey
            $reported.rendered_comment_sha256 = $renderedHash
        }
        Initialize-HistoricalTrustedDirectory -TrustedAnchor $repositoryRoot -Root $stateRoot -Directory $reportedDirectory
        Assert-HistoricalNoReparsePath -TrustedAnchor $repositoryRoot -Root $stateRoot -Path $reportedFile
        $reportedBytes = $utf8NoBom.GetBytes(($reported | ConvertTo-Json -Depth 20))
        Write-HistoricalBytesAtomically -Bytes $reportedBytes -Destination $reportedFile `
            -TrustedAnchor $repositoryRoot -Root $stateRoot -RefuseOverwrite
        [void](Get-Content -LiteralPath $reportedFile -Raw -Encoding utf8 | ConvertFrom-Json)
    }

    Write-Output '[TOLLGATE_REPORT_READY]'
    Write-Output "approval_comment_id: $commentId"
    Write-Output "terminal_status: $([string]$record.terminal_status)"
    Write-Output "mode: $(if ($Publish) { 'PUBLISH' } else { 'DRY_RUN' })"
    Write-Output "report_file: $reportFile"
    Write-Output "terminal_record_sha256: $terminalHash"
    Write-Output "rendered_comment_sha256: $renderedHash"
} catch {
    Fail-Reporter -Message $_.Exception.Message
} finally {
    if ($null -ne $historicalTaskLock) { $historicalTaskLock.Dispose() }
}
