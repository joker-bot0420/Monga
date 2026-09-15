Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tests=$PSScriptRoot;$bridge=Split-Path $tests -Parent;$repository=Split-Path (Split-Path $bridge -Parent) -Parent
$common=Join-Path $bridge 'Tollgate.HistoricalRecovery.ps1';$settlement=Join-Path $bridge 'settle-tollgate-history.ps1';$reporter=Join-Path $bridge 'report-tollgate-result.ps1'
$suite=Join-Path $tests 'state/cross-worktree-production-state'
$utf8=New-Object Text.UTF8Encoding($false,$true);$id=5563219043L
. $common
function Assert-Throws([scriptblock]$Action,[string]$Pattern,[string]$Name){try{&$Action;throw "Expected rejection: $Name"}catch{if($_.Exception.Message-eq"Expected rejection: $Name"){throw};if($_.Exception.Message-notmatch$Pattern){throw "Unexpected rejection for ${Name}: $($_.Exception.Message)"}}}
function Invoke-Script([string]$Path,[string[]]$Arguments){$saved=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path @Arguments 2>&1;return [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=(@($output)-join"`n")}}finally{$ErrorActionPreference=$saved}}
function New-LocalRepository([string]$Path,[string]$Origin){[void][IO.Directory]::CreateDirectory($Path);&git -C $Path init --quiet;if($LASTEXITCODE-ne0){throw "git init failed: $Path"};&git -C $Path remote add origin $Origin;if($LASTEXITCODE-ne0){throw "git remote add failed: $Path"}}
function Write-Json([string]$Path,[object]$Value){[void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent));[IO.File]::WriteAllBytes($Path,$utf8.GetBytes(($Value|ConvertTo-Json -Depth 30)))}
function Get-Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function New-EvidenceFixture([string]$Root){
 $envelope=[ordered]@{schema_version=1;repository='joker-bot0420/Monga';pr_number=23;comment_id=$id;author='joker-bot0420';created_at='2026-09-07T00:05:03Z';marker='[TOLLGATE_APPROVED]';body='[TOLLGATE_APPROVED] TG-AUTO-02-EXT cross-worktree fixture';status='pending'}
 Write-Json (Join-Path $Root "pending\$id.json") $envelope
 1..5|%{$result=[ordered]@{status='CONTINUE';summary="iteration $_";requires_user=$false;evidence=@("e$_");changed_files=@();tests=@();next_action="next $_"};Write-Json (Join-Path $Root "runtime\$id\iteration-$_\codex-result.json") $result}
 $manifest=[ordered]@{pending_sha256=Get-Sha (Join-Path $Root "pending\$id.json");iteration_sha256=@(1..5|%{Get-Sha (Join-Path $Root "runtime\$id\iteration-$_\codex-result.json")});approval=[ordered]@{id=$id;author='joker-bot0420';created_at='2026-09-07T00:05:03Z';body_sha256=Get-RecoverySha256 $utf8.GetBytes($envelope.body)};checkpoint=[ordered]@{id=5566069227L;author='joker-bot0420';created_at='2026-09-07T06:31:25Z';body_sha256=('f'*64)}}
 Write-Json (Join-Path $Root 'evidence-manifest.json') $manifest
}
function Get-StateSnapshot([string]$Root){@((Get-ChildItem $Root -Recurse -Force|Sort-Object FullName|%{if($_.PSIsContainer){"D|$($_.FullName.Substring($Root.Length))"}else{"F|$($_.FullName.Substring($Root.Length))|$($_.Length)|$(Get-Sha $_.FullName)"}}))}
function Assert-SettlementRejectsWithoutDelta([string]$Root,[string]$Name){$before=@(Get-StateSnapshot $Root);$r=Invoke-Script $settlement @('-Apply','-Synthetic','-StateRoot',$Root,'-EvidenceManifestPath',(Join-Path $Root 'evidence-manifest.json'));if($r.ExitCode-eq0){throw "Invalid evidence was accepted: $Name"};$after=@(Get-StateSnapshot $Root);if(@(Compare-Object $before $after).Count){throw "Invalid evidence created filesystem artifacts: $Name"}}
try{
 if(Test-Path $suite){Remove-Item $suite -Recurse -Force};[void][IO.Directory]::CreateDirectory($suite)
 $candidate=Join-Path $suite 'CandidateRepo';$owner=Join-Path $suite 'StateOwnerRepo'
 New-LocalRepository $candidate 'https://github.com/joker-bot0420/Monga.git';New-LocalRepository $owner 'git@github.com:joker-bot0420/Monga.git'
 $state=Join-Path $owner '.tollgate-local';[void][IO.Directory]::CreateDirectory($state)
 $context=Get-HistoricalProductionStateContext $candidate $state 'joker-bot0420/Monga'
 if($context.CandidateRepositoryRoot-eq$context.StateOwnerRepositoryRoot-or$context.ProductionStateRoot-ne[IO.Path]::GetFullPath($state).TrimEnd('\')){throw 'Cross-worktree context was not preserved.'}
 foreach($url in @('https://github.com/joker-bot0420/Monga.git','https://github.com/joker-bot0420/Monga','git@github.com:joker-bot0420/Monga.git','ssh://git@github.com/joker-bot0420/Monga.git')){if((ConvertTo-HistoricalRepositoryIdentity $url)-cne'joker-bot0420/Monga'){throw"Identity normalization failed: $url"}}
 Assert-Throws {ConvertTo-HistoricalRepositoryIdentity 'http://github.com/joker-bot0420/Monga.git'} 'not a supported GitHub' 'plain HTTP origin'
 Assert-Throws {Get-HistoricalProductionStateContext $candidate '.tollgate-local' 'joker-bot0420/Monga'} 'absolute path' 'relative root'
 $wrong=Join-Path $owner 'state';[void][IO.Directory]::CreateDirectory($wrong);Assert-Throws {Get-HistoricalProductionStateContext $candidate $wrong 'joker-bot0420/Monga'} 'basename' 'basename'
 $nested=Join-Path $owner 'nested/.tollgate-local';[void][IO.Directory]::CreateDirectory($nested);Assert-Throws {Get-HistoricalProductionStateContext $candidate $nested 'joker-bot0420/Monga'} 'Git top-level' 'nested root'
 &git -C $owner remote set-url origin 'https://github.com/other/Other.git';Assert-Throws {Get-HistoricalProductionStateContext $candidate $state 'joker-bot0420/Monga'} 'identity is invalid' 'owner identity'; &git -C $owner remote set-url origin 'https://github.com/joker-bot0420/Monga.git'
 &git -C $candidate remote set-url origin 'https://github.com/other/Other.git';Assert-Throws {Get-HistoricalProductionStateContext $candidate $state 'joker-bot0420/Monga'} 'identity is invalid' 'candidate identity'; &git -C $candidate remote set-url origin 'https://github.com/joker-bot0420/Monga.git'
 Assert-Throws {Get-HistoricalProductionStateContext $candidate $state 'joker-bot0420/Other'} 'identity is invalid' 'expected identity'
 $before=@(git status --short);$r=Invoke-Script $settlement @('-Apply');if($r.ExitCode-eq0-or$r.Output-notmatch'ProductionStateRoot'){throw 'Settlement did not fail closed.'};$r=Invoke-Script $reporter @('-HistoricalRecovery','-DryRun');if($r.ExitCode-eq0-or$r.Output-notmatch'ProductionStateRoot'){throw 'Reporter did not fail closed.'};if(@(Compare-Object $before @(git status --short)).Count){throw 'Missing-root rejection changed repository state.'}
 $r=Invoke-Script $settlement @('-Apply','-Synthetic','-StateRoot',$state,'-EvidenceManifestPath',(Join-Path $state 'manifest.json'),'-ProductionStateRoot',$state);if($r.ExitCode-eq0-or$r.Output-notmatch'parameter set'){throw 'Synthetic/production collision was accepted.'}
 $r=Invoke-Script $reporter @('-DryRun','-ProductionStateRoot',$state);if($r.ExitCode-eq0-or$r.Output-notmatch'historical-recovery-only'){throw 'Normal reporter accepted production root.'}
 $r=Invoke-Script $reporter @('-HistoricalRecovery','-DryRun','-ProductionStateRoot',$state);if($r.ExitCode-eq0){throw 'Missing historical evidence was accepted.'}

 $candidateFailed=Join-Path $candidate 'failed';[void][IO.Directory]::CreateDirectory($candidateFailed);$candidateResult=Join-Path $candidateFailed '5563219043.json';[IO.File]::WriteAllText($candidateResult,'{}')
 $r=Invoke-Script $reporter @('-HistoricalRecovery','-DryRun','-ProductionStateRoot',$state,'-ResultFile',$candidateResult);if($r.ExitCode-eq0-or$r.Output-notmatch'direct JSON child'){throw 'Historical reporter accepted a candidate-local ResultFile.'}

 $realState=Join-Path $owner '.real-state';Move-Item $state $realState
 [void](New-Item -ItemType Junction -Path $state -Target $realState)
 Assert-Throws {Get-HistoricalProductionStateContext $candidate $state 'joker-bot0420/Monga'} 'Reparse points are not permitted' 'state-root junction'
 Remove-Item $state -Force;Move-Item $realState $state
 $outside=Join-Path $owner 'outside';[void][IO.Directory]::CreateDirectory($outside);$lifecycle=Join-Path $state 'runtime';[void](New-Item -ItemType Junction -Path $lifecycle -Target $outside)
 Assert-Throws {Assert-HistoricalNoReparsePath $owner $state (Join-Path $lifecycle '5563219043')} 'Reparse points are not permitted' 'lifecycle junction'
 Remove-Item $lifecycle -Force

 $valid=Join-Path $owner '.tollgate-local';New-EvidenceFixture $valid
 $r=Invoke-Script $settlement @('-Apply','-Synthetic','-StateRoot',$valid,'-EvidenceManifestPath',(Join-Path $valid 'evidence-manifest.json'));if($r.ExitCode-ne0){throw "Synthetic settlement failed: $($r.Output)"}
 $terminalPath=Join-Path $valid "failed\$id.json";$terminal=Get-Content $terminalPath -Raw -Encoding utf8|ConvertFrom-Json;$manifest=Get-Content (Join-Path $valid 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
 Assert-HistoricalRecoveryEvidenceArtifacts -Record $terminal -TerminalPath $terminalPath -StateRoot $valid -StateOwnerRepositoryRoot $owner -Manifest $manifest
 Assert-Throws {Assert-HistoricalRecoveryEvidenceArtifacts -Record $terminal -TerminalPath $terminalPath -StateRoot $valid -StateOwnerRepositoryRoot $candidate -Manifest $manifest} 'escapes its trusted anchor' 'candidate anchor regression'

 foreach($case in @('missing','wrong-pending','wrong-runtime','wrong-approval')){
  $invalid=Join-Path $suite "invalid-$case";[void][IO.Directory]::CreateDirectory($invalid);New-EvidenceFixture $invalid
  if($case-eq'missing'){Remove-Item (Join-Path $invalid "pending\$id.json") -Force}
  elseif($case-eq'wrong-pending'){[IO.File]::AppendAllText((Join-Path $invalid "pending\$id.json"),'x')}
  elseif($case-eq'wrong-runtime'){[IO.File]::AppendAllText((Join-Path $invalid "runtime\$id\iteration-3\codex-result.json"),'x')}
  else{$pendingPath=Join-Path $invalid "pending\$id.json";$value=Get-Content $pendingPath -Raw -Encoding utf8|ConvertFrom-Json;$value.author='other';Write-Json $pendingPath $value;$m=Get-Content (Join-Path $invalid 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json;$m.pending_sha256=Get-Sha $pendingPath;Write-Json (Join-Path $invalid 'evidence-manifest.json') $m}
  Assert-SettlementRejectsWithoutDelta $invalid $case
 }
 $settlementSource=Get-Content $settlement -Raw
 if(([regex]::Matches($settlementSource,'Get-ValidatedEvidence \$state \$trustedAnchor \$manifest')).Count-lt3-or$settlementSource.IndexOf('$preLockEvidence=Get-ValidatedEvidence')-gt$settlementSource.IndexOf('Initialize-HistoricalTrustedDirectory')){throw 'Shared pre-lock/post-lock evidence validation order regressed.'}
 Write-Output 'CROSS_WORKTREE_PRODUCTION_STATE_TEST_OK'
}finally{if(Test-Path $suite){Remove-Item $suite -Recurse -Force}}
