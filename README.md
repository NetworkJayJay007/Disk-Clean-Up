# Disk Clean-Up

PowerShell script for freeing space on a full C: drive on any Windows 10/11
machine — built for the recurring "disk is full" monitoring alert.

## Why

The usual first-response steps for a full C: drive (disable hibernation,
delete temp files, run DISM component cleanup) often recover only a couple of
GB. The space that actually matters is usually:

- a Recycle Bin that was never emptied,
- large old files sitting in Downloads (1 GB+ installers, ISOs, and zip
  archives that were used once),
- and large personal files that belong in OneDrive rather than on the local
  disk.

This script reports on and automates those steps so a full-disk ticket doesn't
need a manual walkthrough — including when a tech is elevated with different
credentials or the run comes from RMM as SYSTEM.

## Usage

Run from an **elevated** PowerShell window. By default the script targets the
profile of the account running it; use `-TargetUser` or `-AllUsers` when that
isn't the profile you mean to clean (e.g. a tech elevated with admin
credentials on a user's laptop, or an RMM agent running as SYSTEM — the script
detects both cases and suggests the right switch).

```powershell
# 1. Report only - see what's using space, nothing is deleted
.\Invoke-DiskCleanup.ps1

# 2. Report against a specific user's profile (tech elevated with admin creds)
.\Invoke-DiskCleanup.ps1 -TargetUser jsmith

# 3. Safe cleanup of that user's Recycle Bin + temp, plus machine-wide caches
.\Invoke-DiskCleanup.ps1 -Clean -TargetUser jsmith

# 4. Also remove their old, large Downloads files (asks before each file)
.\Invoke-DiskCleanup.ps1 -Clean -TargetUser jsmith -IncludeDownloads

# 5. Every profile on the machine
.\Invoke-DiskCleanup.ps1 -Clean -AllUsers

# 6. Unattended via RMM/SYSTEM, all profiles, 1 GB+ Downloads files older than 90 days
#    (-Force is required for unattended runs - a non-interactive host can't answer prompts)
.\Invoke-DiskCleanup.ps1 -Clean -AllUsers -IncludeDownloads -Force -DownloadsMinSizeMB 1000

# Dry run - print every deletion -Clean would make, without doing any
.\Invoke-DiskCleanup.ps1 -Clean -WhatIf
```

If script execution is blocked, launch with:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Invoke-DiskCleanup.ps1
```

## What it does

| Area | Report mode | `-Clean` mode |
|---|---|---|
| Recycle Bin | shows size per targeted profile | empties per profile: shell API for the current user, `C:\$Recycle.Bin\<SID>` contents for others |
| Profile temp (`AppData\Local\Temp`, plus the profile's own `TEMP` setting if repointed) | shows size per profile | deletes files older than 24 h (checked per file, at every depth) |
| Windows temp | shows size *(admin)* | same age rule *(admin)* |
| Windows Update cache | shows size *(admin)* | clears `SoftwareDistribution\Download` when over 100 MB, only if wuauserv/BITS stop cleanly *(admin)* |
| Delivery Optimization cache | — | clears *(admin)* |
| Downloads | per profile: lists files over 500 MB, flags ones older than 90 days | deletes flagged files only with `-IncludeDownloads`, confirmed per file unless `-Force` |
| Largest files in profile | top 25 per profile as OneDrive-move candidates (cloud-only placeholders excluded) | same (report only) |
| hiberfil.sys / Windows.old | reports if present | hibernation off only with `-Clean -DisableHibernation` |
| DISM component cleanup | — | only with `-Clean -DeepClean` |

Every run writes a timestamped log to `%USERPROFILE%\DiskCleanup-Logs`
(`%ProgramData%\DiskCleanup-Logs` when running as SYSTEM, so RMM logs are
findable).

## Targeting profiles

- **Default:** the account running the script.
- **`-TargetUser <name>`:** one specific profile. A domain-qualified name
  (`DOMAIN\jsmith`) must match the account exactly; a bare name (`jsmith`)
  matches the short account name or the profile folder name under `C:\Users`.
  Requires elevation (unless it resolves to yourself).
- **`-AllUsers`:** every non-special profile from `Win32_UserProfile`.
  Requires elevation.
- Another user's Downloads/OneDrive/TEMP locations are read from **their**
  registry hive (`HKEY_USERS\<SID>`) when it's loaded (user logged on). Values
  are read **unexpanded** so `%USERPROFILE%` is remapped against *their*
  profile — never the account running the script — and fall back to the
  standard `<profile>\Downloads` path otherwise.
- A Downloads redirect pointing **outside** the target profile is not
  followed — the path is canonicalized first, so `..` segments can't dodge the
  check, paths passing through junctions/symlinks are refused, and
  out-of-profile values (including UNC paths) are never even probed. A TEMP
  redirect into a *different* user's profile is likewise ignored. The script
  never deletes outside the profile being cleaned.
- Other users' Recycle Bins are emptied by clearing their
  `C:\$Recycle.Bin\<SID>` folder — same junction-safe deletion path as
  everything else.

## Safety notes

- Default run is **report-only**; nothing changes without `-Clean`. Cleanup
  switches passed without `-Clean` trigger a warning instead of being silently
  ignored.
- **Junction/symlink safe:** all recursion uses a custom walker that never
  follows junctions or symbolic links. A junction in a temp folder is removed
  as a link only — the folder it points at is never touched — and a cleanup
  target that is itself a junction is refused outright. (On stock
  PowerShell 5.1, `Remove-Item -Recurse` would follow the junction and delete
  its target's contents.) OneDrive cloud folders, which are also reparse
  points, are still walked correctly for the space reports.
- The temp-file age cutoff (24 h) is applied **per file at every depth**, so a
  brand-new file inside an old temp subfolder is left alone; locked files are
  skipped.
- The folder-clearing routine refuses empty paths, drive roots, profile roots,
  and well-known system folders, and requires temp targets to actually be
  named `Temp`/`tmp` — so a repointed `%TEMP%` variable can't wipe a profile.
- User data (Downloads) is never touched without `-IncludeDownloads`, and each
  file is confirmed individually unless `-Force` is given ("Yes to All" / "No
  to All" answers apply to the whole run, across profiles). Every candidate is
  re-checked immediately before deletion — a file that changed, shrank, or was
  swapped for a link since the scan is skipped. Cloud-only OneDrive
  placeholders are never deleted (they take no local space).
- `-WhatIf` is supported on all destructive steps and changes nothing: temp
  folders print "would free ~X" estimates, the other steps print standard
  "What if:" lines (their sizes appear in the report section).
- The Windows Update cache is only cleared when both update services stop
  cleanly, and any service the script stopped is always restarted.
- Moving files to OneDrive is deliberately **not** automated — the script lists
  the largest files per profile and prints instructions, but the user decides
  what moves.
