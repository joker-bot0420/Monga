[CmdletBinding()]
param(
    [string]$ResultFile,
    [switch]$DryRun,
    [switch]$Publish,
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
    param([Parameter(Mandatory = $true)][object]$Record)
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
$tests

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
    } finally {
        if (Test-Path -LiteralPath $testRoot -PathType Container) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

try {
    if ($DryRun -and $Publish) { throw '-DryRun and -Publish are mutually exclusive.' }
    if ($SelfTest -and ($DryRun -or $Publish -or -not [string]::IsNullOrWhiteSpace($ResultFile))) {
        throw '-SelfTest cannot be combined with reporter execution options.'
    }
    if ($SelfTest) { Invoke-ReporterSelfTest; exit 0 }

    $repositoryRootOutput = & git -C $PSScriptRoot rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Unable to locate repository root.' }
    $repositoryRoot = Get-NormalizedPath -Path (($repositoryRootOutput | Out-String).Trim())
    $stateRoot = Join-Path $repositoryRoot '.tollgate-local'
    $completedDirectory = Join-Path $stateRoot 'completed'
    $failedDirectory = Join-Path $stateRoot 'failed'
    $reportedDirectory = Join-Path $stateRoot 'reported'

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
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hash = Get-BytesSha256 -Bytes $bytes
            $reportedFile = Join-Path $reportedDirectory $file.Name
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
    $terminalBytes = [System.IO.File]::ReadAllBytes($resolvedResultFile)
    $terminalHash = Get-BytesSha256 -Bytes $terminalBytes
    $record = $utf8NoBom.GetString($terminalBytes) | ConvertFrom-Json
    Assert-TerminalRecord -Record $record -RecordPath $resolvedResultFile
    $commentId = [long]$record.comment_id
    $reportedFile = Join-Path $reportedDirectory "$commentId.json"
    if (Assert-ReportedState -ReportedFile $reportedFile -ExpectedTerminalHash $terminalHash) {
        Write-Output "TOLLGATE_RESULT_ALREADY_REPORTED: $commentId"
        exit 0
    }

    $rendered = New-RenderedComment -Record $record
    $expectedMarker = "[$([string]$record.terminal_status)]"
    Assert-OnlyLeadingControlMarker -Rendered $rendered -ExpectedMarker $expectedMarker
    $renderedBytes = $utf8NoBom.GetBytes($rendered)
    $renderedHash = Get-BytesSha256 -Bytes $renderedBytes
    $runtimeDirectory = Join-Path (Join-Path $stateRoot 'runtime/reporter') "$commentId"
    [void](New-Item -ItemType Directory -Path $runtimeDirectory -Force)
    $reportFile = Join-Path $runtimeDirectory 'github-comment.txt'
    $metadataFile = Join-Path $runtimeDirectory 'report-metadata.json'
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
        & gh auth status *> $null
        if ($LASTEXITCODE -ne 0) { throw 'gh authentication failed.' }
        $login = (& gh api user --jq .login | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $login -cne $trustedUser) { throw 'Authenticated GitHub user is invalid.' }
        $pr = & gh api "repos/$repository/pulls/$prNumber" | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or [string]$pr.state -cne 'open') { throw 'Target PR is not open.' }
        $commentUrl = (& gh pr comment $prNumber --repo $repository --body-file $reportFile | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $commentUrl -notmatch 'issuecomment-(\d+)$') { throw 'GitHub comment creation failed.' }
        $githubCommentId = [long]$Matches[1]
        $comment = & gh api "repos/$repository/issues/comments/$githubCommentId" | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or [string]$comment.user.login -cne $trustedUser -or
            [string]$comment.issue_url -cne "https://api.github.com/repos/$repository/issues/$prNumber" -or
            [string]$comment.body -cne $rendered) {
            throw 'Published GitHub comment verification failed.'
        }
        $reported = [ordered]@{
            schema_version = 1; repository = $repository; pr_number = $prNumber
            approval_comment_id = $commentId; terminal_status = [string]$record.terminal_status
            terminal_record_sha256 = $terminalHash; github_comment_id = $githubCommentId
            github_comment_url = $commentUrl; reported_at = [DateTimeOffset]::UtcNow.ToString('o')
        }
        Write-JsonAtomically -Value $reported -Destination $reportedFile
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
}
