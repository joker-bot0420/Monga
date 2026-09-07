[CmdletBinding(DefaultParameterSetName = 'Production')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][switch]$Synthetic,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][string]$StateRoot,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][scriptblock]$PrepareStage,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][scriptblock]$ExecutorStage,
    [Parameter(Mandatory = $true, ParameterSetName = 'Synthetic')][scriptblock]$ReporterStage,
    [Parameter(ParameterSetName = 'Production')][string]$CodexExecutable,
    [Parameter(ParameterSetName = 'Production')][string[]]$TrustedSearchRoots = @(),
    [Parameter(ParameterSetName = 'Production')][ValidateRange(30,1800)][int]$TimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Orchestrator.Lock.ps1')

if ($PSCmdlet.ParameterSetName -eq 'Synthetic' -and -not $Synthetic) { throw 'Synthetic switch must be enabled.' }
if (-not $Synthetic) {
    . (Join-Path $PSScriptRoot 'Orchestrator.BridgeStages.ps1')
    $StateRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.tollgate-local'
    $PrepareStage = { param($root, $file) Invoke-TollgateBridgeProcess (New-TollgateBridgeStage -Stage Prepare) }
    $ExecutorStage = { param($root, $file)
        Invoke-TollgateBridgeProcess (New-TollgateBridgeStage -Stage Executor -InputFile $file -CodexExecutable $CodexExecutable -TrustedSearchRoots $TrustedSearchRoots -IsolationRoot (Join-Path $root 'orchestrator') -TimeoutSeconds $TimeoutSeconds)
    }
    $ReporterStage = { param($root, $file) Invoke-TollgateBridgeProcess (New-TollgateBridgeStage -Stage Reporter -InputFile $file) }
}
$root = [IO.Path]::GetFullPath($StateRoot)
$fixturePrefix = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests/state')) + [IO.Path]::DirectorySeparatorChar
if ($Synthetic -and -not $root.StartsWith($fixturePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Synthetic state must be beneath tools/tollgate-orchestrator/tests/state/.'
}
# Reject junctions/symlinks so a fixture cannot redirect to the actual queue.
$ancestor = $root
while ($ancestor) {
    if (Test-Path -LiteralPath $ancestor) {
        if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Reparse points are not permitted in synthetic state paths.'
        }
    }
    $ancestor = [IO.Path]::GetDirectoryName($ancestor)
}
function Get-StageFiles([string]$Directory) {
    $path = Join-Path $root $Directory
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse state directory.' }
        foreach ($file in @(Get-ChildItem -LiteralPath $path -Filter '*.json' -File | Sort-Object Name)) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse state file.' }
            $file
        }
    }
}
function Invoke-Stage([scriptblock]$Stage, [string]$InputFile) {
    $result = @(& $Stage $root $InputFile)
    if ($result.Count -ne 1 -or $result[0] -isnot [int] -or $result[0] -ne 0) {
        throw 'Stage failed: expected exactly one integer exit code 0.'
    }
}

$handle = Enter-TollgateOrchestratorLock -LockPath (Join-Path $root 'orchestrator/orchestrator.lock')
try {
    # The real prepare stage already invokes watcher before staging approval.
    Invoke-Stage $PrepareStage ''
    $pending = @(Get-StageFiles 'pending')
    if ($pending.Count -gt 1) { throw 'Multiple pending tasks require explicit resolution.' }
    if ($pending.Count -eq 1) {
        foreach ($directory in @('completed', 'failed')) {
            if (Test-Path -LiteralPath (Join-Path (Join-Path $root $directory) $pending[0].Name)) {
                throw 'Pending and terminal records overlap; refusing duplicate execution.'
            }
        }
        Invoke-Stage $ExecutorStage $pending[0].FullName
    }
    # Reporter owns SHA validation and idempotency, including already-reported records.
    # No lifecycle record is written, moved, or removed by this routing layer.
    $terminals = @((Get-StageFiles 'completed'); (Get-StageFiles 'failed'))
    foreach ($terminal in $terminals) { Invoke-Stage $ReporterStage $terminal.FullName }
    [pscustomobject]@{ PendingInvoked = ($pending.Count -eq 1); TerminalInvocations = $terminals.Count }
} finally {
    $handle.Dispose()
}
