[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CodexExecutable,
    [string[]]$TrustedSearchRoots = @(),
    [ValidateRange(30,1800)][int]$TimeoutSeconds = 300
)
# Dot-sourcing is never an installation action.
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Orchestrator.Scheduler.ps1')
$identity = Get-TollgateSchedulerIdentity
$codex = Resolve-TollgateCodexExecutable -ExplicitPath $CodexExecutable -TrustedSearchRoots $TrustedSearchRoots
$entry = Assert-TollgateLocalPath (Join-Path $PSScriptRoot 'run-tollgate-orchestrator.ps1')
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'Orchestrator entry point is missing.' }
# Same encoded literal transport as the existing bridge adapter. No candidate is run.
$command = '$ErrorActionPreference = ''Stop''; try { & ''' + $entry.Replace("'", "''") + ''' -CodexExecutable ''' + $codex.Replace("'", "''") + ''' -TimeoutSeconds ' + $TimeoutSeconds + '; if (-not $?) { exit 1 }; exit 0 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }'
$arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$xml = New-TollgateSchedulerXml $identity $arguments
if ($PSCmdlet.ShouldProcess(('\' + $identity.Name), 'Register current-user tollgate scheduler (first run in five minutes)')) {
    $service = Connect-TollgateScheduler
    $folder = $service.GetFolder('\')
    if ($null -ne (Get-TollgateScheduledTask $folder $identity.Name)) { throw 'Task already exists; refusing overwrite. Use the ownership-checked uninstall explicitly first.' }
    # TASK_CREATE=2 (never CREATE_OR_UPDATE), TASK_LOGON_INTERACTIVE_TOKEN=3.
    # No password, elevation, immediate start, or automatic retry registration.
    [void]$folder.RegisterTask($identity.Name, $xml, 2, $identity.Sid, $null, 3, $null)
    [pscustomobject]@{ TaskPath = '\' + $identity.Name; Status = 'Installed'; CodexExecutable = $codex }
}
