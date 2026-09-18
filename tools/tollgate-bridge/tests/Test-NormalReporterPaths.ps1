Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceBridge = Split-Path $PSScriptRoot -Parent
$suite = Join-Path $PSScriptRoot "state\normal-reporter-$([Guid]::NewGuid().ToString('N'))"
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$controlPr = 47

function Write-Json([string]$Path, [object]$Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes(($Value | ConvertTo-Json -Depth 20)))
}

function New-Terminal([long]$Id, [string]$Status) {
    return [ordered]@{
        schema_version=1; comment_id=$Id
        original_approval=[ordered]@{schema_version=1;repository='joker-bot0420/Monga';pr_number=$controlPr;comment_id=$Id;author='joker-bot0420';created_at='2026-09-01T00:00:00Z';marker='[TOLLGATE_APPROVED]';body='normal reporter path fixture';status='pending'}
        terminal_status=$Status;iterations=1;finished_at='2026-09-01T00:01:00Z'
        final_result=[ordered]@{status=$Status;summary='fixture';requires_user=($Status -eq 'STOP_REQUIRED');evidence=@('fixture');changed_files=@();tests=@();next_action=''}
    }
}

function New-ReporterRepository([string]$Name, [string]$Directory, [long]$Id) {
    $root = Join-Path $suite $Name
    $bridge = Join-Path $root 'tools/tollgate-bridge'
    [void][IO.Directory]::CreateDirectory($bridge)
    Copy-Item (Join-Path $sourceBridge 'report-tollgate-result.ps1') $bridge
    Copy-Item (Join-Path $sourceBridge 'Tollgate.HistoricalRecovery.ps1') $bridge
    & git -C $root init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize isolated reporter repository.' }
    $terminal = Join-Path $root ".tollgate-local/$Directory/$Id.json"
    Write-Json $terminal (New-Terminal $Id $(if($Directory -eq 'completed'){'TOLLGATE_REACHED'}else{'STOP_REQUIRED'}))
    return [pscustomobject]@{Root=$root;Reporter=(Join-Path $bridge 'report-tollgate-result.ps1');Terminal=$terminal;Id=$Id}
}

function Install-FakeGh([string]$Root) {
    $bin = Join-Path $Root 'fake-bin';[void][IO.Directory]::CreateDirectory($bin)
    $driver = Join-Path $bin 'fake-gh.ps1'
    [IO.File]::WriteAllText($driver, @'
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$pr=[int]$env:MONGA_FAKE_CONTROL_PR
if($args[0]-eq'auth'){exit 0}
if($args[0]-eq'pr'-and$args[1]-eq'comment'){$bodyFile=$args[[Array]::IndexOf($args,'--body-file')+1];[IO.File]::Copy($bodyFile,$env:MONGA_FAKE_GH_BODY,$true);[IO.File]::AppendAllText($env:MONGA_FAKE_GH_COUNT,"1`n");Write-Output "https://github.com/joker-bot0420/Monga/pull/$pr#issuecomment-9900000001";exit 0}
if($args[0]-eq'api'){$endpoint=$args[$args.Count-1];if($endpoint-eq'user'){Write-Output '{"login":"joker-bot0420"}';exit 0};if($endpoint-eq"repos/joker-bot0420/Monga/pulls/$pr"){[ordered]@{number=$pr;state='open';merged_at=$null}|ConvertTo-Json -Compress;exit 0};if($endpoint-eq'repos/joker-bot0420/Monga/issues/comments/9900000001'){$body=[IO.File]::ReadAllText($env:MONGA_FAKE_GH_BODY,[Text.Encoding]::UTF8);[ordered]@{id=9900000001;html_url="https://github.com/joker-bot0420/Monga/pull/$pr#issuecomment-9900000001";issue_url="https://api.github.com/repos/joker-bot0420/Monga/issues/$pr";body=$body;user=@{login='joker-bot0420'}}|ConvertTo-Json -Compress;exit 0}}
exit 9
'@, $utf8)
    [IO.File]::WriteAllText((Join-Path $bin 'gh.cmd'), "@powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0fake-gh.ps1`" %*`r`n@exit /b %ERRORLEVEL%`r`n", [Text.Encoding]::ASCII)
    return $bin
}

function Invoke-Reporter([object]$Fixture, [switch]$Publish, [switch]$AutoDiscover, [string]$ResultFile) {
    $oldPath=$env:PATH;$oldBody=$env:MONGA_FAKE_GH_BODY;$oldCount=$env:MONGA_FAKE_GH_COUNT;$oldPr=$env:MONGA_FAKE_CONTROL_PR
    $body=Join-Path $Fixture.Root 'fake-published-body.txt';$count=Join-Path $Fixture.Root 'fake-publish-count.txt'
    try {
        $env:PATH="$(Install-FakeGh $Fixture.Root);$oldPath";$env:MONGA_FAKE_GH_BODY=$body;$env:MONGA_FAKE_GH_COUNT=$count;$env:MONGA_FAKE_CONTROL_PR=[string]$controlPr
        $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Fixture.Reporter,'-ControlPrNumber',[string]$controlPr)
        if($Publish){$arguments+='-Publish'}else{$arguments+='-DryRun'}
        if(-not$AutoDiscover){$arguments+=@('-ResultFile',$(if($ResultFile){$ResultFile}else{$Fixture.Terminal}))}
        $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$output=& powershell.exe @arguments 2>&1;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$saved}
        return [pscustomobject]@{ExitCode=$code;Output=@($output);CountFile=$count;BodyFile=$body}
    } finally {$env:PATH=$oldPath;$env:MONGA_FAKE_GH_BODY=$oldBody;$env:MONGA_FAKE_GH_COUNT=$oldCount;$env:MONGA_FAKE_CONTROL_PR=$oldPr}
}

