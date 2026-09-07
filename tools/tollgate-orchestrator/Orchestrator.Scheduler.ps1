# Definitions only: loading this file never connects to Task Scheduler.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Orchestrator.ExecutorEnvironment.ps1')

function Get-TollgateSchedulerIdentity {
    $repo = Assert-TollgateLocalPath (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($repo.ToUpperInvariant() + '|' + $sid))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    [pscustomobject]@{
        Repository = $repo
        Sid = $sid
        Name = 'Tollgate-Orchestrator-' + $hash
        Owner = 'TG-AUTO-02-EXT scheduler v1|' + $repo + '|' + $sid
        PowerShell = Assert-TollgateLocalPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    }
}

function Connect-TollgateScheduler {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    return $service
}

function Get-TollgateScheduledTask($Folder, [string]$Name) {
    try { return $Folder.GetTask($Name) }
    catch {
        # Only ERROR_FILE_NOT_FOUND means absent. Access/service errors fail closed.
        $errorObject = $_.Exception
        while ($errorObject) {
            if ($errorObject.HResult -eq -2147024894) { return $null }
            $errorObject = $errorObject.InnerException
        }
        throw
    }
}

function Get-TollgateSchedulerActionHash([string]$Arguments) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Arguments))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function New-TollgateSchedulerXml($Identity, [string]$Arguments) {
    $xml = New-Object Xml.XmlDocument
    $xml.LoadXml('<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><RegistrationInfo/><Triggers/><Principals/><Settings/><Actions Context="CurrentUser"/></Task>')
    $ns = $xml.DocumentElement.NamespaceURI
    function Add-Element($Parent, [string]$Name, [string]$Value) {
        $node = $xml.CreateElement($Name, $ns)
        if ($Value) { $node.InnerText = $Value }
        [void]$Parent.AppendChild($node)
        return $node
    }
    $root = $xml.DocumentElement
    [void](Add-Element $root.SelectSingleNode('*[local-name()="RegistrationInfo"]') 'Description' ($Identity.Owner + '|action-sha256:' + (Get-TollgateSchedulerActionHash $Arguments)))
    [void](Add-Element $root.SelectSingleNode('*[local-name()="RegistrationInfo"]') 'URI' ('\' + $Identity.Name))
    $trigger = Add-Element $root.SelectSingleNode('*[local-name()="Triggers"]') 'TimeTrigger' ''
    $repeat = Add-Element $trigger 'Repetition' ''
    [void](Add-Element $repeat 'Interval' 'PT5M')
    [void](Add-Element $repeat 'StopAtDurationEnd' 'false')
    [void](Add-Element $trigger 'StartBoundary' ([DateTime]::Now.AddMinutes(5).ToString('yyyy-MM-ddTHH:mm:ss')))
    [void](Add-Element $trigger 'Enabled' 'true')
    $principal = Add-Element $root.SelectSingleNode('*[local-name()="Principals"]') 'Principal' ''
    $principal.SetAttribute('id', 'CurrentUser')
    [void](Add-Element $principal 'UserId' $Identity.Sid)
    [void](Add-Element $principal 'LogonType' 'InteractiveToken')
    [void](Add-Element $principal 'RunLevel' 'LeastPrivilege')
    foreach ($pair in @(@('MultipleInstancesPolicy','IgnoreNew'), @('DisallowStartIfOnBatteries','false'), @('StopIfGoingOnBatteries','false'), @('StartWhenAvailable','false'), @('AllowStartOnDemand','false'), @('Enabled','true'), @('WakeToRun','false'), @('ExecutionTimeLimit','PT0S'))) {
        [void](Add-Element $root.SelectSingleNode('*[local-name()="Settings"]') $pair[0] $pair[1])
    }
    $action = Add-Element $root.SelectSingleNode('*[local-name()="Actions"]') 'Exec' ''
    [void](Add-Element $action 'Command' $Identity.PowerShell)
    [void](Add-Element $action 'Arguments' $Arguments)
    [void](Add-Element $action 'WorkingDirectory' $Identity.Repository)
    return $xml.OuterXml
}

function Assert-TollgateSchedulerOwnership($Task, $Identity) {
    [xml]$xml = $Task.Xml
    $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    $arguments = $xml.SelectNodes('/t:Task/t:Actions/t:Exec/t:Arguments', $ns)
    if ($arguments.Count -ne 1) { throw 'Existing task action is ambiguous; refusing removal.' }
    $checks = @{
        '/t:Task/t:RegistrationInfo/t:Description' = $Identity.Owner + '|action-sha256:' + (Get-TollgateSchedulerActionHash $arguments[0].InnerText)
        '/t:Task/t:RegistrationInfo/t:URI' = '\' + $Identity.Name
        '/t:Task/t:Principals/t:Principal/t:UserId' = $Identity.Sid
        '/t:Task/t:Principals/t:Principal/t:LogonType' = 'InteractiveToken'
        '/t:Task/t:Principals/t:Principal/t:RunLevel' = 'LeastPrivilege'
        '/t:Task/t:Actions/t:Exec/t:Command' = $Identity.PowerShell
        '/t:Task/t:Actions/t:Exec/t:WorkingDirectory' = $Identity.Repository
    }
    foreach ($path in $checks.Keys) {
        $nodes = $xml.SelectNodes($path, $ns)
        if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cne $checks[$path]) { throw 'Existing task ownership is ambiguous; refusing removal.' }
    }
    if ($Task.Path -cne ('\' + $Identity.Name) -or $xml.SelectNodes('/t:Task/t:Actions/*', $ns).Count -ne 1 -or $xml.SelectNodes('/t:Task/t:Principals/*', $ns).Count -ne 1) {
        throw 'Existing task identity is ambiguous; refusing removal.'
    }
}
