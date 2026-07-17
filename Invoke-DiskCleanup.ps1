<#
.SYNOPSIS
    Reports on and frees disk space on the C: drive of a Windows machine.

.DESCRIPTION
    Frees disk space on any Windows 10/11 machine whose C: drive has filled up
    (e.g. after a disk-usage alert from monitoring/RMM).

    The DEFAULT run is REPORT-ONLY. Nothing is deleted unless -Clean is supplied.

    By default the script targets the profile of the account running it. Use
    -TargetUser <name> to run against a specific user's profile (e.g. when a
    tech is elevated with admin credentials on a user's laptop), or -AllUsers
    to run against every local profile on the machine. Both require elevation.

    Report mode shows:
      - Current C: capacity / used / free
      - Machine-wide recoverable space (Windows temp, Windows Update cache,
        Outlook diagnostic logging under <SystemDrive>\Temp for all users,
        hiberfil.sys, Windows.old)
      - Per targeted profile: Recycle Bin and temp sizes, large/old files in
        Downloads (old installers and archives are the usual culprits), and
        the largest files in the profile (candidates to move to OneDrive)

    Clean mode (-Clean) empties the targeted Recycle Bin(s) and clears the
    targeted temp folder(s), Windows temp, the Windows Update download cache,
    the Delivery Optimization cache, and Outlook diagnostic logging folders
    ('<SystemDrive>\Temp\<any user>\Outlook Logging') for ALL users -
    independent of -TargetUser/-AllUsers. Old, large Downloads files are only
    touched when -IncludeDownloads is also supplied, and each file is
    confirmed individually unless -Force is used.

    With -Clean -MoveToOneDrive, large old user files are MOVED into the
    profile's OneDrive folder (under 'Moved from <computer>', keeping their
    relative path) and marked "free up space" so OneDrive dehydrates them
    after upload. Only plain user content from the standard folders (Desktop,
    Documents, Pictures, Videos, Music, Downloads) is eligible; Outlook data
    files, disk images, hidden/system files, and - critically - files inside
    ANY cloud sync root (every OneDrive account and every SharePoint/Teams-
    synced library, enumerated from the profile's own hive) are never moved,
    since moving a file out of a sync root replicates as a cloud-side delete.
    Moves therefore require the target user to be signed in (hive loaded);
    when -IncludeDownloads is also given, Downloads deletion takes precedence
    over moving. NOTE: disk space is freed only after OneDrive finishes
    uploading and dehydrating the files - not at move time.

    Everything the script deletes is either regenerable by Windows (temp/caches)
    or explicitly confirmed by the operator (Downloads, Recycle Bin). Directory
    junctions and symbolic links are never followed: only the link itself is
    removed, never the folder it points at.

.PARAMETER Clean
    Actually perform the safe cleanups (Recycle Bin, temp folders, update caches).
    Without this switch the script only reports, and the other cleanup switches
    have no effect.

.PARAMETER TargetUser
    Run the user-profile steps (Downloads, Recycle Bin, user temp, largest
    files, OneDrive detection) against this user's profile instead of the
    account running the script. A domain-qualified name ('DOMAIN\jsmith') must
    match the account name exactly; a bare name ('jsmith') matches the short
    account name or the profile folder name under C:\Users. Requires elevation
    unless it resolves to the current user.

.PARAMETER AllUsers
    Run the user-profile steps against every non-special local profile on the
    machine. Requires elevation. Cannot be combined with -TargetUser.

.PARAMETER IncludeDownloads
    With -Clean, also delete files in the targeted Downloads folder(s) that are
    BOTH larger than -DownloadsMinSizeMB AND older than -DownloadsOlderThanDays.
    Prompts per file unless -Force is given. Unattended/non-interactive runs
    (RMM, scheduled tasks) must use -Force, since no one is there to answer
    prompts.

.PARAMETER DownloadsMinSizeMB
    Minimum file size (MB) for a Downloads file to be eligible. Default 500.

.PARAMETER DownloadsOlderThanDays
    Minimum age (days since last write) for a Downloads file to be eligible.
    Default 90.

.PARAMETER MoveToOneDrive
    With -Clean, move eligible large old user files into the profile's
    OneDrive folder and mark them "free up space" (dehydrated after upload).
    Prompts per file unless -Force is given. Requires OneDrive to be set up
    AND the target user to be signed in, so all sync roots can be verified
    from their hive; skipped with a note otherwise. Business OneDrive is
    preferred over personal when both exist.

.PARAMETER MoveMinSizeMB
    Minimum file size (MB) to be eligible for -MoveToOneDrive. Default 500.

.PARAMETER MoveOlderThanDays
    Minimum age (days since last write) to be eligible for -MoveToOneDrive.
    Default 90. Use 0 to ignore age.

.PARAMETER DeepClean
    With -Clean, also run DISM component-store cleanup (slow, so it's off by
    default). Requires elevation.

.PARAMETER DisableHibernation
    With -Clean, turn hibernation off to remove hiberfil.sys. Requires
    elevation. Skip this on machines where users rely on hibernate.

.PARAMETER Force
    Skip the per-file confirmation prompts for Downloads cleanup and
    OneDrive moves.

.PARAMETER SkipLargeFileScan
    Skip the recursive scan of each profile for the largest-files report
    (the scan can take several minutes per profile on a full drive). The
    scan still runs when -Clean -MoveToOneDrive is used, since move
    candidates come from it; only the top-N listing is suppressed.

.PARAMETER TopFiles
    How many of the largest files to list per profile. Default 25.

.PARAMETER LogDirectory
    Where to write the run log. Default: <user profile>\DiskCleanup-Logs, or
    <ProgramData>\DiskCleanup-Logs when running as SYSTEM (so RMM logs are
    findable).

.EXAMPLE
    .\Invoke-DiskCleanup.ps1
    Report only, current user's profile - nothing is deleted.

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -TargetUser jsmith
    Report only, against another user's profile (run elevated as a tech account).

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -Clean -TargetUser jsmith -IncludeDownloads
    Clean that user's Recycle Bin, temp and old large Downloads files,
    confirming each Downloads file.

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -Clean -MoveToOneDrive
    Also move large old user files (500 MB+, 90+ days) into OneDrive,
    confirming each file; they become online-only after upload.

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -Clean -AllUsers
    Empty every profile's Recycle Bin and temp, plus machine-wide caches.

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -Clean -AllUsers -IncludeDownloads -Force -DownloadsMinSizeMB 1000
    Unattended (e.g. RMM as SYSTEM): all profiles, including 1 GB+ Downloads
    files older than 90 days.

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -Clean -WhatIf
    Show every deletion that -Clean would perform without doing any of them.

.NOTES
    Elevation: user-profile steps for accounts OTHER than the one running the
    script require an elevated session, as do the machine-wide steps (Windows
    temp, update caches, DISM, hibernation). Without elevation the current
    user's own profile steps still work; everything else is skipped with a
    warning.

    When run as SYSTEM or as a different admin account WITHOUT -TargetUser /
    -AllUsers, the script warns that it is about to target the wrong profile
    and suggests the right switch.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Clean,
    [string]$TargetUser,
    [switch]$AllUsers,
    [switch]$IncludeDownloads,
    [ValidateRange(1, 1048576)]
    [int]$DownloadsMinSizeMB = 500,
    [ValidateRange(1, 36500)]
    [int]$DownloadsOlderThanDays = 90,
    [switch]$MoveToOneDrive,
    [ValidateRange(1, 1048576)]
    [int]$MoveMinSizeMB = 500,
    [ValidateRange(0, 36500)]
    [int]$MoveOlderThanDays = 90,
    [switch]$DeepClean,
    [switch]$DisableHibernation,
    [switch]$Force,
    [switch]$SkipLargeFileScan,
    [ValidateRange(1, 500)]
    [int]$TopFiles = 25,
    [string]$LogDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- helpers ---

$script:LogFile = $null

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host $Message -ForegroundColor $Color
    if ($script:LogFile) {
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        # Logging is bookkeeping, not a cleanup action - exempt from -WhatIf/-Confirm.
        Add-Content -Path $script:LogFile -Value "$stamp  $Message" -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Write-Section {
    param([string]$Title)
    Write-Log ''
    Write-Log "=== $Title ===" ([ConsoleColor]::Cyan)
}

function Format-Size {
    param([double]$Bytes)
    $sign = ''
    if ($Bytes -lt 0) { $sign = '-'; $Bytes = -$Bytes }
    if ($Bytes -ge 1GB) { return ('{0}{1:N2} GB' -f $sign, ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0}{1:N1} MB' -f $sign, ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0}{1:N0} KB' -f $sign, ($Bytes / 1KB)) }
    return ('{0}{1:N0} bytes' -f $sign, $Bytes)
}

function Get-DriveFreeBytes {
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    return [double]$disk.FreeSpace
}

# Walks a folder tree WITHOUT following junctions or symbolic links.
# On Windows PowerShell 5.1, Get-ChildItem -Recurse and Remove-Item -Recurse
# both traverse INTO junctions, which would make deletions escape the folder
# being cleaned and inflate size measurements - so all recursion in this
# script goes through this walker instead.
function Get-FolderInventory {
    param([string]$Root)
    $files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $dirs  = New-Object 'System.Collections.Generic.List[System.IO.DirectoryInfo]'
    $links = New-Object 'System.Collections.Generic.List[System.IO.FileSystemInfo]'
    if (Test-Path -LiteralPath $Root) {
        $stack = New-Object 'System.Collections.Generic.Stack[string]'
        $stack.Push($Root)
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)
            foreach ($child in $children) {
                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    if (-not $child.PSIsContainer) {
                        # File reparse points (OneDrive placeholders, file symlinks)
                        # are safe to treat as files: deleting one is non-recursive
                        # and only removes the local entry.
                        $files.Add($child)
                    } elseif ($child.LinkType) {
                        # Junction / symbolic link / mount point - never follow.
                        $links.Add($child)
                    } else {
                        # Container reparse point with no link target (OneDrive
                        # cloud folder): a real directory, so recurse into it.
                        $dirs.Add($child)
                        $stack.Push($child.FullName)
                    }
                } elseif ($child.PSIsContainer) {
                    $dirs.Add($child)
                    $stack.Push($child.FullName)
                } else {
                    $files.Add($child)
                }
            }
        }
    }
    New-Object PSObject -Property @{ Files = $files; Dirs = $dirs; Links = $links }
}

