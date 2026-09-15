Set-StrictMode -Version Latest

function Assert-TollgateLocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { throw 'An absolute local drive path is required.' }
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Reparse points are not allowed in executor paths.'
            }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}

function Resolve-TollgateCodexExecutable {
    [CmdletBinding()]
    param([string]$ExplicitPath, [string[]]$TrustedSearchRoots = @())
    # Roots are supplied by the trusted operator, never approval/task contents.
    # Do not recurse through links or execute candidates to identify them.
    if ($ExplicitPath) {
        $candidate = Assert-TollgateLocalPath $ExplicitPath
        if ([IO.Path]::GetFileName($candidate) -ine 'codex.exe' -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw 'Explicit Codex path must identify an existing codex.exe.'
        }
        return $candidate
    }
    $found = @{}
    foreach ($root in $TrustedSearchRoots) {
        $directory = Assert-TollgateLocalPath $root
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'Trusted installation root is missing.' }
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        $queue.Enqueue($directory)
        while ($queue.Count -gt 0) {
            foreach ($item in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force -ErrorAction Stop)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
                elseif ($item.Name -ieq 'codex.exe') { $found[$item.FullName] = $true }
            }
        }
    }
    if ($found.Count -ne 1) { throw 'Discovery requires exactly one codex.exe; supply an explicit path if missing or ambiguous.' }
    return @($found.Keys)[0]
}

function New-TollgateExecutorStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CodexExecutable,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$IsolationRoot
    )
    $codex = Resolve-TollgateCodexExecutable -ExplicitPath $CodexExecutable
    $repo = Assert-TollgateLocalPath $RepositoryRoot
    $isolation = Assert-TollgateLocalPath $IsolationRoot
    if (-not $isolation.StartsWith($repo.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Isolation root must be inside the repository.'
    }
    if (-not (Test-Path -LiteralPath $isolation -PathType Container)) { throw 'Create an isolated runtime directory before building the child environment.' }
    $ghConfig = Join-Path $isolation 'gh-unconfigured'
    if (Test-Path -LiteralPath $ghConfig) { throw 'GitHub config isolation path must be absent.' }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.WorkingDirectory = $repo
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.EnvironmentVariables.Clear()
    # Allowlist excludes GH/GITHUB tokens, proxy variables, injected Git config,
    # SSH agents and inherited Codex sandbox/network overrides.
    foreach ($name in @('SystemRoot','WINDIR','COMSPEC','USERPROFILE','HOMEDRIVE','HOMEPATH','LOCALAPPDATA','APPDATA','TEMP','TMP')) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($value) { $info.EnvironmentVariables[$name] = $value }
    }
    $info.EnvironmentVariables['PATH'] = ([IO.Path]::GetDirectoryName($codex) + ';' + (Join-Path $env:SystemRoot 'System32') + ';' + (Split-Path $info.FileName -Parent))
    $info.EnvironmentVariables['GH_CONFIG_DIR'] = $ghConfig
    $info.EnvironmentVariables['GH_PROMPT_DISABLED'] = '1'
    $info.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
    $info.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = 'NUL'
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    # Caller supplies only trusted bridge arguments. This helper never starts a process.
    return $info
}
