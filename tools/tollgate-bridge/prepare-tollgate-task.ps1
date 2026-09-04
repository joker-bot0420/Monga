[CmdletBinding()]
param(
    [switch]$SerializationSelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = 'joker-bot0420/Monga'
$prNumber = 23
$trustedUser = 'joker-bot0420'
$triggerMarker = '[TOLLGATE_APPROVED]'

function Fail-Prepare {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [Console]::Error.WriteLine("TOLLGATE_PREPARE_ERROR: $Message")
    exit 1
}

function Write-TaskEnvelopeAtomically {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Envelope,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)

    $temporaryFile = Join-Path $destinationDirectory ".$([System.IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Envelope | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryFile -Encoding utf8
        Move-Item -LiteralPath $temporaryFile -Destination $Destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }
}

function Assert-TaskEnvelope {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Envelope
    )

    if ([int]$Envelope.schema_version -ne 1) {
        throw 'Unsupported task envelope schema_version.'
    }
    if ([string]$Envelope.repository -ne $repository) {
        throw 'Task envelope repository does not match the configured repository.'
    }
    if ([int]$Envelope.pr_number -ne $prNumber) {
        throw 'Task envelope PR number does not match the configured PR.'
    }
    if ([long]$Envelope.comment_id -le 0) {
        throw 'Task envelope comment_id is invalid.'
    }
    if ([string]$Envelope.author -ne $trustedUser) {
        throw 'Task envelope author is not trusted.'
    }
    if ([string]$Envelope.marker -ne $triggerMarker) {
        throw 'Task envelope marker is invalid.'
    }
    if (-not ([string]$Envelope.body).Contains($triggerMarker, [StringComparison]::Ordinal)) {
        throw 'Task envelope body does not contain the exact trigger marker.'
    }
    if ([string]$Envelope.status -ne 'pending') {
        throw 'Task envelope status is not pending.'
    }

    $parsedTimestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Envelope.created_at, [ref]$parsedTimestamp)) {
        throw 'Task envelope created_at is not a valid timestamp.'
    }
}

function Invoke-SerializationSelfTest {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "monga-tollgate-$([Guid]::NewGuid().ToString('N'))"
    $testFile = Join-Path $testRoot '5537055156.json'
    $testBody = "[TOLLGATE_APPROVED]`n`n한국어 UTF-8 round-trip 테스트"
    $testEnvelope = [ordered]@{
        schema_version = 1
        repository = $repository
        pr_number = $prNumber
        comment_id = 5537055156L
        author = $trustedUser
        created_at = '2026-09-04T07:13:17Z'
        marker = $triggerMarker
        body = $testBody
        status = 'pending'
    }

    try {
        Write-TaskEnvelopeAtomically -Envelope $testEnvelope -Destination $testFile
        $roundTrip = Get-Content -LiteralPath $testFile -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-TaskEnvelope -Envelope $roundTrip

        if ([long]$roundTrip.comment_id -ne 5537055156L) {
            throw 'Serialization self-test comment_id mismatch.'
        }
        if ([string]$roundTrip.body -cne $testBody) {
            throw 'Serialization self-test body round-trip mismatch.'
        }

        Write-Output 'SERIALIZATION_TEST_OK'
    } finally {
        if (Test-Path -LiteralPath $testRoot -PathType Container) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

try {
    if ($SerializationSelfTest) {
        Invoke-SerializationSelfTest
        exit 0
    }

    $repositoryRootOutput = & git -C $PSScriptRoot rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($repositoryRootOutput | Out-String).Trim()
        throw "Unable to locate the repository root: $details"
    }

    $repositoryRoot = ($repositoryRootOutput | Out-String).Trim()
    $stateRoot = Join-Path $repositoryRoot '.tollgate-local'
    $stagingDirectory = Join-Path $stateRoot 'staging'
    $pendingDirectory = Join-Path $stateRoot 'pending'
    $completedDirectory = Join-Path $stateRoot 'completed'
    $failedDirectory = Join-Path $stateRoot 'failed'

    foreach ($directory in @($stagingDirectory, $pendingDirectory, $completedDirectory, $failedDirectory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    $watcherPath = Join-Path $PSScriptRoot 'watch-tollgate.ps1'
    if (-not (Test-Path -LiteralPath $watcherPath -PathType Leaf)) {
        throw "Watcher not found: $watcherPath"
    }

    $watcherOutput = & $watcherPath -StageResult 2>&1
    $watcherExitCode = $LASTEXITCODE
    if ($watcherExitCode -ne 0) {
        $details = ($watcherOutput | Out-String).Trim()
        throw "Watcher failed with exit code ${watcherExitCode}: $details"
    }

    $stagingFile =
        Get-ChildItem -LiteralPath $stagingDirectory -Filter '*.json' -File |
        Sort-Object -Property LastWriteTimeUtc, Name |
        Select-Object -First 1

    if ($null -eq $stagingFile) {
        Write-Output 'NO_NEW_TOLLGATE'
        exit 0
    }

    $envelope = Get-Content -LiteralPath $stagingFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-TaskEnvelope -Envelope $envelope

    $commentId = [long]$envelope.comment_id
    $fileName = "$commentId.json"
    $pendingFile = Join-Path $pendingDirectory $fileName
    $completedFile = Join-Path $completedDirectory $fileName
    $failedFile = Join-Path $failedDirectory $fileName

    $existingTask = @($pendingFile, $completedFile, $failedFile) | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1

    if ($null -ne $existingTask) {
        Remove-Item -LiteralPath $stagingFile.FullName -Force
        Write-Output "TOLLGATE_TASK_ALREADY_EXISTS: $commentId"
        exit 0
    }

    Move-Item -LiteralPath $stagingFile.FullName -Destination $pendingFile

    Write-Output '[TOLLGATE_TASK_PREPARED]'
    Write-Output "comment_id: $commentId"
    Write-Output "task_file: $pendingFile"
    Write-Output "author: $trustedUser"
} catch {
    Fail-Prepare -Message $_.Exception.Message
}