try {
    $completed=New-ReporterRepository 'completed-valid' 'completed' 9200000001L
    $completedResult=Invoke-Reporter $completed -Publish
    if($completedResult.ExitCode-ne0-or@(Get-Content $completedResult.CountFile).Count-ne1-or-not(Test-Path (Join-Path $completed.Root '.tollgate-local/reported/9200000001.json'))){throw 'Valid normal completed publish fixture failed.'}
    $reportedRecord=Get-Content (Join-Path $completed.Root '.tollgate-local/reported/9200000001.json') -Raw|ConvertFrom-Json
    if([int]$reportedRecord.pr_number-ne$controlPr){throw 'Reported state did not preserve the parameterized control PR.'}
    $again=Invoke-Reporter $completed -Publish
    if($again.ExitCode-ne0-or@(Get-Content $completedResult.CountFile).Count-ne1-or(@($again.Output)-join"`n")-notmatch'TOLLGATE_RESULT_ALREADY_REPORTED'){throw 'Normal already-reported idempotency failed.'}

    $failed=New-ReporterRepository 'failed-valid' 'failed' 9200000002L
    $failedResult=Invoke-Reporter $failed -Publish
    if($failedResult.ExitCode-ne0-or@(Get-Content $failedResult.CountFile).Count-ne1-or-not(Test-Path (Join-Path $failed.Root '.tollgate-local/reported/9200000002.json'))){throw 'Valid normal failed publish fixture failed.'}

    $autoCompleted=New-ReporterRepository 'completed-auto' 'completed' 9200000003L
    if((Invoke-Reporter $autoCompleted -AutoDiscover).ExitCode-ne0){throw 'Normal completed auto-discovery failed.'}
    $autoFailed=New-ReporterRepository 'failed-auto' 'failed' 9200000004L
    if((Invoke-Reporter $autoFailed -AutoDiscover).ExitCode-ne0){throw 'Normal failed auto-discovery failed.'}

    $external=Join-Path $suite 'external.json';Write-Json $external (New-Terminal 9200000005L 'TOLLGATE_REACHED')
    $explicit=New-ReporterRepository 'external-explicit' 'completed' 9200000005L
    if((Invoke-Reporter $explicit -ResultFile $external).ExitCode-eq0){throw 'External explicit ResultFile was accepted.'}
    $lexical=Join-Path $explicit.Root '.tollgate-local-evil/completed/9200000005.json';Write-Json $lexical (New-Terminal 9200000005L 'TOLLGATE_REACHED')
    if((Invoke-Reporter $explicit -ResultFile $lexical).ExitCode-eq0){throw 'Lexical-prefix ResultFile escape was accepted.'}

    foreach($directory in @('completed','failed')){
        $fixture=New-ReporterRepository "$directory-junction" $directory 9200000006L
        Remove-Item -LiteralPath (Join-Path $fixture.Root ".tollgate-local/$directory") -Recurse -Force
        $outside=Join-Path $suite "$directory-junction-outside";[void][IO.Directory]::CreateDirectory($outside)
        Write-Json (Join-Path $outside '9200000006.json') (New-Terminal 9200000006L $(if($directory-eq'completed'){'TOLLGATE_REACHED'}else{'STOP_REQUIRED'}))
        & cmd.exe /c "mklink /J `"$(Join-Path $fixture.Root ".tollgate-local/$directory")`" `"$outside`"" *> $null
        if($LASTEXITCODE-ne0){Write-Output "SKIP: $directory junction unavailable";continue}
        $result=Invoke-Reporter $fixture -AutoDiscover
        if($result.ExitCode-eq0-or(Test-Path $result.CountFile)){throw "Normal reporter accepted $directory junction or published."}
    }

    $reported=New-ReporterRepository 'reported-junction' 'completed' 9200000007L
    $outsideReported=Join-Path $suite 'reported-junction-outside';[void][IO.Directory]::CreateDirectory($outsideReported)
    [void][IO.Directory]::CreateDirectory((Join-Path $reported.Root '.tollgate-local'))
    & cmd.exe /c "mklink /J `"$(Join-Path $reported.Root '.tollgate-local/reported')`" `"$outsideReported`"" *> $null
    if($LASTEXITCODE-eq0){$result=Invoke-Reporter $reported -Publish;if($result.ExitCode-eq0-or(Test-Path $result.CountFile)-or@(Get-ChildItem $outsideReported -Force).Count-ne0){throw 'Normal reporter accepted reported junction or performed an external action.'}}else{Write-Output 'SKIP: reported junction unavailable'}

    Write-Output 'PASS: parameterized normal completed/failed discovery, explicit lifecycle paths, mock publish and already-reported idempotency.'
    Write-Output 'PASS: completed/failed/reported junctions and external/lexical ResultFile paths fail closed before mock publish.'
} finally {
    if(Test-Path $suite){Remove-Item -LiteralPath $suite -Recurse -Force}
}
