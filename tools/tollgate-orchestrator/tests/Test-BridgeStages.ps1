Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Orchestrator.BridgeStages.ps1')
if ($PSVersionTable.PSVersion.ToString() -notlike '5.1.*') { throw 'Run with Windows PowerShell 5.1.' }
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$bridge = Join-Path $repo 'tools/tollgate-bridge'
$before = @(Get-ChildItem -LiteralPath $bridge -File | Get-FileHash -Algorithm SHA256)
$suite = Join-Path $PSScriptRoot ('state/adapters-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($suite)
$exe = Join-Path $suite 'codex.exe'
[IO.File]::WriteAllText($exe, 'inert fixture; never execute')
function Assert-Fails([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected rejection.' }
}
function Read-StageCommand($Info) {
    [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($Info.Arguments -split ' ')[-1]))
}
$prepare = New-TollgateBridgeStage -Stage Prepare
$pending = Join-Path $repo ".tollgate-local/pending/task 'quoted'; dollar`$.json"
$executor = New-TollgateBridgeStage -Stage Executor -InputFile $pending -CodexExecutable $exe -IsolationRoot $suite -TimeoutSeconds 90
$reporter = New-TollgateBridgeStage -Stage Reporter -InputFile (Join-Path $repo '.tollgate-local/completed/result.json')
$failedReporter = New-TollgateBridgeStage -Stage Reporter -InputFile (Join-Path $repo '.tollgate-local/failed/result.json')
foreach ($info in @($prepare,$executor,$reporter,$failedReporter)) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput((Read-StageCommand $info), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Generated command parse failed.' }
    # Extract literal parameter values without executing the bridge command.
    $table = $ast.Find({ param($node) $node -is [Management.Automation.Language.HashtableAst] }, $true).SafeGetValue()
    if ($info -eq $executor) {
        if ($table.TaskFile -cne $pending -or -not $table.RunPending -or $table.TimeoutSeconds -ne 90) { throw 'Executor arguments changed.' }
        if ($info.EnvironmentVariables.ContainsKey('GH_TOKEN')) { throw 'Executor inherited token.' }
    } elseif ($info -eq $prepare) {
        if ($table.Count -ne 0 -or (Read-StageCommand $info) -notlike '*prepare-tollgate-task.ps1*') { throw 'Prepare contract failed.' }
    } else {
        if (-not $table.Publish -or $table.ResultFile -notlike '*.json') { throw 'Reporter contract failed.' }
    }
}
Assert-Fails { New-TollgateBridgeStage -Stage Prepare -InputFile $pending }
Assert-Fails { New-TollgateBridgeStage -Stage Executor -InputFile (Join-Path $suite 'task.json') }
Assert-Fails { New-TollgateBridgeStage -Stage Reporter -InputFile $pending }
Assert-Fails { New-TollgateBridgeStage -Stage Executor -InputFile $pending -IsolationRoot $suite }
# Exercise the process runner with harmless child commands, never a bridge or Codex.
function New-Probe([string]$Code) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $prepare.FileName
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    return $info
}
if ((Invoke-TollgateBridgeProcess (New-Probe 'exit 0')) -ne 0) { throw 'Success propagation failed.' }
Assert-Fails { Invoke-TollgateBridgeProcess (New-Probe 'exit 17') }
Assert-Fails { Invoke-TollgateBridgeProcess (New-Probe 'throw "synthetic failure"') }
$missing = New-Probe 'exit 0'
$missing.FileName = Join-Path $suite 'missing.exe'
Assert-Fails { Invoke-TollgateBridgeProcess $missing }
$after = @(Get-ChildItem -LiteralPath $bridge -File | Get-FileHash -Algorithm SHA256)
if (Compare-Object $before $after -Property Path,Hash) { throw 'Protected bridge bytes changed.' }
Write-Output "PASS: stage argument transport, routing constraints, discovery failure, child exit/start failure, protected bridge hashes; fixture $suite"
