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

try {
    $root = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
    Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $root
    foreach ($path in @($EvidenceManifestPath, $ResultFile, $ExitCodeFile)) {
        Assert-HistoricalNoReparsePath -TrustedAnchor $trustedAnchor -Root $root -Path $path
    }
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
            if (Test-Path -LiteralPath $reported -PathType Leaf) {
                Write-Output "TOLLGATE_RESULT_ALREADY_REPORTED: $([long]$record.comment_id)"
                [IO.File]::WriteAllText($ExitCodeFile, '0', [Text.Encoding]::ASCII)
                exit 0
            }
            [void][IO.Directory]::CreateDirectory((Split-Path $reported -Parent))
            [IO.File]::AppendAllText((Join-Path $root 'mock-create-count.txt'), "1`n")
            $value = [ordered]@{approval_comment_id=[long]$record.comment_id;terminal_status='STOP_REQUIRED';settlement_key=$settlementKey;rendered_comment_sha256=(Get-RecoverySha256 ([Text.UTF8Encoding]::new($false,$true).GetBytes($body)))}
            $temp = "$reported.$([guid]::NewGuid().ToString('N')).tmp"
            [IO.File]::WriteAllText($temp, ($value|ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false,$true))
            [IO.File]::Move($temp,$reported)
        } finally { $lock.Dispose() }
    }
    Write-Output '[TOLLGATE_REPORT_READY]'
    [IO.File]::WriteAllText($ExitCodeFile, '0', [Text.Encoding]::ASCII)
} catch {
    [Console]::Error.WriteLine("HISTORICAL_REPORTER_FIXTURE_ERROR: $($_.Exception.Message)")
    [IO.File]::WriteAllText($ExitCodeFile, '1', [Text.Encoding]::ASCII)
    exit 1
}
