Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.ToString() -notlike '5.1.*') { throw 'Requires Windows PowerShell 5.1.' }
$source = Split-Path $PSScriptRoot -Parent
. (Join-Path $source 'Orchestrator.ExecutorEnvironment.ps1')
$suite = Assert-TollgateLocalPath (Join-Path $PSScriptRoot ('state/scheduler-' + [guid]::NewGuid().ToString('N')))
$fixture = Join-Path $suite "repo with 'quotes'; dollar$/tools/tollgate-orchestrator"
[void][IO.Directory]::CreateDirectory($fixture)
foreach ($name in @('Orchestrator.Scheduler.ps1','Orchestrator.ExecutorEnvironment.ps1','install-tollgate-scheduler.ps1','uninstall-tollgate-scheduler.ps1')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $fixture
    if ((Get-FileHash -LiteralPath (Join-Path $source $name)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $fixture $name)).Hash) { throw 'Fixture copy differs.' }
}
[IO.File]::WriteAllText((Join-Path $fixture 'run-tollgate-orchestrator.ps1'), 'throw "Scheduler tests must never run an orchestrator."')
$exe = Join-Path $suite 'codex.exe'
[IO.File]::WriteAllText($exe, 'Inert; never execute.')
$global:connections = 0
$global:registrations = 0
$global:removals = 0
$global:existing = $null
$global:lookupFailure = $false
$global:race = $false
$global:registrationFailure = $false
$global:removalFailure = $false
$global:capturedXml = ''
$global:folder = [pscustomobject]@{}
$global:folder | Add-Member ScriptMethod GetTask {
    param($name)
    if ($name -cne $global:identity.Name) { throw 'Non-exact lookup.' }
    if ($global:lookupFailure) { throw 'Injected access denied.' }
    if ($null -eq $global:existing) { throw [IO.FileNotFoundException]::new('Absent fixture task') }
    return $global:existing
}
$global:folder | Add-Member ScriptMethod RegisterTask {
    param($name,$xml,$flags,$sid,$password,$logon,$sddl)
    if ($name -cne $global:identity.Name -or $flags -ne 2 -or $sid -cne $global:identity.Sid -or $null -ne $password -or $logon -ne 3 -or $null -ne $sddl) { throw 'Unsafe registration parameters.' }
    if ($global:race -or $global:registrationFailure) { throw 'Injected create failure; no overwrite.' }
    $global:registrations++
    $global:capturedXml = $xml
    $global:existing = [pscustomobject]@{ Path = '\' + $name; Xml = $xml }
}
$global:folder | Add-Member ScriptMethod DeleteTask {
    param($name,$flags)
    if ($name -cne $global:identity.Name -or $flags -ne 0) { throw 'Non-exact removal.' }
    if ($global:removalFailure) { throw 'Injected removal failure.' }
    $global:removals++
    $global:existing = $null
}
$global:service = [pscustomobject]@{}
$global:service | Add-Member ScriptMethod Connect { $global:connections++ }
$global:service | Add-Member ScriptMethod GetFolder {
    param($path)
    if ($path -cne '\') { throw 'Unexpected task folder.' }
    return $global:folder
}
# Every COM creation is intercepted; no real scheduler object can be acquired.
# The fake exposes no Run/Start/Stop/update operations; unexpected calls fail.
function New-Object {
    [CmdletBinding(DefaultParameterSetName = 'Type')]
    param(
        [Parameter(Position=0, ParameterSetName='Type')][string]$TypeName,
        [Parameter(Position=1, ParameterSetName='Type')][object[]]$ArgumentList,
        [Parameter(ParameterSetName='Com')][string]$ComObject
    )
    if ($PSCmdlet.ParameterSetName -eq 'Com') {
        if ($ComObject -cne 'Schedule.Service') { throw 'Unexpected COM access.' }
        return $global:service
    }
    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}
function Assert-Fails([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected rejection.' }
}
$install = Join-Path $fixture 'install-tollgate-scheduler.ps1'
$uninstall = Join-Path $fixture 'uninstall-tollgate-scheduler.ps1'
$parentPath = $env:PATH
. $install
. $uninstall
. (Join-Path $fixture 'Orchestrator.Scheduler.ps1')
$global:identity = Get-TollgateSchedulerIdentity
if ($connections -or $registrations -or $removals) { throw 'Import side effect.' }
& $install -CodexExecutable $exe -WhatIf
& $uninstall -WhatIf
if ($connections) { throw 'WhatIf contacted scheduler.' }
Assert-Fails { & $install }
Assert-Fails { & $install -CodexExecutable 'relative/codex.exe' }
Assert-Fails { & $install -CodexExecutable $exe -TimeoutSeconds 1 }
if ($connections) { throw 'Invalid configuration contacted scheduler.' }
$r = & $install -TrustedSearchRoots $suite -TimeoutSeconds 90
if ($r.Status -cne 'Installed' -or $registrations -ne 1) { throw 'Install failed.' }
[xml]$xml = $capturedXml
if ($xml.Task.Principals.Principal.UserId -cne $identity.Sid -or $xml.Task.Principals.Principal.LogonType -cne 'InteractiveToken' -or $xml.Task.Principals.Principal.RunLevel -cne 'LeastPrivilege') { throw 'Unsafe principal.' }
if ($xml.Task.Triggers.TimeTrigger.Repetition.Interval -cne 'PT5M' -or $xml.Task.Triggers.ChildNodes.Count -ne 1 -or $xml.Task.Settings.MultipleInstancesPolicy -cne 'IgnoreNew' -or $xml.Task.Settings.AllowStartOnDemand -cne 'false' -or $xml.Task.Settings.WakeToRun -cne 'false' -or $xml.Task.Settings.StartWhenAvailable -cne 'false' -or $xml.Task.Settings.ExecutionTimeLimit -cne 'PT0S') { throw 'Wrong schedule.' }
$start = [datetime]::Parse($xml.Task.Triggers.TimeTrigger.StartBoundary)
if ($start -lt [datetime]::Now.AddMinutes(4) -or $start -gt [datetime]::Now.AddMinutes(6)) { throw 'Wrong initial delay.' }
$argsText = $xml.Task.Actions.Exec.Arguments
$code = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($argsText -split ' ')[-1]))
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Encoded action parse failure.' }
$command = $ast.Find({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Ampersand' }, $true)
if ($command.CommandElements[0].SafeGetValue() -cne (Join-Path $fixture 'run-tollgate-orchestrator.ps1') -or $command.CommandElements[2].SafeGetValue() -cne $exe -or $command.CommandElements[4].SafeGetValue() -ne 90) { throw 'Literal action transport changed.' }
Assert-Fails { & $install -CodexExecutable $exe }
if ($registrations -ne 1) { throw 'Existing task overwritten.' }
$owned = $existing
foreach ($change in @('owner','sid','path','command','arguments','extra-action','runlevel')) {
    [xml]$altered = $owned.Xml
    $taskPath = $owned.Path
    switch ($change) {
        owner { $altered.Task.RegistrationInfo.Description = 'unknown' }
        sid { $altered.Task.Principals.Principal.UserId = 'S-1-5-18' }
        path { $taskPath = '\Unrelated' }
        command { $altered.Task.Actions.Exec.Command = 'unknown.exe' }
        arguments { $altered.Task.Actions.Exec.Arguments = '-Command exit' }
        extra-action { [void]$altered.Task.Actions.AppendChild($altered.Task.Actions.Exec.CloneNode($true)) }
        runlevel { $altered.Task.Principals.Principal.RunLevel = 'HighestAvailable' }
    }
    $global:existing = [pscustomobject]@{ Path = $taskPath; Xml = $altered.OuterXml }
    Assert-Fails { & $uninstall }
    Assert-Fails { & $install -CodexExecutable $exe }
}
if ($removals -or $registrations -ne 1) { throw 'Collision mutated task.' }
$global:existing = $owned
$global:removalFailure = $true
Assert-Fails { & $uninstall }
$global:removalFailure = $false
$r = & $uninstall
if ($r.Status -cne 'Uninstalled' -or $removals -ne 1) { throw 'Owned uninstall failed.' }
$r = & $uninstall
if ($r.Status -cne 'Absent' -or $removals -ne 1) { throw 'Absent uninstall mutated task.' }
$global:lookupFailure = $true
Assert-Fails { & $install -CodexExecutable $exe }
Assert-Fails { & $uninstall }
$global:lookupFailure = $false
$global:race = $true
Assert-Fails { & $install -CodexExecutable $exe }
$global:race = $false
$global:registrationFailure = $true
Assert-Fails { & $install -CodexExecutable $exe }
if ($registrations -ne 1 -or $removals -ne 1 -or $env:PATH -cne $parentPath) { throw 'Unexpected mutation.' }
Write-Output "PASS: import/WhatIf isolation, absolute discovery and literal transport, schedule/principal, exact ownership, collisions/create race, absent task, service errors; only fake registration=1/removal=1; no start API. Fixture: $suite"