function Get-FolderSizeBytes {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 0 }
    $inv = Get-FolderInventory -Root $Path
    if ($inv.Files.Count -gt 0) {
        $sum = $inv.Files | Measure-Object -Property Length -Sum
        if ($sum -and $sum.Sum) { return [double]$sum.Sum }
    }
    return 0
}

# Expands a raw (UNEXPANDED) registry value for a TARGET profile: %USERPROFILE%
# maps to the target's profile path (never the caller's), machine-scoped
# variables expand normally, and any other unresolved %variable% returns $null
# rather than guessing with the caller's environment. Replacements are literal
# string operations - no regex substitution semantics.
function Expand-TargetProfileValue {
    param(
        [string]$Raw,
        [string]$ProfilePath
    )
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $result = $Raw
    foreach ($pair in @(
        @{ Token = '%USERPROFILE%'; Value = $ProfilePath },
        @{ Token = '%SystemDrive%'; Value = $env:SystemDrive },
        @{ Token = '%SystemRoot%';  Value = $env:SystemRoot }
    )) {
        if (-not $pair.Value) { continue }
        $idx = $result.IndexOf($pair.Token, [StringComparison]::OrdinalIgnoreCase)
        while ($idx -ge 0) {
            $result = $result.Substring(0, $idx) + $pair.Value + $result.Substring($idx + $pair.Token.Length)
            $idx = $result.IndexOf($pair.Token, ($idx + $pair.Value.Length), [StringComparison]::OrdinalIgnoreCase)
        }
    }
    if ($result.IndexOf('%') -ge 0) { return $null }
    return $result
}

# Returns $true when no existing directory component of $Path is a
# junction/symlink - deletions through such a path would land somewhere else.
# (OneDrive cloud folders carry the reparse attribute but no LinkType and are
# fine to traverse.) Components that don't exist yet can't be links.
function Test-NoLinkComponents {
    param([string]$Path)
    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $false }
    $root = [System.IO.Path]::GetPathRoot($full)
    if (-not $root) { return $false }
    $rest = $full.Substring($root.Length).Trim('\')
    if (-not $rest) { return $true }
    $currentPath = $root.TrimEnd('\')
    foreach ($segment in $rest.Split('\')) {
        $currentPath = $currentPath + '\' + $segment
        if (-not (Test-Path -LiteralPath $currentPath)) { return $true }
        $item = $null
        try { $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop } catch { return $false }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $item.LinkType) { return $false }
    }
    return $true
}

# Finds Outlook diagnostic-logging folders under <SystemDrive>\Temp for EVERY
# user. Outlook's troubleshooting logging writes large .etl/.log files to
# '<temp>\Outlook Logging'; on machines where TEMP is redirected to
# C:\Temp\<username>, those folders grow unbounded and sit outside the
# per-profile temp cleanup, so they are handled machine-wide instead.
# Junctions are never looked through.
function Get-OutlookLoggingPaths {
    $paths = @()
    $tempRoot = Join-Path $env:SystemDrive 'Temp'
    if (Test-Path -LiteralPath $tempRoot) {
        $direct = Join-Path $tempRoot 'Outlook Logging'
        if (Test-Path -LiteralPath $direct) { $paths += $direct }
        $children = @(Get-ChildItem -LiteralPath $tempRoot -Directory -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $child.LinkType) { continue }
            $candidate = Join-Path $child.FullName 'Outlook Logging'
            if (Test-Path -LiteralPath $candidate) { $paths += $candidate }
        }
    }
    # Emit elements plainly; callers collect with @(...) so 0/1/n results all
    # become a flat array (a leading-comma wrap here would nest it instead).
    return @($paths | Where-Object { Test-NoLinkComponents -Path $_ })
}

# OneDrive Files On-Demand placeholders report their full logical size but
# occupy ~0 bytes locally; deleting or "moving" them frees nothing.
function Test-CloudOnlyFile {
    param([System.IO.FileInfo]$File)
    # FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS (0x400000), RECALL_ON_OPEN (0x40000), Offline (0x1000)
    $mask = 0x400000 -bor 0x40000 -bor 0x1000
    return ((([int]$File.Attributes) -band $mask) -ne 0)
}

