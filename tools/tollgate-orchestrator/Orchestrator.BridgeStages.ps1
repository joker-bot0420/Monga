Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Orchestrator.ExecutorEnvironment.ps1')

function ConvertTo-TollgateLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-TollgateBridgeStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Prepare','Executor','Reporter')][string]$Stage,
        [string]$InputFile,
        [string]$CodexExecutable,
        [string[]]$TrustedSearchRoots = @(),
        [string]$IsolationRoot,
        [ValidateRange(30,1800)][int]$TimeoutSeconds = 300
    )
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $state = Join-Path $repo '.tollgate-local'
    $parameters = @{}
    switch ($Stage) {
        Prepare {
            if ($InputFile) { throw 'Prepare does not accept an input file.' }
            $scriptName = 'prepare-tollgate-task.ps1'
        }
        Executor {
            $scriptName = 'run-tollgate-task.ps1'
            $directories = @('pending')
            $parameters = @{ RunPending = $true; TimeoutSeconds = $TimeoutSeconds }
        }
        Reporter {
            $scriptName = 'report-tollgate-result.ps1'
            $directories = @('completed','failed')
            $parameters = @{ Publish = $true }
        }
    }
    if ($Stage -ne 'Prepare') {
        $inputPath = Assert-TollgateLocalPath $InputFile
        $allowed = @($directories | ForEach-Object { Join-Path $state $_ })
        if ([IO.Path]::GetDirectoryName($inputPath) -notin $allowed -or
            [IO.Path]::GetExtension($inputPath) -cne '.json') {
            throw 'Stage input must be a direct JSON child of its bridge lifecycle directory.'
        }
        # Existence and envelope/SHA validation remain the bridge's responsibility.
        if ($Stage -eq 'Executor') { $parameters.TaskFile = $inputPath }
        else { $parameters.ResultFile = $inputPath }
    }
    if ($Stage -eq 'Executor') {
        $codex = Resolve-TollgateCodexExecutable -ExplicitPath $CodexExecutable -TrustedSearchRoots $TrustedSearchRoots
        $info = New-TollgateExecutorStartInfo -CodexExecutable $codex -RepositoryRoot $repo -IsolationRoot $IsolationRoot
    } else {
        # Trusted Windows host retains its environment only for GitHub-facing stages.
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $info.WorkingDirectory = $repo
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
    }
    $scriptPath = Join-Path (Join-Path $repo 'tools/tollgate-bridge') $scriptName
    $pairs = foreach ($key in @($parameters.Keys | Sort-Object)) {
        $value = $parameters[$key]
        $literal = if ($value -is [bool]) { '$true' } elseif ($value -is [int]) { [string]$value } else { ConvertTo-TollgateLiteral $value }
        (ConvertTo-TollgateLiteral $key) + '=' + $literal
    }
    # Only fixed code and quoted data enter the child; no task content is evaluated.
    $command = '$ErrorActionPreference = ''Stop''; $ProgressPreference = ''SilentlyContinue''; try { $p = @{' + ($pairs -join ';') + '}; & ' + (ConvertTo-TollgateLiteral $scriptPath) + ' @p; if (-not $?) { exit 1 }; exit 0 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }'
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    return $info
}

function Invoke-TollgateBridgeProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][Diagnostics.ProcessStartInfo]$StartInfo)
    # Output is inherited, so verbose bridge output cannot deadlock redirected pipes.
    $process = New-Object Diagnostics.Process
    try {
        $process.StartInfo = $StartInfo
        if (-not $process.Start()) { throw 'Bridge process did not start.' }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Bridge stage failed with exit code $($process.ExitCode)." }
        return [int]0
    } finally { $process.Dispose() }
}
