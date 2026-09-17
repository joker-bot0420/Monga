Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.ToString() -notlike '5.1.*') { throw 'Requires Windows PowerShell 5.1.' }

$sourceBridge = Split-Path $PSScriptRoot -Parent
$suite = Join-Path $PSScriptRoot "state\reported-historical-$([Guid]::NewGuid().ToString('N'))"
$root = Join-Path $suite 'repo'
$bridge = Join-Path $root 'tools/tollgate-bridge'
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$id = 9300000001L
$controlPr = 47

function Write-Json([string]$Path, [object]$Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes(($Value | ConvertTo-Json -Depth 20)))
}

function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-NormalReporter([string]$Reporter, [string]$Terminal, [string]$FakeBin, [string]$GhCount, [switch]$AutoDiscover) {
    $oldPath = $env:PATH
    $oldCount = $env:MONGA_FAKE_GH_COUNT
    try {
        $env:PATH = "$FakeBin;$oldPath"
        $env:MONGA_FAKE_GH_COUNT = $GhCount
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Reporter,'-Publish','-ControlPrNumber',[string]$controlPr)
            if (-not $AutoDiscover) { $arguments += @('-ResultFile',$Terminal) }
            $output = & powershell.exe @arguments 2>&1
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
    if ((@($mismatch.Output) -join "`n") -notmatch 'Terminal record changed after it was reported') { throw 'Historical hash mismatch failed for an unexpected reason.' }
    if (Test-Path -LiteralPath $ghCount) { throw 'Hash mismatch touched gh.' }
    if (Test-Path -LiteralPath (Join-Path $root ".tollgate-local/runtime/reporter/$id")) { throw 'Historical hash mismatch created reporter runtime artifacts.' }

    Remove-Item -LiteralPath $reported -Force
    $missing = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($missing.ExitCode -eq 0) { throw 'Unreported historical terminal was accepted in normal mode.' }
    if ((@($missing.Output) -join "`n") -notmatch 'Historical recovery records require explicit -HistoricalRecovery mode') { throw 'Unreported historical terminal failed for an unexpected reason.' }
    if (Test-Path -LiteralPath $ghCount) { throw 'Unreported historical rejection touched gh.' }
    if (Test-Path -LiteralPath (Join-Path $root ".tollgate-local/runtime/reporter/$id")) { throw 'Unreported historical rejection created reporter runtime artifacts.' }

    # A matching reported hash must never bypass structural validation.
    $record.final_result.status = 'TOLLGATE_REACHED'
    Write-Json $terminal $record
    Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=(Get-Sha256 $terminal)})
    $invalid = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($invalid.ExitCode -eq 0 -or (@($invalid.Output) -join "`n") -notmatch 'Final result status mismatch') { throw 'Reported historical terminal bypassed structural validation.' }
    $invalidAuto = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount -AutoDiscover
    if ($invalidAuto.ExitCode -eq 0 -or (@($invalidAuto.Output) -join "`n") -notmatch 'Final result status mismatch') { throw 'Auto-discovery bypassed reported historical structural validation.' }
    $record.final_result.status = 'STOP_REQUIRED'
    Write-Json $terminal $record
    Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=(Get-Sha256 $terminal)})

    # Retained normal terminals from the previous PR have the same no-op contract.
    $id = 9300000002L
    $terminal = Join-Path $root ".tollgate-local/completed/$id.json"
    $reported = Join-Path $root ".tollgate-local/reported/$id.json"
    $record.Remove('recovery')
    $record.comment_id = $id
    $record.original_approval.comment_id = $id
    $record.terminal_status = 'TOLLGATE_REACHED'
    $record.final_result.status = 'TOLLGATE_REACHED'
    $record.final_result.requires_user = $false
    Write-Json $terminal $record
    Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=(Get-Sha256 $terminal)})
    $normal = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($normal.ExitCode -ne 0 -or (@($normal.Output) -join "`n") -notmatch "TOLLGATE_RESULT_ALREADY_REPORTED: $id") { throw 'Already-reported previous-PR normal terminal did not return an idempotent no-op.' }
    $auto = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount -AutoDiscover
    if ($auto.ExitCode -ne 0 -or (@($auto.Output) -join "`n") -notmatch 'NO_UNREPORTED_TOLLGATE_RESULT') { throw 'Auto-discovery did not skip exact already-reported previous-PR terminals.' }

    Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=('0' * 64)})
    $normalMismatch = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($normalMismatch.ExitCode -eq 0 -or (@($normalMismatch.Output) -join "`n") -notmatch 'Terminal record changed after it was reported') { throw 'Normal terminal/report hash mismatch did not fail closed.' }

    Remove-Item -LiteralPath $reported -Force
    $unreportedNormal = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
    if ($unreportedNormal.ExitCode -eq 0 -or (@($unreportedNormal.Output) -join "`n") -notmatch 'Approval PR number does not match the configured control PR') { throw 'Unreported previous-PR normal terminal bypassed the live control PR check.' }

    foreach ($invalidKind in @('status','pr-number')) {
        $record.final_result.status = if ($invalidKind -eq 'status') { 'STOP_REQUIRED' } else { 'TOLLGATE_REACHED' }
        $record.original_approval.pr_number = if ($invalidKind -eq 'pr-number') { 0 } else { 23 }
        Write-Json $terminal $record
        Write-Json $reported ([ordered]@{schema_version=1;terminal_record_sha256=(Get-Sha256 $terminal)})
        $invalid = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount
        $expectedError = if ($invalidKind -eq 'status') { 'Final result status mismatch' } else { 'Approval PR number is invalid' }
        if ($invalid.ExitCode -eq 0 -or (@($invalid.Output) -join "`n") -notmatch $expectedError) { throw "Reported normal terminal bypassed structural validation: $invalidKind" }
        $invalidAuto = Invoke-NormalReporter (Join-Path $bridge 'report-tollgate-result.ps1') $terminal $fakeBin $ghCount -AutoDiscover
        if ($invalidAuto.ExitCode -eq 0 -or (@($invalidAuto.Output) -join "`n") -notmatch $expectedError) { throw "Auto-discovery bypassed reported normal structural validation: $invalidKind" }
    }
    if (Test-Path -LiteralPath $ghCount) { throw 'Compatibility or rejection path touched gh.' }
    if (Test-Path -LiteralPath (Join-Path $root '.tollgate-local/runtime/reporter')) { throw 'Compatibility or rejection path created reporter runtime artifacts.' }

    Write-Output 'PASS: ControlPrNumber 47 treats exact already-reported PR #23 historical and normal terminals as idempotent no-ops.'
    Write-Output 'PASS: historical hash mismatch and unreported recovery still fail closed before gh/runtime writes.'
    Write-Output 'PASS: old normal terminal hash mismatch and unreported control-PR mismatch fail closed before gh/runtime writes.'
    Write-Output 'PASS: matching reported hashes do not bypass historical/normal structural validation or positive PR-number validation.'
    Write-Output 'PASS: auto-discovery validates structure before skipping exact already-reported previous-PR terminals.'
} finally {
    if (Test-Path -LiteralPath $suite) { Remove-Item -LiteralPath $suite -Recurse -Force }
}
