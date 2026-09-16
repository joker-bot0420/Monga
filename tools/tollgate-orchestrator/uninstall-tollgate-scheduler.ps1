[CmdletBinding(SupportsShouldProcess = $true)]
param()
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Orchestrator.Scheduler.ps1')
$identity = Get-TollgateSchedulerIdentity
if ($PSCmdlet.ShouldProcess(('\' + $identity.Name), 'Remove owned current-user tollgate scheduler')) {
    $service = Connect-TollgateScheduler
    $folder = $service.GetFolder('\')
    $task = Get-TollgateScheduledTask $folder $identity.Name
    if ($null -eq $task) {
        [pscustomobject]@{ TaskPath = '\' + $identity.Name; Status = 'Absent' }
        return
    }
    Assert-TollgateSchedulerOwnership $task $identity
    # A running instance is not stopped; lifecycle files are never touched.
    $folder.DeleteTask($identity.Name, 0)
    [pscustomobject]@{ TaskPath = '\' + $identity.Name; Status = 'Uninstalled' }
}
