Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.ToString() -notlike '5.1.*') { throw 'Requires Windows PowerShell 5.1.' }

$sourceBridge = Split-Path $PSScriptRoot -Parent
$suite = Join-Path $PSScriptRoot "state\reported-historical-$([Guid]::NewGuid().ToString('N'))"
$root = Join-Path $suite 'repo'
$bridge = Join-Path $root 'tools/tollgate-bridge'
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$id = 9300000001L

function Write-Json([string]$Path, [object]$Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes(($Value | ConvertTo-Json -Depth 20)))
}

function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-NormalReporter([string]$Reporter, [string]$Terminal, [string]$FakeBin, [string]$GhCount) {
    $oldPath = $env:PATH
    $oldCount = $env:MONGA_FAKE_GH_COUNT
    try {
        $env:PATH = "$FakeBin;$oldPath"
        $env:MONGA_FAKE_GH_COUNT = $GhCount
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Reporter -Publish -ResultFile $Terminal 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $saved }
        return [pscustomobject]@{ ExitCode=$code; Output=@($output) }
    } finally {
        $env:PATH = $oldPath
        $env:MONGA_FAKE_GH_COUNT = $oldCount
    }
}

try {
    [void][IO.Directory]::CreateDirectory($bridge)
    foreach ($name in @('report-tollgate-result.ps1','Tollgate.HistoricalRecovery.ps1')) {
        Copy-Item -LiteralPath (Join-Path $sourceBridge $name) -Destination $bridge
    }
    & git -C $root init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize isolated reporter repository.' }

    $terminal = Join-Path $root ".tollgate-local/failed/$id.json"
    $record = [ordered]@{
        schema_version=1; comment_id=$id; terminal_status='STOP_REQUIRED'; iterations=5; finished_at='2026-09-16T06:25:13Z'
        original_approval=[ordered]@{schema_version=1;repository='joker-bot0420/Monga';pr_number=23;comment_id=$id;author='joker-bot0420';created_at='2026-09-07T00:05:03Z';marker='[TOLLGATE_APPROVED]';body='historical compatibility fixture';status='pending'}
        final_result=[ordered]@{status='STOP_REQUIRED';summary='fixture recovery';requires_user=$true;evidence=@();changed_files=@();tests=@();next_action='new approval'}
        recovery=[ordered]@{schema_version=1;tollgate_id='FIXTURE-HISTORICAL';settlement_kind='historical_recovery'}
    }
    Write-Json $terminal $record
    $terminalHash = Get-Sha256 $terminal

    $reported = Join-Path $root ".tollgate-local/reported/$id.json"
    Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=$terminalHash})

    $fakeBin = Join-Path $suite 'fake-bin'
    [void][IO.Directory]::CreateDirectory($fakeBin)
    $ghCount = Join-Path $suite 'gh-called.txt'
    [IO.File]::WriteAllText((Join-Path $fakeBin 'gh.cmd'), "@echo called>>`"%MONGA_FAKE_GH_COUNT%`"`r`n@exit /b 99`r`n", [Text.Encoding]::ASCII)

    $result = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($result.ExitCode -ne 0) { throw "Already-reported historical terminal failed normal reporter: $(@($result.Output) -join ' | ')" }
    if ((@($result.Output) -join "`n") -notmatch "TOLLGATE_RESULT_ALREADY_REPORTED: $id") { throw 'Already-reported historical terminal did not return idempotent no-op.' }
    if (Test-Path -LiteralPath $ghCount) { throw 'Already-reported historical no-op touched gh.' }
    if (Test-Path -LiteralPath (Join-Path $root ".tollgate-local/runtime/reporter/$id")) { throw 'Already-reported historical no-op created reporter runtime artifacts.' }

    Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=('0' * 64)})
    $mismatch = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($mismatch.ExitCode -eq 0) { throw 'Historical terminal/report hash mismatch was accepted.' }
    if (Test-Path -LiteralPath $ghCount) { throw 'Hash mismatch touched gh.' }

    Remove-Item -LiteralPath $reported -Force
    $missing = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($missing.ExitCode -eq 0) { throw 'Unreported historical terminal was accepted in normal mode.' }
    if ((@($missing.Output) -join "`n") -notmatch 'Historical recovery records require explicit -HistoricalRecovery mode') { throw 'Unreported historical terminal failed for an unexpected reason.' }
    if (Test-Path -LiteralPath $ghCount) { throw 'Unreported historical rejection touched gh.' }

    Write-Output 'PASS: normal reporter treats an exact already-reported historical terminal as an idempotent no-op.'
    Write-Output 'PASS: historical hash mismatch and unreported recovery still fail closed before gh/runtime writes.'
} finally {
    if (Test-Path -LiteralPath $suite) { Remove-Item -LiteralPath $suite -Recurse -Force }
}
