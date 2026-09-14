[CmdletBinding(DefaultParameterSetName = 'DryRun')]
param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$EvidenceManifestPath,
    [Parameter(Mandatory = $true)][string]$ResultFile,
    [Parameter(Mandatory = $true)][string]$ExitCodeFile,
    [Parameter(ParameterSetName = 'DryRun')][switch]$DryRun,
    [Parameter(Mandatory = $true, ParameterSetName = 'MockPublish')][switch]$MockPublish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$bridge = Split-Path $PSScriptRoot -Parent
$trustedAnchor = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'state')).TrimEnd('\')
. (Join-Path $bridge 'Tollgate.HistoricalRecovery.ps1')
. (Join-Path (Split-Path $bridge -Parent) 'tollgate-orchestrator/Orchestrator.Lock.ps1')

$trustedExitCodeFile = $null
try {
    $root = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
    Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $root
    foreach ($path in @($EvidenceManifestPath, $ResultFile, $ExitCodeFile)) {
        Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $path
    }
    Initialize-HistoricalTrustedDirectory -TrustedAnchor $trustedAnchor -Root $root -Directory (Split-Path -Parent $ExitCodeFile)
    Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $ExitCodeFile
    $trustedExitCodeFile = [IO.Path]::GetFullPath($ExitCodeFile)
    $manifest = Get-Content -LiteralPath $EvidenceManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $record = Get-Content -LiteralPath $ResultFile -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-HistoricalRecoveryEvidenceArtifactsAgainstManifest -Record $record -TerminalPath $ResultFile `
        -StateRoot $root -TrustedAnchor $trustedAnchor -Manifest $manifest

    $terminalSha = Get-RecoverySha256 ([IO.File]::ReadAllBytes($ResultFile))
    $settlementKey = Get-HistoricalSettlementKey $terminalSha
    $body = "[STOP_REQUIRED]`nSettlement key: $settlementKey"
    if ($MockPublish) {
        $lockPath = Join-Path $root "orchestrator/task-$([long]$record.comment_id).lock"
        Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $lockPath
        [void][IO.Directory]::CreateDirectory((Split-Path $lockPath -Parent))
        Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $lockPath
        $lock = Enter-HistoricalReporterTaskLock $lockPath
        try {
            $reported = Join-Path $root "reported/$([long]$record.comment_id).json"
            Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $reported
            if (Test-Path -LiteralPath $reported -PathType Leaf) {
                Write-Output "TOLLGATE_RESULT_ALREADY_REPORTED: $([long]$record.comment_id)"
                Write-HistoricalBytesAtomically -Bytes ([Text.Encoding]::ASCII.GetBytes('0')) -Destination $trustedExitCodeFile `
                    -TrustedAnchor $trustedAnchor -Root $root -RefuseOverwrite
                exit 0
            }
            Initialize-HistoricalTrustedDirectory -TrustedAnchor $trustedAnchor -Root $root -Directory (Split-Path $reported -Parent)
            $createCount = Join-Path $root 'mock-create-count.txt'
            Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $createCount
            [IO.File]::AppendAllText($createCount, "1`n")
            $value = [ordered]@{approval_comment_id=[long]$record.comment_id;terminal_status='STOP_REQUIRED';settlement_key=$settlementKey;rendered_comment_sha256=(Get-RecoverySha256 ([Text.UTF8Encoding]::new($false,$true).GetBytes($body)))}
            $bytes = [Text.UTF8Encoding]::new($false,$true).GetBytes(($value|ConvertTo-Json -Depth 10))
            Write-HistoricalBytesAtomically -Bytes $bytes -Destination $reported -TrustedAnchor $trustedAnchor -Root $root -RefuseOverwrite
        } finally { $lock.Dispose() }
    }
    Write-Output '[TOLLGATE_REPORT_READY]'
    Write-HistoricalBytesAtomically -Bytes ([Text.Encoding]::ASCII.GetBytes('0')) -Destination $trustedExitCodeFile `
        -TrustedAnchor $trustedAnchor -Root $root -RefuseOverwrite
} catch {
    [Console]::Error.WriteLine("HISTORICAL_REPORTER_FIXTURE_ERROR: $($_.Exception.Message)")
    if ($null -ne $trustedExitCodeFile) {
        try {
            Write-HistoricalBytesAtomically -Bytes ([Text.Encoding]::ASCII.GetBytes('1')) -Destination $trustedExitCodeFile `
                -TrustedAnchor $trustedAnchor -Root $root -RefuseOverwrite
        } catch {
            [Console]::Error.WriteLine("HISTORICAL_REPORTER_FIXTURE_EXIT_EVIDENCE_ERROR: $($_.Exception.Message)")
        }
    }
    exit 1
}
