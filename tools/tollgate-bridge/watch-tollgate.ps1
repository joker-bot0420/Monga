[CmdletBinding()]
param(
    [switch]$StageResult
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = 'joker-bot0420/Monga'
$issueNumber = 23
$trustedUser = 'joker-bot0420'
$triggerMarker = '[TOLLGATE_APPROVED]'
$expectedIssueUrl = "https://api.github.com/repos/$repository/issues/$issueNumber"
$stateDirectoryName = '.tollgate-local'
$stateFileName = 'last-approved-comment.json'

function Fail-Watcher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [Console]::Error.WriteLine("TOLLGATE_WATCHER_ERROR: $Message")
    exit 1
}

function Invoke-GhJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

    try {
        $process = Start-Process `
            -FilePath 'gh' `
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

        return $json | ConvertFrom-Json
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProcessedCommentIds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StateFile
    )

    $processedIds = [System.Collections.Generic.HashSet[long]]::new()
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        return ,$processedIds
    }

    $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json

    if ($null -ne $state.PSObject.Properties['processed_comment_ids']) {
        foreach ($id in @($state.processed_comment_ids)) {
            [void]$processedIds.Add([long]$id)
        }
    }

    if ($null -ne $state.PSObject.Properties['last_approved_comment_id']) {
        [void]$processedIds.Add([long]$state.last_approved_comment_id)
    }

    return ,$processedIds
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)

    $temporaryFile = Join-Path $destinationDirectory ".$([System.IO.Path]::GetFileName($Destination)).$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryFile -Encoding utf8
        Move-Item -LiteralPath $temporaryFile -Destination $Destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }
}

function Add-StateDirectoryToLocalExclude {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $gitDirectoryOutput = & git -C $RepositoryRoot rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($gitDirectoryOutput | Out-String).Trim()
        throw "Unable to locate the Git directory: $details"
    }

    $gitDirectory = ($gitDirectoryOutput | Out-String).Trim()
    if (-not [System.IO.Path]::IsPathRooted($gitDirectory)) {
        $gitDirectory = Join-Path $RepositoryRoot $gitDirectory
    }

    $excludeFile = Join-Path $gitDirectory 'info\exclude'
    $excludeDirectory = Split-Path -Parent $excludeFile
    [void](New-Item -ItemType Directory -Path $excludeDirectory -Force)

    $excludeEntry = "$stateDirectoryName/"
    $existingEntries =
        if (Test-Path -LiteralPath $excludeFile -PathType Leaf) {
            @(Get-Content -LiteralPath $excludeFile)
        } else {
            @()
        }

    if ($existingEntries -notcontains $excludeEntry) {
        Add-Content -LiteralPath $excludeFile -Value $excludeEntry -Encoding utf8
    }
}

try {
    if ($null -eq (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) is not available on PATH.'
    }

    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub CLI authentication check failed. Run gh auth login and try again.'
    }

    $repositoryRootOutput = & git -C $PSScriptRoot rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($repositoryRootOutput | Out-String).Trim()
        throw "Unable to locate the repository root: $details"
    }

    $repositoryRoot = ($repositoryRootOutput | Out-String).Trim()
    $stateDirectory = Join-Path $repositoryRoot $stateDirectoryName
    $stateFile = Join-Path $stateDirectory $stateFileName
    $processedCommentIds = Get-ProcessedCommentIds -StateFile $stateFile

    $comments = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $perPage = 100

    do {
        $endpoint = "repos/$repository/issues/$issueNumber/comments?per_page=$perPage&page=$page"
        $pageResult = Invoke-GhJson -Endpoint $endpoint
        $pageComments = @(
            foreach ($item in @($pageResult)) {
                if ($item -is [System.Array]) {
                    foreach ($comment in $item) {
                        $comment
                    }
                }
                else {
                    $item
                }
            }
        )

        foreach ($comment in $pageComments) {
            $comments.Add($comment)
        }
        $page++
    } while ($pageComments.Count -eq $perPage)

    $candidate =
        $comments |
        Where-Object {
            $_.issue_url -eq $expectedIssueUrl -and
            $_.user.login -eq $trustedUser -and
            $_.user.type -ne 'Bot' -and
            ([string]$_.body).IndexOf($triggerMarker, [StringComparison]::Ordinal) -ge 0 -and
            -not $processedCommentIds.Contains([long]$_.id)
        } |
        Sort-Object -Property @{ Expression = { [DateTimeOffset]$_.created_at }; Descending = $true },
            @{ Expression = { [long]$_.id }; Descending = $true } |
        Select-Object -First 1

    if ($null -eq $candidate) {
        Write-Output 'NO_NEW_TOLLGATE'
        exit 0
    }

    [void]$processedCommentIds.Add([long]$candidate.id)
    Add-StateDirectoryToLocalExclude -RepositoryRoot $repositoryRoot
    [void](New-Item -ItemType Directory -Path $stateDirectory -Force)

    if ($StageResult) {
        $stagingDirectory = Join-Path $stateDirectory 'staging'
        $stagingFile = Join-Path $stagingDirectory "$([long]$candidate.id).json"

        if (-not (Test-Path -LiteralPath $stagingFile -PathType Leaf)) {
            $stagedEnvelope = [ordered]@{
                schema_version = 1
                repository = $repository
                pr_number = $issueNumber
                comment_id = [long]$candidate.id
                author = [string]$candidate.user.login
                created_at = ([DateTimeOffset]$candidate.created_at).ToUniversalTime().ToString('o')
                marker = $triggerMarker
                body = [string]$candidate.body
                status = 'pending'
            }

            Write-JsonAtomically -Value $stagedEnvelope -Destination $stagingFile
        }
    }

    $state = [ordered]@{
        repository = $repository
        issue_number = $issueNumber
        last_approved_comment_id = [long]$candidate.id
        processed_comment_ids = @($processedCommentIds | Sort-Object)
        updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    }

    Write-JsonAtomically -Value $state -Destination $stateFile

    Write-Output '[TOLLGATE_DETECTED]'
    Write-Output "comment_id: $($candidate.id)"
    Write-Output "author: $trustedUser"
    Write-Output "created_at: $($candidate.created_at)"
    Write-Output ''
    Write-Output ([string]$candidate.body)
} catch {
    Fail-Watcher -Message $_.Exception.Message
}