# Decides whether a file is safe to relocate into OneDrive: plain user content
# only. Eligible files must live under one of the profile's standard content
# folders (Desktop/Documents/Pictures/Videos/Music/Downloads) - this keeps
# app-owned trees like .git, VirtualBox VMs, .nuget etc. out of scope - and
# must not be inside ANY cloud sync root (a second OneDrive account or a
# SharePoint/Teams-synced library: moving a file out of one would sync as a
# cloud-side DELETE). Outlook data files, disk images, hidden/system files,
# and cloud placeholders are never candidates.
function Test-OneDriveMoveCandidate {
    param(
        [System.IO.FileInfo]$File,
        [string[]]$AllowedRoots,
        [string[]]$SyncRoots,
        [double]$MinBytes,
        [datetime]$Cutoff
    )
    if ($File.Length -lt $MinBytes) { return $false }
    if ($File.LastWriteTime -ge $Cutoff) { return $false }
    if ($File.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if (Test-CloudOnlyFile -File $File) { return $false }
    if ($File.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) { return $false }
    $blockedExt = @('.ost', '.pst', '.vhd', '.vhdx', '.vmdk', '.avhd', '.avhdx', '.vdi', '.qcow2', '.img', '.hdd')
    if ($blockedExt -contains $File.Extension.ToLowerInvariant()) { return $false }
    $filePath = $File.FullName
    $inAllowed = $false
    foreach ($root in $AllowedRoots) {
        if (-not $root) { continue }
        if ($filePath.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
            $inAllowed = $true
            break
        }
    }
    if (-not $inAllowed) { return $false }
    foreach ($root in $SyncRoots) {
        if (-not $root) { continue }
        if ($filePath.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

# Deletes old contents of a folder (never the folder itself). The age cutoff
# is applied per FILE at every depth, so a brand-new file inside an old
# directory is left alone. Junctions/symlinks are removed as links only -
# their targets are never touched. Returns bytes freed.
function Clear-FolderContents {
    param(
        [string]$Path,
        [string]$Label,
        [int]$OlderThanHours = 24,
        [switch]$MustBeTempFolder
    )

    # Refuse blank paths, drive roots, and well-known profile/system roots so a
    # bad or repointed environment variable can never wipe user data.
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Log "  SKIP $Label - path is empty." ([ConsoleColor]::Yellow)
        return 0
    }
    $resolved = $null
    try { $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { }
    if (-not $resolved) {
        Write-Log "  SKIP $Label - $Path does not exist." ([ConsoleColor]::DarkGray)
        return 0
    }
    if ($resolved -match '^[A-Za-z]:\\?$') {
        Write-Log "  SKIP $Label - refusing to clean a drive root ($resolved)." ([ConsoleColor]::Yellow)
        return 0
    }
    $protectedRoots = @(
        $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:SystemRoot,
        $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:PUBLIC, (Join-Path $env:SystemDrive 'Users')
    ) | Where-Object { $_ }
    foreach ($root in $protectedRoots) {
        if ($resolved.TrimEnd('\') -eq $root.TrimEnd('\')) {
            Write-Log "  SKIP $Label - refusing to clean protected folder ($resolved)." ([ConsoleColor]::Yellow)
            return 0
        }
    }
    # Refuse any profile root under C:\Users (covers targeted profiles too).
    if ($resolved.TrimEnd('\') -match '^[A-Za-z]:\\Users\\[^\\]+$') {
        Write-Log "  SKIP $Label - refusing to clean a profile root ($resolved)." ([ConsoleColor]::Yellow)
        return 0
    }
    if ($MustBeTempFolder) {
        # Accept ...\Temp and Terminal Services per-session paths like ...\Temp\2.
        $leaf = Split-Path $resolved -Leaf
        $parentLeaf = ''
        $parentPath = Split-Path $resolved -Parent
        if ($parentPath) { $parentLeaf = Split-Path $parentPath -Leaf }
        if (-not (($leaf -match '^te?mp$') -or (($leaf -match '^\d+$') -and ($parentLeaf -match '^te?mp$')))) {
            Write-Log "  SKIP $Label - $resolved is not a Temp folder; refusing (TEMP may be repointed)." ([ConsoleColor]::Yellow)
            return 0
        }
    }
    # Never clean THROUGH a link: if the folder itself is a junction/symlink,
    # its contents actually live somewhere else - refuse.
    try {
        $rootItem = Get-Item -LiteralPath $resolved -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $rootItem.LinkType) {
            Write-Log "  SKIP $Label - $resolved is a junction/symlink; refusing to clean through a link." ([ConsoleColor]::Yellow)
            return 0
        }
    } catch { }

    $cutoff = (Get-Date).AddHours(-$OlderThanHours)
    $inv = Get-FolderInventory -Root $resolved
    $oldFiles = @($inv.Files | Where-Object { $_.LastWriteTime -lt $cutoff })
    $oldLinks = @($inv.Links | Where-Object { $_.LastWriteTime -lt $cutoff })

    $targetBytes = [double]0
    foreach ($f in $oldFiles) { $targetBytes += $f.Length }

    if ($oldFiles.Count -eq 0 -and $oldLinks.Count -eq 0) {
        Write-Log ("  {0}: nothing older than {1}h to remove." -f $Label, $OlderThanHours) ([ConsoleColor]::DarkGray)
        return 0
    }

    $action = 'Delete {0} item(s) older than {1}h (~{2})' -f ($oldFiles.Count + $oldLinks.Count), $OlderThanHours, (Format-Size $targetBytes)
    if (-not $PSCmdlet.ShouldProcess($resolved, $action)) {
        if ($WhatIfPreference) {
            Write-Log ("  {0}: would free ~{1} ({2} file(s))" -f $Label, (Format-Size $targetBytes), $oldFiles.Count)
        }
        return 0
    }

    $freed = [double]0
    foreach ($f in $oldFiles) {
        $len = $f.Length
        # Locked/in-use files simply fail and are skipped; that is expected.
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $f.FullName)) { $freed += $len }
    }
    foreach ($l in $oldLinks) {
        # .Delete() removes only the reparse point itself, never its target.
        try { $l.Delete() } catch { }
    }
    # Prune old directories that are now empty, deepest first.
    $oldDirs = @($inv.Dirs | Where-Object { $_.LastWriteTime -lt $cutoff } |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($d in $oldDirs) {
        # DirectoryInfo.Delete() is non-recursive and throws unless empty.
        try { $d.Delete() } catch { }
    }

    Write-Log ("  {0}: freed {1}" -f $Label, (Format-Size $freed)) ([ConsoleColor]::Green)
    return $freed
}

# ------------------------------------------------- profile identification ---

# Resolves which user profiles this run targets. Each result carries:
# UserName, Sid, ProfilePath, IsCurrentUser, HiveLoaded.
function Get-TargetProfiles {
    param(
        [string]$TargetUser,
        [bool]$AllUsers,
        [System.Security.Principal.WindowsIdentity]$Identity
    )

    $current = New-Object PSObject -Property @{
        UserName      = $Identity.Name
        Sid           = $Identity.User.Value
        ProfilePath   = $env:USERPROFILE
        IsCurrentUser = $true
        HiveLoaded    = $true
    }

    if (-not $AllUsers -and [string]::IsNullOrWhiteSpace($TargetUser)) {
        return @($current)
    }

    # Enumerate real (non-special) local profiles.
    $profileList = @()
    $cimProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { (-not $_.Special) -and $_.LocalPath -and ($_.LocalPath -match '\\Users\\') })
    foreach ($cp in $cimProfiles) {
        $accountName = $null
        try {
            $sidObj = New-Object System.Security.Principal.SecurityIdentifier($cp.SID)
            $accountName = $sidObj.Translate([System.Security.Principal.NTAccount]).Value
        } catch { }
        if (-not $accountName) { $accountName = Split-Path $cp.LocalPath -Leaf }
        $profileList += New-Object PSObject -Property @{
            UserName      = $accountName
            Sid           = $cp.SID
            ProfilePath   = $cp.LocalPath
            IsCurrentUser = ($cp.SID -eq $Identity.User.Value)
            HiveLoaded    = [bool]$cp.Loaded
        }
    }

    if ($AllUsers) {
        if ($profileList.Count -eq 0) {
            throw 'Could not enumerate user profiles (Win32_UserProfile returned nothing).'
        }
        return @($profileList | Sort-Object { -not $_.IsCurrentUser })
    }

    # -TargetUser: a domain-qualified name must match the account name exactly;
    # a bare name matches the short account name or the profile folder name.
    $wanted = $TargetUser.Trim()
    if ($wanted -match '\\') {
        $matches0 = @($profileList | Where-Object { $_.UserName -eq $wanted })
    } else {
        $matches0 = @($profileList | Where-Object {
            ($_.UserName -eq $wanted) -or
            (($_.UserName -match '\\') -and ($_.UserName.Split('\')[-1] -eq $wanted)) -or
            ((Split-Path $_.ProfilePath -Leaf) -eq $wanted)
        })
    }
    if ($matches0.Count -eq 0) {
        $available = ($profileList | ForEach-Object { Split-Path $_.ProfilePath -Leaf }) -join ', '
        throw "No profile found for user '$TargetUser'. Profiles on this machine: $available"
    }
    if ($matches0.Count -gt 1) {
        $hits = ($matches0 | ForEach-Object { "$($_.UserName) [$($_.ProfilePath)]" }) -join '; '
        throw "User '$TargetUser' matches more than one profile: $hits. Use the full 'DOMAIN\name' account name or the exact profile folder name."
    }
    return @($matches0)
}

# Reads a profile's Downloads location from ITS OWN registry hive when loaded
# (Downloads can be redirected), falling back to <profile>\Downloads. The value
# is read UNEXPANDED - Get-ItemProperty would pre-expand REG_EXPAND_SZ values
# like '%USERPROFILE%\Downloads' against the account RUNNING this script - and
# %USERPROFILE% is then remapped to the TARGET profile. A redirect pointing
# outside the target profile is not followed: deletions must never leave the
# profile being cleaned.
function Get-ProfileDownloadsPath {
    param($TargetProfile)
    $default = Join-Path $TargetProfile.ProfilePath 'Downloads'
    if (-not $TargetProfile.HiveLoaded) { return $default }
    $candidate = $null
    try {
        $key = Get-Item -Path "Registry::HKEY_USERS\$($TargetProfile.Sid)\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop
        $raw = $key.GetValue('{374DE290-123F-4565-9164-39C4925E467B}', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $candidate = Expand-TargetProfileValue -Raw $raw -ProfilePath $TargetProfile.ProfilePath
    } catch { }
    if (-not $candidate) { return $default }
    # Canonicalize BEFORE any disk access, so '..' segments can't dodge the
    # containment check and off-profile paths (incl. UNC) are never probed.
    try {
        if (-not [System.IO.Path]::IsPathRooted($candidate)) { return $default }
        $candidate = [System.IO.Path]::GetFullPath($candidate)
    } catch { return $default }
    $profRoot = $TargetProfile.ProfilePath.TrimEnd('\') + '\'
    $candNorm = $candidate.TrimEnd('\') + '\'
    if (-not (($candNorm.Length -gt $profRoot.Length) -and $candNorm.StartsWith($profRoot, [StringComparison]::OrdinalIgnoreCase))) {
        Write-Log ("  NOTE: {0}'s Downloads is redirected to {1}; using {2} instead (this script never cleans outside the profile)." -f `
            $TargetProfile.UserName, $candidate, $default) ([ConsoleColor]::Yellow)
        return $default
    }
    if (-not (Test-NoLinkComponents -Path $candidate)) {
        Write-Log ("  NOTE: {0}'s Downloads redirect passes through a junction/symlink; using {1} instead." -f `
            $TargetProfile.UserName, $default) ([ConsoleColor]::Yellow)
        return $default
    }
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $default
}

# Finds a profile's OneDrive folder: its own registry hive when loaded (user
# environment variables, read unexpanded and remapped to the target profile),
# else a OneDrive* folder in the profile root.
function Get-ProfileOneDrivePath {
    param($TargetProfile)
    if ($TargetProfile.HiveLoaded) {
        try {
            $envKey = Get-Item -Path "Registry::HKEY_USERS\$($TargetProfile.Sid)\Environment" -ErrorAction Stop
            foreach ($name in @('OneDriveCommercial', 'OneDrive')) {
                $raw = $envKey.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $expanded = Expand-TargetProfileValue -Raw $raw -ProfilePath $TargetProfile.ProfilePath
                # Never probe a UNC value from a foreign hive (would trigger an
                # outbound SMB connection as the elevated account).
                if ($expanded -and -not $expanded.StartsWith('\\') -and (Test-Path -LiteralPath $expanded)) { return $expanded }
            }
        } catch { }
    }
    $fallback = @(Get-ChildItem -LiteralPath $TargetProfile.ProfilePath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OneDrive*' } | Select-Object -First 1)
    if ($fallback.Count -gt 0) { return $fallback[0].FullName }
    return $null
}

# Enumerates ALL of a profile's cloud sync roots (every OneDrive account's
# UserFolder plus every SharePoint/Teams library synced under Tenants) from
# the profile's own hive, and picks the move destination (business OneDrive
# preferred over personal). Files must never be moved OUT of any sync root -
# the sync engine would replicate that as a deletion in the cloud - so moves
# are refused entirely when the hive isn't loaded and the roots can't be
# verified (HiveReadable = false).
function Get-ProfileOneDriveInfo {
    param($TargetProfile)
    $syncRoots = @()
    $moveTarget = $null
    $personalTarget = $null
    $hiveReadable = $false
    if ($TargetProfile.HiveLoaded) {
        $hiveReadable = $true
        $accountsKey = $null
        try {
            $accountsKey = Get-Item -Path "Registry::HKEY_USERS\$($TargetProfile.Sid)\Software\Microsoft\OneDrive\Accounts" -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            # Key absent: OneDrive simply isn't configured. Not a read failure.
            $accountsKey = $null
        } catch {
            # Could not READ the key: fail closed - an incomplete sync-root
            # list must refuse moves rather than risk moving out of one.
            $accountsKey = $null
            $hiveReadable = $false
        }
        if ($accountsKey) {
            $acctNames = @()
            try { $acctNames = @($accountsKey.GetSubKeyNames()) } catch { $hiveReadable = $false }
            foreach ($acctName in $acctNames) {
                $acct = $null
                try { $acct = $accountsKey.OpenSubKey($acctName) } catch { }
                if (-not $acct) { $hiveReadable = $false; continue }
                $rawFolder = $null
                $userFolder = $null
                try { $rawFolder = $acct.GetValue('UserFolder', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } catch { $hiveReadable = $false }
                if ($rawFolder) {
                    $userFolder = Expand-TargetProfileValue -Raw $rawFolder -ProfilePath $TargetProfile.ProfilePath
                    # A sync root we cannot resolve means the exclusion list is
                    # incomplete - fail closed.
                    if (-not $userFolder) { $hiveReadable = $false }
                }
                if ($userFolder) {
                    $syncRoots += $userFolder
                    # A destination candidate gets the same guards as every
                    # other hive-derived path: local, rooted, canonicalized,
                    # and actually present on disk.
                    $validTarget = $null
                    try {
                        if ([System.IO.Path]::IsPathRooted($userFolder) -and -not $userFolder.StartsWith('\\')) {
                            $canonical = [System.IO.Path]::GetFullPath($userFolder)
                            if (Test-Path -LiteralPath $canonical) { $validTarget = $canonical }
                        }
                    } catch { }
                    if ($validTarget) {
                        if ($acctName -like 'Business*') {
                            if (-not $moveTarget) { $moveTarget = $validTarget }
                        } elseif (-not $personalTarget) {
                            $personalTarget = $validTarget
                        }
                    }
                }
                $tenants = $null
                try { $tenants = $acct.OpenSubKey('Tenants') } catch { $hiveReadable = $false }
                if ($tenants) {
                    $tenantNames = @()
                    try { $tenantNames = @($tenants.GetSubKeyNames()) } catch { $hiveReadable = $false }
                    foreach ($tenantName in $tenantNames) {
                        $tenantKey = $null
                        try { $tenantKey = $tenants.OpenSubKey($tenantName) } catch { }
                        if (-not $tenantKey) { $hiveReadable = $false; continue }
                        # Value NAMES under a tenant key are the local paths
                        # of synced SharePoint/Teams libraries.
                        $libNames = @()
                        try { $libNames = @($tenantKey.GetValueNames()) } catch { $hiveReadable = $false }
                        foreach ($libPath in $libNames) {
                            if ($libPath) { $syncRoots += $libPath }
                        }
                    }
                }
            }
        }
    }
    if (-not $moveTarget) { $moveTarget = $personalTarget }
    # Belt and braces: also treat env-derived and OneDrive*-named folders as
    # sync roots even if the Accounts key missed them.
    $envRoot = Get-ProfileOneDrivePath -TargetProfile $TargetProfile
    if ($envRoot) { $syncRoots += $envRoot }
    $namedRoots = @(Get-ChildItem -LiteralPath $TargetProfile.ProfilePath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OneDrive*' })
    foreach ($nr in $namedRoots) { $syncRoots += $nr.FullName }
    New-Object PSObject -Property @{
        MoveTarget   = $moveTarget
        SyncRoots    = @($syncRoots | Where-Object { $_ } | Select-Object -Unique)
        HiveReadable = $hiveReadable
    }
}

# ------------------------------------------------------------------ setup ---

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    if ($identity.User.Value -eq 'S-1-5-18') {
        # SYSTEM's %USERPROFILE% is buried under System32; keep RMM logs findable.
        $LogDirectory = Join-Path $env:ProgramData 'DiskCleanup-Logs'
    } else {
        $LogDirectory = Join-Path $env:USERPROFILE 'DiskCleanup-Logs'
    }
}
try {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        # Log-directory creation is bookkeeping - exempt from -WhatIf/-Confirm.
        New-Item -Path $LogDirectory -ItemType Directory -Force -WhatIf:$false -Confirm:$false | Out-Null
    }
    $script:LogFile = Join-Path $LogDirectory ("DiskCleanup_{0}.log" -f (Get-Date).ToString('yyyyMMdd_HHmmss'))
} catch {
    Write-Warning "Could not create log directory '$LogDirectory'; continuing without a log file."
}

if ($AllUsers -and -not [string]::IsNullOrWhiteSpace($TargetUser)) {
    throw 'Use either -TargetUser or -AllUsers, not both.'
}

$targetProfiles = @(Get-TargetProfiles -TargetUser $TargetUser -AllUsers ([bool]$AllUsers) -Identity $identity)

$targetsOtherProfiles = [bool]($targetProfiles | Where-Object { -not $_.IsCurrentUser })
if ($targetsOtherProfiles -and -not $isAdmin) {
    throw 'Targeting other users'' profiles (-TargetUser / -AllUsers) requires an elevated PowerShell session.'
}

$modeText = 'REPORT-ONLY (no changes will be made; use -Clean to clean)'
if ($Clean) { $modeText = 'CLEAN' }

Write-Log "Disk Cleanup - $env:COMPUTERNAME - running as $($identity.Name)" ([ConsoleColor]::White)
Write-Log "Mode: $modeText" ([ConsoleColor]::White)
Write-Log ("Target profile(s): {0}" -f (($targetProfiles | ForEach-Object { "{0} [{1}]" -f $_.UserName, $_.ProfilePath }) -join '; ')) ([ConsoleColor]::White)
if (-not $isAdmin) {
    Write-Log 'Not elevated: Windows temp, update caches, DISM and hibernation steps will be skipped.' ([ConsoleColor]::Yellow)
}
if (-not $Clean) {
    foreach ($ignored in @(
        @{ On = [bool]$IncludeDownloads;   Name = '-IncludeDownloads' },
        @{ On = [bool]$MoveToOneDrive;     Name = '-MoveToOneDrive' },
        @{ On = [bool]$DeepClean;          Name = '-DeepClean' },
        @{ On = [bool]$DisableHibernation; Name = '-DisableHibernation' },
        @{ On = [bool]$Force;              Name = '-Force' }
    )) {
        if ($ignored.On) {
            Write-Log ("WARNING: {0} has no effect without -Clean; this run will only report." -f $ignored.Name) ([ConsoleColor]::Yellow)
        }
    }
}

# If no explicit target was given, everything user-scoped comes from THIS
# process's identity. Warn loudly if that is not the logged-on user - e.g.
# run as SYSTEM via RMM, or elevated with a different admin account.
if (-not $AllUsers -and [string]::IsNullOrWhiteSpace($TargetUser)) {
    if ($identity.User.Value -eq 'S-1-5-18') {
        Write-Log 'WARNING: Running as SYSTEM without -TargetUser/-AllUsers - the user-profile steps would' ([ConsoleColor]::Red)
        Write-Log '         target the SYSTEM profile. Use -AllUsers or -TargetUser <name> instead.' ([ConsoleColor]::Red)
    } else {
        $consoleUser = $null
        try { $consoleUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName } catch { }
        if ($consoleUser -and ($consoleUser -ne $identity.Name)) {
            Write-Log ("WARNING: Logged-on console user is {0} but this script runs as {1}." -f $consoleUser, $identity.Name) ([ConsoleColor]::Red)
            Write-Log ('         Add -TargetUser {0} to target their profile instead of yours.' -f $consoleUser.Split('\')[-1]) ([ConsoleColor]::Red)
        }
    }
}
if ($script:LogFile) { Write-Log "Log file: $script:LogFile" }

$freeBefore = Get-DriveFreeBytes
$disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
$usedPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)

Write-Section 'Drive C: status'
Write-Log ("  Total: {0}   Used: {1} ({2}%)   Free: {3}" -f `
    (Format-Size $disk.Size), (Format-Size ($disk.Size - $disk.FreeSpace)), $usedPct, (Format-Size $disk.FreeSpace)) `
    ([ConsoleColor]::White)

$winTemp     = Join-Path $env:SystemRoot 'Temp'
$wuCache     = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
$hiberFile   = Join-Path $env:SystemDrive '\hiberfil.sys'
$windowsOld  = Join-Path $env:SystemDrive '\Windows.old'
$recycleBin  = Join-Path $env:SystemDrive '\$Recycle.Bin'

# ---------------------------------------------------- machine-wide report ---

Write-Section 'Machine-wide recoverable space'

if ($isAdmin) {
    Write-Log ("  Windows temp:             {0}" -f (Format-Size (Get-FolderSizeBytes -Path $winTemp)))
    Write-Log ("  Windows Update cache:     {0}" -f (Format-Size (Get-FolderSizeBytes -Path $wuCache)))
} else {
    Write-Log '  Windows temp:             n/a (needs elevation)'
    Write-Log '  Windows Update cache:     n/a (needs elevation)'
}

# Outlook diagnostic logging under <SystemDrive>\Temp - all users' folders,
# independent of which profiles this run targets.
$outlookLogPaths = @(Get-OutlookLoggingPaths)
if ($outlookLogPaths.Count -gt 0) {
    $outlookLogBytes = [double]0
    foreach ($olPath in $outlookLogPaths) { $outlookLogBytes += Get-FolderSizeBytes -Path $olPath }
    Write-Log ("  Outlook logging folders:  {0} across {1} folder(s) under {2}\Temp  (all users)" -f `
        (Format-Size $outlookLogBytes), $outlookLogPaths.Count, $env:SystemDrive)
    if (-not $isAdmin) {
        Write-Log '    (sizes may be incomplete and other users'' folders may not clean without elevation)' ([ConsoleColor]::DarkGray)
    }
}

try {
    if (Test-Path -LiteralPath $hiberFile) {
        $hiberSize = (Get-Item -LiteralPath $hiberFile -Force -ErrorAction Stop).Length
        Write-Log ("  hiberfil.sys:             {0}  (remove with -Clean -DisableHibernation)" -f (Format-Size $hiberSize)) ([ConsoleColor]::Yellow)
    }
} catch {
    Write-Log '  hiberfil.sys:             present - size n/a (needs elevation)' ([ConsoleColor]::Yellow)
}
if (Test-Path -LiteralPath $windowsOld) {
    if ($isAdmin) {
        Write-Log ("  Windows.old:              {0}  (remove via Settings > Storage > Temporary files)" -f `
            (Format-Size (Get-FolderSizeBytes -Path $windowsOld))) ([ConsoleColor]::Yellow)
    } else {
        Write-Log '  Windows.old:              present - size n/a (needs elevation); remove via Settings > Storage > Temporary files' ([ConsoleColor]::Yellow)
    }
}

# ----------------------------------------------------- per-profile report ---

# Each entry: Profile, DownloadsPath, TempPath, BinPath, DownloadCandidates, OneDrivePath
$profileData = @()

foreach ($prof in $targetProfiles) {

    Write-Section ("Profile: {0} ({1})" -f $prof.UserName, $prof.ProfilePath)

    $profBin  = Join-Path $recycleBin $prof.Sid
    $profDownloads = Get-ProfileDownloadsPath -TargetProfile $prof
    $profOneDrive  = Get-ProfileOneDrivePath -TargetProfile $prof

    # Temp: the profile default, plus the profile's own TEMP setting when it
    # points somewhere else ($env:TEMP for the current user; the hive, read
    # unexpanded and remapped, for others). Paths nested under one already in
    # the list are dropped.
    $profTempPaths = @(Join-Path $prof.ProfilePath 'AppData\Local\Temp')
    $extraTemp = $null
    if ($prof.IsCurrentUser) {
        $extraTemp = $env:TEMP
    } elseif ($prof.HiveLoaded) {
        try {
            $envKeyItem = Get-Item -Path "Registry::HKEY_USERS\$($prof.Sid)\Environment" -ErrorAction Stop
            $rawTemp = $envKeyItem.GetValue('TEMP', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $extraTemp = Expand-TargetProfileValue -Raw $rawTemp -ProfilePath $prof.ProfilePath
        } catch { }
    }
    if ($extraTemp) {
        $extraOk = $false
        try {
            # Canonicalize before touching disk; never accept UNC or relative values.
            if ([System.IO.Path]::IsPathRooted($extraTemp) -and -not $extraTemp.StartsWith('\\')) {
                $extraTemp = [System.IO.Path]::GetFullPath($extraTemp)
                $extraOk = $true
            }
        } catch { }
        if ($extraOk) {
            # A TEMP redirect into a DIFFERENT user's profile is never trusted
            # (off-profile locations like D:\Temp are legitimate and allowed).
            $usersRoot = (Join-Path $env:SystemDrive 'Users').TrimEnd('\') + '\'
            $extraNorm = $extraTemp.TrimEnd('\') + '\'
            $profNorm = $prof.ProfilePath.TrimEnd('\') + '\'
            if ($extraNorm.StartsWith($usersRoot, [StringComparison]::OrdinalIgnoreCase) -and
                -not $extraNorm.StartsWith($profNorm, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Log ("  NOTE: {0}'s TEMP points into another profile ({1}); ignoring it." -f $prof.UserName, $extraTemp) ([ConsoleColor]::Yellow)
                $extraOk = $false
            }
        }
        if ($extraOk -and -not (Test-NoLinkComponents -Path $extraTemp)) {
            Write-Log ("  NOTE: {0}'s TEMP path passes through a junction/symlink; ignoring it." -f $prof.UserName) ([ConsoleColor]::Yellow)
            $extraOk = $false
        }
        if ($extraOk) {
            # Drop it when either path nests inside the other (a parent would
            # only double-count the report; cleaning it is refused anyway).
            $extraNorm = $extraTemp.TrimEnd('\') + '\'
            $isCovered = $false
            foreach ($known in $profTempPaths) {
                $knownNorm = $known.TrimEnd('\') + '\'
                if ($extraNorm.StartsWith($knownNorm, [StringComparison]::OrdinalIgnoreCase) -or
                    $knownNorm.StartsWith($extraNorm, [StringComparison]::OrdinalIgnoreCase)) {
                    $isCovered = $true
                }
            }
            if (-not $isCovered) { $profTempPaths += $extraTemp }
        }
    }

    Write-Log ("  Recycle Bin:  {0}" -f (Format-Size (Get-FolderSizeBytes -Path $profBin)))
    foreach ($tp in $profTempPaths) {
        Write-Log ("  Temp folder:  {0}  ({1})" -f (Format-Size (Get-FolderSizeBytes -Path $tp)), $tp)
    }

    # Downloads candidates - old installers and archives are the usual space
    # hogs. A Downloads folder that is itself a junction/symlink is skipped:
    # its contents live elsewhere and deletions must not travel through links.
    $candidates = @()
    $downloadsOk = Test-Path -LiteralPath $profDownloads
    if ($downloadsOk) {
        try {
            $dlItem = Get-Item -LiteralPath $profDownloads -Force -ErrorAction Stop
            if (($dlItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $dlItem.LinkType) {
                Write-Log ("  Downloads folder {0} is a junction/symlink; skipping it." -f $profDownloads) ([ConsoleColor]::Yellow)
                $downloadsOk = $false
            }
        } catch { }
    }
    if ($downloadsOk) {
        $cutoffDate = (Get-Date).AddDays(-$DownloadsOlderThanDays)
        $bigDownloads = @(Get-ChildItem -LiteralPath $profDownloads -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge ($DownloadsMinSizeMB * 1MB) } |
            Sort-Object Length -Descending)

        Write-Log ("  Downloads ({0}):" -f $profDownloads)
        if ($bigDownloads.Count -eq 0) {
            Write-Log ("    No files over {0} MB found." -f $DownloadsMinSizeMB)
        } else {
            foreach ($f in $bigDownloads) {
                $tag = '(recent - review manually)'
                if (Test-CloudOnlyFile -File $f) {
                    $tag = '(cloud-only in OneDrive - takes no local space, skipped)'
                } elseif ($f.LastWriteTime -lt $cutoffDate) {
                    $tag = "(older than $DownloadsOlderThanDays days - eligible for -IncludeDownloads)"
                    $candidates += $f
                }
                Write-Log ("    {0,10}  {1:yyyy-MM-dd}  {2}  {3}" -f (Format-Size $f.Length), $f.LastWriteTime, $f.Name, $tag)
            }
            if ($candidates.Count -gt 0) {
                $candidateBytes = ($candidates | Measure-Object -Property Length -Sum).Sum
                Write-Log ("    Eligible for cleanup: {0} across {1} file(s)." -f (Format-Size $candidateBytes), $candidates.Count) ([ConsoleColor]::White)
            }
        }
    } elseif (-not (Test-Path -LiteralPath $profDownloads)) {
        Write-Log ("  Downloads folder not found ({0})." -f $profDownloads) ([ConsoleColor]::Yellow)
    }

    # Largest files in the profile - candidates to move to OneDrive. The
    # inventory is also needed when -Clean -MoveToOneDrive is requested even
    # if the listing itself was skipped.
    $odInfo = Get-ProfileOneDriveInfo -TargetProfile $prof
    $profileInv = $null
    $moveCandidates = @()
    $moveAllowedRoots = @()
    if ((-not $SkipLargeFileScan) -or ($Clean -and $MoveToOneDrive -and $odInfo.HiveReadable -and $odInfo.MoveTarget)) {
        if ($SkipLargeFileScan) {
            Write-Log '  Scanning profile for OneDrive move candidates - this can take a few minutes...' ([ConsoleColor]::DarkGray)
        } else {
            Write-Log ("  Largest {0} files (OneDrive move candidates) - scanning, this can take a few minutes..." -f $TopFiles) ([ConsoleColor]::DarkGray)
        }
        $profileInv = Get-FolderInventory -Root $prof.ProfilePath
    }
    if ($profileInv -and $odInfo.MoveTarget -and $odInfo.HiveReadable) {
        # Only plain user-content folders are in scope for moves.
        foreach ($contentFolder in @('Desktop', 'Documents', 'Pictures', 'Videos', 'Music')) {
            $moveAllowedRoots += (Join-Path $prof.ProfilePath $contentFolder)
        }
        $moveAllowedRoots += $profDownloads
        # A file that -IncludeDownloads will delete is not also a move
        # candidate: deletion takes precedence when both switches are used.
        $dlExclude = @{}
        if ($IncludeDownloads) {
            foreach ($dc in $candidates) { $dlExclude[$dc.FullName] = $true }
        }
        $moveCutoff = (Get-Date).AddDays(-$MoveOlderThanDays)
        $moveCandidates = @($profileInv.Files | Where-Object {
            (-not $dlExclude.ContainsKey($_.FullName)) -and
            (Test-OneDriveMoveCandidate -File $_ -AllowedRoots $moveAllowedRoots -SyncRoots $odInfo.SyncRoots -MinBytes ($MoveMinSizeMB * 1MB) -Cutoff $moveCutoff)
        })
    }
    if ($profileInv -and -not $SkipLargeFileScan) {
        $movePathSet = @{}
        foreach ($mc in $moveCandidates) { $movePathSet[$mc.FullName] = $true }
        $largest = $profileInv.Files |
            Where-Object { -not (Test-CloudOnlyFile -File $_) } |
            Sort-Object Length -Descending |
            Select-Object -First $TopFiles
        foreach ($f in $largest) {
            $tag = ''
            if ($movePathSet.ContainsKey($f.FullName)) { $tag = '  (eligible for -MoveToOneDrive)' }
            Write-Log ("    {0,10}  {1:yyyy-MM-dd}  {2}{3}" -f (Format-Size $f.Length), $f.LastWriteTime, $f.FullName, $tag)
        }
        Write-Log '    Cloud-only OneDrive placeholders excluded; .ost/.pst and AppData files usually should NOT be moved or deleted.' ([ConsoleColor]::DarkGray)
    }
    if ($moveCandidates.Count -gt 0) {
        $moveBytes = ($moveCandidates | Measure-Object -Property Length -Sum).Sum
        Write-Log ("  OneDrive move candidates: {0} file(s), {1} (moved only with -Clean -MoveToOneDrive; space frees after upload)." -f `
            $moveCandidates.Count, (Format-Size $moveBytes)) ([ConsoleColor]::White)
    }

    if ($profOneDrive) {
        Write-Log ("  OneDrive folder: {0}" -f $profOneDrive)
    } else {
        Write-Log '  OneDrive: not set up for this profile.' ([ConsoleColor]::Yellow)
    }

    $profileData += New-Object PSObject -Property @{
        Profile            = $prof
        TempPaths          = $profTempPaths
        BinPath            = $profBin
        DownloadsPath      = $profDownloads
        DownloadCandidates = $candidates
        MoveCandidates     = $moveCandidates
        MoveAllowedRoots   = $moveAllowedRoots
        OneDriveInfo       = $odInfo
        OneDrivePath       = $profOneDrive
    }
}

# ------------------------------------------------------------------ clean ---

$totalFreed = [double]0
$totalMoved = [double]0

if ($Clean) {

    # Confirmation state spans ALL profiles: 'Yes to All' / 'No to All' mean
    # the whole run, exactly as the prompts present them. Downloads deletion
    # and OneDrive moves keep separate answers.
    $yesToAll = [bool]$Force
    $noToAll = $false
    $odYesToAll = [bool]$Force
    $odNoToAll = $false

    # --- per-profile cleanup ---
    foreach ($pd in $profileData) {
        $prof = $pd.Profile
        Write-Section ("Cleaning profile: {0}" -f $prof.UserName)

        # 1. Recycle Bin. The current user's bin goes through the shell API;
        #    other users' bins are cleared as folders under C:\$Recycle.Bin\<SID>.
        if ($prof.IsCurrentUser -and ($identity.User.Value -ne 'S-1-5-18')) {
            if ($PSCmdlet.ShouldProcess("Recycle Bin ($($prof.UserName), drive C:)", 'Empty')) {
                $binBefore = Get-FolderSizeBytes -Path $pd.BinPath
                try {
                    Clear-RecycleBin -DriveLetter C -Force -ErrorAction Stop
                } catch {
                    # Clear-RecycleBin throws if the bin is already empty; that's fine.
                    Write-Log "  Recycle Bin: $($_.Exception.Message)" ([ConsoleColor]::DarkGray)
                }
                $binFreed = $binBefore - (Get-FolderSizeBytes -Path $pd.BinPath)
                if ($binFreed -lt 0) { $binFreed = 0 }
                Write-Log ("  Recycle Bin: freed {0}" -f (Format-Size $binFreed)) ([ConsoleColor]::Green)
                $totalFreed += $binFreed
            }
        } else {
            $totalFreed += Clear-FolderContents -Path $pd.BinPath -Label ("Recycle Bin [{0}]" -f $prof.UserName) -OlderThanHours 0
        }

        # 2. Profile temp folder(s).
        foreach ($tp in $pd.TempPaths) {
            $totalFreed += Clear-FolderContents -Path $tp -Label ("Temp [{0}]" -f $prof.UserName) -MustBeTempFolder
        }

        # 3. Downloads - only with the explicit switch, confirmed per file.
        if ($IncludeDownloads) {
            $candidates = @($pd.DownloadCandidates)
            if ($candidates.Count -eq 0) {
                Write-Log ("  Downloads: nothing eligible (over {0} MB and older than {1} days)." -f $DownloadsMinSizeMB, $DownloadsOlderThanDays)
            }
            foreach ($f in $candidates) {
                # Re-check right before acting: the file may have changed, been
                # replaced, or been swapped for a link since the report scan.
                $current = $null
                try { $current = Get-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { }
                $stillEligible = ($current -is [System.IO.FileInfo]) -and
                    (-not ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)) -and
                    (-not (Test-CloudOnlyFile -File $current)) -and
                    ($current.Length -ge ($DownloadsMinSizeMB * 1MB)) -and
                    ($current.LastWriteTime -lt (Get-Date).AddDays(-$DownloadsOlderThanDays))
                if (-not $stillEligible) {
                    Write-Log ("  Skipped (missing or changed since the scan): {0}" -f $f.Name) ([ConsoleColor]::Yellow)
                    continue
                }
                $desc = "{0}\{1} ({2}, last modified {3:yyyy-MM-dd})" -f $prof.UserName, $current.Name, (Format-Size $current.Length), $current.LastWriteTime
                $doDelete = $yesToAll
                if ($WhatIfPreference) {
                    # Don't prompt during a dry run; let ShouldProcess print the What-if line.
                    $doDelete = $true
                } elseif (-not $yesToAll -and -not $noToAll) {
                    try {
                        $doDelete = $PSCmdlet.ShouldContinue("Delete $desc?", 'Downloads cleanup', [ref]$yesToAll, [ref]$noToAll)
                    } catch {
                        # Non-interactive host (RMM/scheduled task) cannot prompt.
                        Write-Log '  Host cannot prompt for confirmation; keeping all files. Use -Force for unattended runs.' ([ConsoleColor]::Yellow)
                        $doDelete = $false
                        $noToAll = $true
                    }
                }
                if ($doDelete -and $PSCmdlet.ShouldProcess($current.FullName, 'Delete download')) {
                    $len = $current.Length
                    Remove-Item -LiteralPath $current.FullName -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path -LiteralPath $current.FullName)) {
                        Write-Log ("  Deleted: {0} ({1})" -f $current.Name, (Format-Size $len)) ([ConsoleColor]::Green)
                        $totalFreed += $len
                    } else {
                        Write-Log ("  Could not delete: {0}" -f $current.Name) ([ConsoleColor]::Yellow)
                    }
                } elseif (-not $doDelete) {
                    Write-Log ("  Kept: {0}" -f $f.Name)
                }
            }
        }

        # 4. Move large old user files into OneDrive - only with the explicit
        #    switch. Space is freed after OneDrive uploads and dehydrates them.
        if ($MoveToOneDrive) {
            $odi = $pd.OneDriveInfo
            $moveList = @($pd.MoveCandidates)
            if (-not $odi.HiveReadable) {
                Write-Log '  OneDrive move: cannot verify this profile''s sync folders (user not signed in); skipping moves for this profile.' ([ConsoleColor]::Yellow)
            } elseif (-not $odi.MoveTarget) {
                Write-Log '  OneDrive move: no usable OneDrive folder was found for this profile; skipping.' ([ConsoleColor]::Yellow)
            } elseif ($moveList.Count -eq 0) {
                Write-Log ("  OneDrive move: nothing eligible (over {0} MB, older than {1} days, in the standard user-content folders)." -f $MoveMinSizeMB, $MoveOlderThanDays)
            } elseif (-not (Test-NoLinkComponents -Path $odi.MoveTarget)) {
                Write-Log '  OneDrive move: the OneDrive path passes through a junction/symlink; skipping.' ([ConsoleColor]::Yellow)
            } else {
                # Files On-Demand disabled by policy means moved files can never
                # dehydrate - the move would free no local space.
                $fodDisabled = $false
                try {
                    $odPolicy = Get-Item -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\OneDrive' -ErrorAction Stop
                    if (($odPolicy.GetValue('FilesOnDemandEnabled', $null)) -eq 0) { $fodDisabled = $true }
                } catch { }
                if ($fodDisabled) {
                    Write-Log '  NOTE: Files On-Demand is disabled by policy - moved files will stay on this disk and free no local space.' ([ConsoleColor]::Yellow)
                }
                if ($prof.IsCurrentUser) {
                    if (-not (Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)) {
                        Write-Log '  NOTE: OneDrive is not running; moved files upload when OneDrive next starts for this profile.' ([ConsoleColor]::Yellow)
                    }
                } else {
                    Write-Log '  NOTE: OneDrive upload state was not verified for this profile; files upload when OneDrive next syncs.' ([ConsoleColor]::DarkGray)
                }
                $archiveRoot = Join-Path $odi.MoveTarget ("Moved from {0}" -f $env:COMPUTERNAME)
                $profRootTrim = $prof.ProfilePath.TrimEnd('\')
                $moveCutoff = (Get-Date).AddDays(-$MoveOlderThanDays)
                foreach ($f in $moveList) {
                    # Re-check right before acting, same as Downloads deletion.
                    $current = $null
                    try { $current = Get-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { }
                    $stillEligible = ($current -is [System.IO.FileInfo]) -and
                        (Test-OneDriveMoveCandidate -File $current -AllowedRoots $pd.MoveAllowedRoots -SyncRoots $odi.SyncRoots -MinBytes ($MoveMinSizeMB * 1MB) -Cutoff $moveCutoff)
                    if (-not $stillEligible) {
                        Write-Log ("  Skipped (missing or changed since the scan): {0}" -f $f.Name) ([ConsoleColor]::Yellow)
                        continue
                    }
                    $rel = $current.FullName.Substring($profRootTrim.Length).TrimStart('\')
                    $dest = Join-Path $archiveRoot $rel
                    if (Test-Path -LiteralPath $dest) {
                        # Never assume an existing destination IS this file: it
                        # may be a partial copy from an interrupted earlier move.
                        $existing = $null
                        try { $existing = Get-Item -LiteralPath $dest -Force -ErrorAction Stop } catch { }
                        if (($existing -is [System.IO.FileInfo]) -and ($existing.Length -eq $current.Length)) {
                            Write-Log ("  Skipped (a same-size copy is already in OneDrive): {0}" -f $rel)
                            continue
                        }
                        $collisionDir = Split-Path $dest -Parent
                        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($dest)
                        $extName = [System.IO.Path]::GetExtension($dest)
                        $alt = $null
                        for ($n = 1; $n -le 9; $n++) {
                            $candidatePath = Join-Path $collisionDir ("{0} ({1}){2}" -f $baseName, $n, $extName)
                            if (-not (Test-Path -LiteralPath $candidatePath)) { $alt = $candidatePath; break }
                        }
                        if (-not $alt) {
                            Write-Log ("  Skipped: {0} - OneDrive holds DIFFERENT content under this name (and all fallback names); local file left in place." -f $rel) ([ConsoleColor]::Yellow)
                            continue
                        }
                        Write-Log ("  NOTE: {0} exists in OneDrive with a different size; moving as '{1}'." -f $rel, (Split-Path $alt -Leaf)) ([ConsoleColor]::Yellow)
                        $dest = $alt
                    }
                    $desc = "{0}\{1} ({2}, last modified {3:yyyy-MM-dd})" -f $prof.UserName, $rel, (Format-Size $current.Length), $current.LastWriteTime
                    $doMove = $odYesToAll
                    if ($WhatIfPreference) {
                        # Don't prompt during a dry run; let ShouldProcess print the What-if line.
                        $doMove = $true
                    } elseif (-not $odYesToAll -and -not $odNoToAll) {
                        try {
                            $doMove = $PSCmdlet.ShouldContinue("Move $desc to OneDrive?", 'OneDrive move', [ref]$odYesToAll, [ref]$odNoToAll)
                        } catch {
                            # Non-interactive host (RMM/scheduled task) cannot prompt.
                            Write-Log '  Host cannot prompt for confirmation; moving nothing. Use -Force for unattended runs.' ([ConsoleColor]::Yellow)
                            $doMove = $false
                            $odNoToAll = $true
                        }
                    }
                    if ($doMove -and $PSCmdlet.ShouldProcess($current.FullName, "Move to OneDrive ($dest)")) {
                        $len = $current.Length
                        $destDir = Split-Path $dest -Parent
                        try {
                            if (-not (Test-Path -LiteralPath $destDir)) {
                                New-Item -Path $destDir -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
                            }
                        } catch {
                            Write-Log ("  Could not create destination folder for {0}: {1}" -f $rel, $_.Exception.Message) ([ConsoleColor]::Yellow)
                            continue
                        }
                        # The archive path is user-writable: re-verify no
                        # component is a junction before moving through it.
                        if (-not (Test-NoLinkComponents -Path $destDir)) {
                            Write-Log '  OneDrive move: the archive folder contains a junction/symlink; stopping moves for this profile.' ([ConsoleColor]::Red)
                            break
                        }
                        try {
                            # .NET Move is literal on both sides (no wildcard
                            # semantics) and works across volumes.
                            [System.IO.File]::Move($current.FullName, $dest)
                        } catch {
                            Write-Log ("  Could not move {0}: {1}" -f $rel, $_.Exception.Message) ([ConsoleColor]::Yellow)
                            continue
                        }
                        $movedItem = $null
                        try { $movedItem = Get-Item -LiteralPath $dest -Force -ErrorAction Stop } catch { }
                        if (($movedItem -is [System.IO.FileInfo]) -and ($movedItem.Length -eq $len)) {
                            # Mark "free up space" so OneDrive dehydrates it once uploaded.
                            & attrib.exe +U -P "$dest" 2>&1 | Out-Null
                            if ($LASTEXITCODE -ne 0) {
                                Write-Log ("  NOTE: could not mark {0} as 'free up space'; right-click it in OneDrive after upload." -f $rel) ([ConsoleColor]::Yellow)
                            }
                            Write-Log ("  Moved to OneDrive: {0} ({1})" -f $rel, (Format-Size $len)) ([ConsoleColor]::Green)
                            $totalMoved += $len
                        } else {
                            Write-Log ("  WARNING: {0} did not arrive intact at {1}; check both locations." -f $rel, $dest) ([ConsoleColor]::Red)
                        }
                    } elseif (-not $doMove) {
                        Write-Log ("  Kept: {0}" -f $rel)
                    }
                }
            }
        }
    }

    # --- machine-wide cleanup ---
    Write-Section 'Cleaning machine-wide'

    # Outlook diagnostic logging folders under <SystemDrive>\Temp - every
    # user's, regardless of profile targeting. Runs unelevated too: files the
    # current account cannot delete are simply skipped.
    foreach ($olPath in $outlookLogPaths) {
        # Re-check right before acting: a component could have been swapped
        # for a junction since the report scan.
        if (-not (Test-NoLinkComponents -Path $olPath)) {
            Write-Log ("  SKIP Outlook logging [{0}] - path now passes through a junction/symlink." -f $olPath) ([ConsoleColor]::Yellow)
            continue
        }
        $totalFreed += Clear-FolderContents -Path $olPath -Label ("Outlook logging [{0}]" -f $olPath)
    }

    if ($isAdmin) {
        $totalFreed += Clear-FolderContents -Path $winTemp -Label 'Windows temp' -MustBeTempFolder

        # Windows Update download cache - safe to clear; Windows re-downloads
        # anything it still needs. Only proceed if BOTH update services are
        # confirmed stopped, and always restart whatever we stopped.
        $wuSize = Get-FolderSizeBytes -Path $wuCache
        if ($wuSize -gt 100MB) {
            if ($PSCmdlet.ShouldProcess($wuCache, 'Clear Windows Update download cache')) {
                $stopped = @()
                $stopFailed = $false
                foreach ($svcName in @('wuauserv', 'bits')) {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq 'Running') {
                        try {
                            Stop-Service -Name $svcName -Force -ErrorAction Stop
                            $stopped += $svcName
                        } catch {
                            Write-Log "  Could not stop service $svcName - skipping update-cache cleanup." ([ConsoleColor]::Yellow)
                            $stopFailed = $true
                            break
                        }
                    }
                }
                try {
                    if (-not $stopFailed) {
                        $totalFreed += Clear-FolderContents -Path $wuCache -Label 'Windows Update cache' -OlderThanHours 0
                    }
                } finally {
                    foreach ($svcName in $stopped) {
                        Start-Service -Name $svcName -ErrorAction SilentlyContinue
                    }
                }
            }
        } else {
            Write-Log ("  Windows Update cache: only {0}, leaving as-is." -f (Format-Size $wuSize)) ([ConsoleColor]::DarkGray)
        }

        # Delivery Optimization cache (peer-to-peer update cache).
        if ($PSCmdlet.ShouldProcess('Delivery Optimization cache', 'Clear')) {
            $doBefore = Get-DriveFreeBytes
            try {
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                $doFreed = (Get-DriveFreeBytes) - $doBefore
                if ($doFreed -lt 0) { $doFreed = 0 }
                Write-Log ("  Delivery Optimization cache: freed {0}" -f (Format-Size $doFreed)) ([ConsoleColor]::Green)
                $totalFreed += $doFreed
            } catch {
                Write-Log ("  Delivery Optimization cache: skipped ({0})" -f $_.Exception.Message) ([ConsoleColor]::DarkGray)
            }
        }
    } else {
        Write-Log '  Skipping Windows temp / update caches (not elevated).' ([ConsoleColor]::Yellow)
    }

    # Optional deep clean (DISM).
    if ($DeepClean) {
        if ($isAdmin) {
            if ($PSCmdlet.ShouldProcess('Windows component store', 'DISM StartComponentCleanup')) {
                Write-Log '  Running DISM component cleanup (this can take 10+ minutes)...' ([ConsoleColor]::DarkGray)
                & dism.exe /Online /Cleanup-Image /StartComponentCleanup | Out-Null
                Write-Log ("  DISM component cleanup finished (exit code {0})." -f $LASTEXITCODE) ([ConsoleColor]::Green)
            }
        } else {
            Write-Log '  Skipping DISM (not elevated).' ([ConsoleColor]::Yellow)
        }
    }

    # Optional hibernation disable.
    if ($DisableHibernation) {
        if ($isAdmin) {
            if ($PSCmdlet.ShouldProcess('Hibernation (hiberfil.sys)', 'Disable')) {
                & powercfg.exe /hibernate off
                Write-Log '  Hibernation disabled; hiberfil.sys will be removed.' ([ConsoleColor]::Green)
            }
        } else {
            Write-Log '  Skipping hibernation change (not elevated).' ([ConsoleColor]::Yellow)
        }
    }
}

# ---------------------------------------------------------------- summary ---

Write-Section 'Summary'
$freeAfter = Get-DriveFreeBytes
if ($Clean) {
    if ($WhatIfPreference) {
        Write-Log '  Dry run (-WhatIf): nothing was changed. Temp folders show "would free" estimates above;' ([ConsoleColor]::White)
        Write-Log '  for the other areas, see their sizes in the report section.' ([ConsoleColor]::White)
    } else {
        Write-Log ("  Free space before:        {0}" -f (Format-Size $freeBefore)) ([ConsoleColor]::White)
        Write-Log ("  Free space after:         {0}" -f (Format-Size $freeAfter)) ([ConsoleColor]::White)
        Write-Log ("  Freed by cleanup steps:   {0}" -f (Format-Size $totalFreed)) ([ConsoleColor]::Green)
        if ($totalMoved -gt 0) {
            Write-Log ("  Moved to OneDrive:        {0}  (frees space only after upload completes and files dehydrate)" -f (Format-Size $totalMoved)) ([ConsoleColor]::Green)
        }
        # The net figure can differ from the step total (or even go negative)
        # if other processes wrote to disk during the run.
        Write-Log ("  Net free-space change:    {0}" -f (Format-Size ($freeAfter - $freeBefore))) ([ConsoleColor]::White)
    }
} else {
    Write-Log '  Report-only run - nothing was changed. Re-run with -Clean to free space.' ([ConsoleColor]::White)
}

Write-Log ''
Write-Log 'Large personal files can be moved to OneDrive with -Clean -MoveToOneDrive, or manually:' ([ConsoleColor]::White)
foreach ($pd in $profileData) {
    if ($pd.OneDrivePath) {
        Write-Log ("  {0}: move files into {1}, wait for the sync check-mark, then right-click > Free up space." -f $pd.Profile.UserName, $pd.OneDrivePath)
    } else {
        Write-Log ("  {0}: OneDrive not set up - sign into the OneDrive app first." -f $pd.Profile.UserName) ([ConsoleColor]::Yellow)
    }
}
