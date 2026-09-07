# Compatible with Windows PowerShell 5.1. The caller owns the returned handle.
function Enter-TollgateOrchestratorLock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LockPath)

    $fullPath = [System.IO.Path]::GetFullPath($LockPath)
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    [void][System.IO.Directory]::CreateDirectory($parent)
    # OpenOrCreate never truncates an existing lock file. FileShare.None is held
    # across the complete pipeline, and Windows releases it on process exit.
    # Do not delete the file on release: deleting creates a lock identity race.
    return [System.IO.File]::Open(
        $fullPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
}
