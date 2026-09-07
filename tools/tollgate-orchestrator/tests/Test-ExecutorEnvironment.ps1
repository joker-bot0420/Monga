Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Orchestrator.ExecutorEnvironment.ps1')
$suite = Join-Path $PSScriptRoot ('state/environment-' + [guid]::NewGuid().ToString('N'))
$install = Join-Path $suite 'installation with spaces/version-a/bin'
[void][IO.Directory]::CreateDirectory($install)
$exe = Join-Path $install 'codex.exe'
[IO.File]::WriteAllText($exe, 'inert fixture; never execute')
function Assert-Fails([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected rejection.' }
}
if ((Resolve-TollgateCodexExecutable -TrustedSearchRoots (Join-Path $suite 'installation with spaces')) -ne $exe) { throw 'Nested discovery failed.' }
if ((Resolve-TollgateCodexExecutable -ExplicitPath $exe) -ne $exe) { throw 'Explicit discovery failed.' }
Assert-Fails { Resolve-TollgateCodexExecutable }
Assert-Fails { Resolve-TollgateCodexExecutable -ExplicitPath 'relative/codex.exe' }
Assert-Fails { Resolve-TollgateCodexExecutable -ExplicitPath '\\server\share\codex.exe' }
Assert-Fails { Resolve-TollgateCodexExecutable -ExplicitPath (Join-Path $suite 'missing.exe') }
$other = Join-Path $suite 'installation with spaces/version-b'
[void][IO.Directory]::CreateDirectory($other)
[IO.File]::WriteAllText((Join-Path $other 'codex.exe'), 'inert fixture')
Assert-Fails { Resolve-TollgateCodexExecutable -TrustedSearchRoots (Join-Path $suite 'installation with spaces') }
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$names = @('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN','HTTP_PROXY','CODEX_SANDBOX_NETWORK_DISABLED','GIT_CONFIG_COUNT','SSH_AUTH_SOCK','UNLISTED_SECRET')
$saved = @{}
$parentPath = $env:PATH
try {
    foreach ($name in $names) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, 'synthetic-secret', 'Process')
    }
    $info = New-TollgateExecutorStartInfo -CodexExecutable $exe -RepositoryRoot $repo -IsolationRoot $suite
    foreach ($name in $names) {
        if ($info.EnvironmentVariables.ContainsKey($name)) { throw 'Disallowed inherited variable.' }
    }
    if ($env:PATH -ne $parentPath -or -not $info.EnvironmentVariables['PATH'].StartsWith($install + ';')) { throw 'PATH isolation failed.' }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $probe = '$ErrorActionPreference = "Stop"; if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { exit 5 }; foreach ($n in @("GH_TOKEN","GITHUB_TOKEN","HTTP_PROXY","UNLISTED_SECRET","SSH_AUTH_SOCK")) { if ([Environment]::GetEnvironmentVariable($n)) { exit 6 } }; if (Test-Path -LiteralPath $env:GH_CONFIG_DIR) { exit 7 }; if ($env:GIT_CONFIG_GLOBAL -ne "NUL") { exit 8 }; "PASS child environment"'
    $probe = '$ProgressPreference = "SilentlyContinue"; ' + $probe
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
    $process = New-Object Diagnostics.Process
    try {
        $process.StartInfo = $info
        if (-not $process.Start()) { throw 'Probe did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { throw 'Probe timeout.' }
        if ($process.ExitCode -ne 0 -or $stdout.Result.Trim() -ne 'PASS child environment' -or $stderr.Result) { throw ('Child environment probe failed. Exit: ' + $process.ExitCode + '; stdout: ' + $stdout.Result + '; stderr: ' + $stderr.Result) }
    } finally { $process.Dispose() }
    Assert-Fails { New-TollgateExecutorStartInfo -CodexExecutable $exe -RepositoryRoot $suite -IsolationRoot $repo }
    [void][IO.Directory]::CreateDirectory((Join-Path $suite 'gh-unconfigured'))
    Assert-Fails { New-TollgateExecutorStartInfo -CodexExecutable $exe -RepositoryRoot $repo -IsolationRoot $suite }
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
Write-Output "PASS: discovery, ambiguity/missing/path rejection, child allowlist, parent PATH preservation, Windows PowerShell 5.1 probe. Fixtures: $suite"
