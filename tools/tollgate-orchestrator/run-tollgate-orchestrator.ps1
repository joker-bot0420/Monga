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
$repositoryRoot = [IO.Path]::GetFullPath((Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$trustedAnchor = if ($Synthetic) { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests/state')) } else { $repositoryRoot }
$fixturePrefix = $trustedAnchor.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar
if ($Synthetic -and -not $root.StartsWith($fixturePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Synthetic state must be beneath tools/tollgate-orchestrator/tests/state/.'
}
function Assert-NoOrchestratorReparsePath([string]$Anchor, [string]$Root, [string]$Path) {
    $anchorFull = [IO.Path]::GetFullPath($Anchor).TrimEnd('\')
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not ($rootFull -eq $anchorFull -or $rootFull.StartsWith($anchorFull + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Orchestrator state root escapes its trusted anchor.'
    }
    if (-not ($pathFull -eq $rootFull -or $pathFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Orchestrator path escapes the state root.'
    }
    $current = $pathFull
    while ($current -and $current.Length -ge $anchorFull.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not permitted in orchestrator state paths: $current"
            }
        }
        if ($current.Equals($anchorFull, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    if (-not $current -or -not $current.Equals($anchorFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Orchestrator path could not be traced to its trusted anchor.' }
}
Assert-NoOrchestratorReparsePath $trustedAnchor $root $root
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

$orchestratorLockPath = Join-Path $root 'orchestrator/orchestrator.lock'
Assert-NoOrchestratorReparsePath $trustedAnchor $root $orchestratorLockPath
[void][IO.Directory]::CreateDirectory((Split-Path $orchestratorLockPath -Parent))
Assert-NoOrchestratorReparsePath $trustedAnchor $root $orchestratorLockPath
$handle = Enter-TollgateOrchestratorLock -LockPath $orchestratorLockPath
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
