<# 
    PwshBkp.ps1
    Backup & restore config folders with a menu.

    MENU:
        1) Backup item
        2) Backup all
        3) Restore item
        4) Restore all
        5) Show backup items and paths
        6) Show restore items and paths
        7) Script Documentation
        8) Quit

    ZIP POLICY (simple & robust)
    - Backup always produces a *folder* at Desktop\PwshBkp_YYMMDD.
    - Then it also creates Desktop\PwshBkp_YYMMDD.zip for archival.
    - The ZIP includes this script file (if available).
    - Restore ONLY works from a real folder. If you have a ZIP, unzip it first.

    USER-DIR RESTORE SET (used by Restore All / Restore Item):
        PowerShell        -> C:\Users\<user>\Documents\PowerShell
        WindowsTerminal   -> C:\Users\<user>\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState
        Everything        -> C:\Users\<user>\AppData\Roaming\Everything
        Calibre           -> C:\Users\<user>\AppData\Roaming\calibre
        Links             -> C:\Users\<user>\Links
        SSH               -> C:\Users\<user>\.ssh
#>

# -------- Settings --------
$UserDesktop = [Environment]::GetFolderPath('Desktop')
$TodayStamp  = (Get-Date).ToString('yyMMdd')
$DefaultBackupRoot = Join-Path $UserDesktop "PwshBkp_$TodayStamp"
$DefaultZipPath    = "$DefaultBackupRoot.zip"
$UserHome = $env:USERPROFILE

# Toggle if you ever want to skip zip creation
$CreateZip = $true

# Included paths (Key = logical name -> Value = path)
$IncludePaths = [ordered]@{
    "PowerShell"      = Join-Path $env:USERPROFILE "Documents\PowerShell"
    "WindowsTerminal" = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    "Everything"      = Join-Path $env:APPDATA      "Everything"
    "Calibre"         = Join-Path $env:APPDATA      "calibre"
    "Links"           = Join-Path $env:USERPROFILE  "Links"
    "SSH"             = Join-Path $env:USERPROFILE  ".ssh"
    "ObsidianConfig"  = "D:\Home\Files\Obsidian\Nxor-Remote\.obsidian"
    "Scripts"         = "D:\Home\Files\Scripts"
}

function Get-UserItems {
    $IncludePaths.Keys | Where-Object {
        $path = $IncludePaths[$_]
        try {
            $full = [IO.Path]::GetFullPath($path)
            $full.StartsWith([IO.Path]::GetFullPath($UserHome), [StringComparison]::OrdinalIgnoreCase)
        } catch { $false }
    }
}

# -------- Documentation text (shown in menu) --------
$ScriptDocumentation = @"
SCRIPT DOCUMENTATION
====================
What this does
--------------
- Backs up your config folders into Desktop\PwshBkp_YYMMDD (each item to its own subfolder).
- Also creates Desktop\PwshBkp_YYMMDD.zip that INCLUDES THIS SCRIPT for convenience.
- Restores from a chosen backup *folder* (not directly from .zip).

Backup
------
- "Backup item": choose one logical item to copy into today's backup folder.
- "Backup all": copies all IncludePaths into today's backup folder.
- After copying, a .zip is created next to the folder; the script file is copied into the folder before zipping.

Restore
-------
- Auto-detects backup root in this order:
    1) If the script lives inside a PwshBkp_* folder anywhere, use that.
    2) Newest PwshBkp_* on your Desktop.
    3) Otherwise, you're prompted to enter a path.
- "Restore item": choose one user-dir item to restore.
- "Restore all": restores all user-dir items.
- You must unzip if you only have a .zip; restore reads real folders.

Safe to edit
------------
- Edit `$IncludePaths` to add/remove items.
- Restore never deletes; it copies over with robocopy, preserving timestamps/attrs.

"@

# -------- Helpers --------
function Write-Title($text) {
    Write-Host ""
    Write-Host "========= $text =========" -ForegroundColor Cyan
}

function Confirm($message) {
    $ans = Read-Host "$message [y/N]"
    return ($ans -match '^(y|yes)$')
}

function New-DirectoryIfMissing($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Get-LatestBackupRootOnDesktop {
    Get-ChildItem -LiteralPath $UserDesktop -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'PwshBkp_*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName -ErrorAction SilentlyContinue
}

function Find-AncestorBackupRoot([string]$startPath) {
    try {
        $cur = [IO.Path]::GetFullPath($startPath)
    } catch { return $null }
    while ($cur -and (Test-Path -LiteralPath $cur)) {
        $leaf = Split-Path $cur -Leaf
    if ($leaf -like 'PwshBkp_*') { return $cur }
        $parent = Split-Path $cur -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $cur)) { break }
        $cur = $parent
    }
    return $null
}

function Get-ScriptDirectory {
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    elseif ($PSScriptRoot) { return $PSScriptRoot }
    else { return (Get-Location).Path }
}

function Select-BackupRoot([switch]$SilentIfDetected) {
    $scriptDir = Get-ScriptDirectory
    $fromScript = Find-AncestorBackupRoot -startPath $scriptDir
    if ($fromScript) {
        if (-not $SilentIfDetected) {
            Write-Host "Detected backup folder from script location: $fromScript"
            if (Confirm "Use this backup folder?") { return $fromScript }
        } else {
            return $fromScript
        }
    }

    $latestDesktop = Get-LatestBackupRootOnDesktop
    if ($latestDesktop) {
        Write-Host "Detected latest Desktop backup folder: $latestDesktop"
        if (Confirm "Use this backup folder?") { return $latestDesktop }
    } else {
        Write-Warning "No PwshBkp_* folder found on Desktop."
    }

    do {
        $custom = Read-Host "Enter path to a backup folder (e.g. $DefaultBackupRoot)"
        if ([string]::IsNullOrWhiteSpace($custom)) { continue }
        if (Test-Path -LiteralPath $custom) { return $custom }
        Write-Warning "Path not found. Try again."
    } while ($true)
}

function Copy-WithRobocopy($Source, $Dest) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Warning "Missing source: $Source"
        return
    }
    New-DirectoryIfMissing $Dest

    $robocopyParams = @(
        "`"$Source`"", "`"$Dest`"",
        "/E", "/COPY:DAT", "/DCOPY:DAT",
        "/R:1", "/W:2",
        "/NFL", "/NDL", "/NP", "/XJ"
    )

    $p = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyParams -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ge 8) {
        Write-Error "Robocopy failed for `"$Source`" -> `"$Dest`" with code $($p.ExitCode)"
    } else {
        Write-Host "Copied: $Source -> $Dest"
    }
}

function Select-BackupItem([string[]]$Keys) {
    if (-not $Keys -or $Keys.Count -eq 0) {
        Write-Warning "No items available."
        return $null
    }
    Write-Host ""
    for ($i=0; $i -lt $Keys.Count; $i++) {
        $k = $Keys[$i]
        $p = $IncludePaths[$k]
        Write-Host ("{0,2}) {1,-16}  {2}" -f ($i+1), $k, $p)
    }
    $sel = Read-Host "Choose item number"
    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $Keys.Count) {
        return $Keys[[int]$sel - 1]
    } else {
        Write-Warning "Invalid selection."
        return $null
    }
}

# -------- Display / Plans --------
function Show-IncludedPaths {
    Write-Title "Included Backup Paths"
    $IncludePaths.GetEnumerator() | ForEach-Object {
        $exists = if (Test-Path -LiteralPath $_.Value) { "✓" } else { "✗" }
        "{0,-16}  {1}  {2}" -f $_.Key, $exists, $_.Value
    } | Write-Host
}

function Show-RestorePaths {
    Write-Title "Restore Items and Paths (User Dir Items)"
    $detected = Select-BackupRoot -SilentIfDetected
    if ($detected) {
        Write-Host "Using backup root: $detected"
    } else {
        Write-Host "No backup root auto-detected. You'll be asked during actual restore."
    }
    foreach ($k in (Get-UserItems)) {
        $target = $IncludePaths[$k]
        $hasSrc = $false
        if ($detected) {
            $src = Join-Path $detected $k
            $hasSrc = Test-Path -LiteralPath $src
        }
        $mark = if ($hasSrc) { "✓" } else { " " }
        Write-Host ("{0,-16}  {1}  {2}" -f $k, $mark, $target)
    }
    if ($detected) {
        Write-Host "`nLegend: ✓ = corresponding source exists in backup root"
    }
}

# -------- ZIP Helpers --------
function Add-ScriptToBackup([string]$BackupRoot) {
    try {
        if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
            $destFile = Join-Path $BackupRoot (Split-Path $PSCommandPath -Leaf)
            Copy-Item -LiteralPath $PSCommandPath -Destination $destFile -Force
            Write-Host "Included script in backup: $destFile"
        } else {
            Write-Warning "Script path unavailable; cannot include script in backup."
        }
    } catch {
        Write-Warning "Failed to include script: $($_.Exception.Message)"
    }
}

function Compress-BackupToZip([string]$BackupRoot, [string]$ZipPath) {
    try {
        if (Test-Path -LiteralPath $ZipPath) {
            Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
        }
        # Zip the CONTENTS of the backup folder (not the parent)
        Compress-Archive -Path (Join-Path $BackupRoot '*') -DestinationPath $ZipPath -Force
        Write-Host "Created archive: $ZipPath"
    } catch {
        Write-Warning "Failed to create zip: $($_.Exception.Message)"
    }
}

# -------- Core Ops --------
function Start-Backup {
    param([string]$BackupRoot = $DefaultBackupRoot)
    Write-Title "Backup All"
    Write-Host "Target: $BackupRoot"
    New-DirectoryIfMissing $BackupRoot
    foreach ($kvp in $IncludePaths.GetEnumerator()) {
        $name = $kvp.Key
        $src  = $kvp.Value
        $dest = Join-Path $BackupRoot $name
        Copy-WithRobocopy -Source $src -Dest $dest
    }

    if ($CreateZip) {
        Add-ScriptToBackup -BackupRoot $BackupRoot
        Compress-BackupToZip -BackupRoot $BackupRoot -ZipPath $DefaultZipPath
    }

    Write-Host "`nBackup completed." -ForegroundColor Green
}

function Start-BackupItem {
    param([string]$BackupRoot = $DefaultBackupRoot)
    $key = Select-BackupItem -Keys $IncludePaths.Keys
    if (-not $key) { return }
    Write-Title "Backup Item: $key"
    Write-Host "Target: $BackupRoot"
    New-DirectoryIfMissing $BackupRoot
    $src  = $IncludePaths[$key]
    $dest = Join-Path $BackupRoot $key
    Copy-WithRobocopy -Source $src -Dest $dest

    if ($CreateZip) {
        Add-ScriptToBackup -BackupRoot $BackupRoot
        Compress-BackupToZip -BackupRoot $BackupRoot -ZipPath $DefaultZipPath
    }

    Write-Host "`nBackup of $key completed." -ForegroundColor Green
}

function Restore-One {
    param(
        [string]$BackupRoot,
        [string]$Key,
        [switch]$SilentConfirm
    )
    if (-not $IncludePaths.Contains($Key)) {
        Write-Warning "Unknown key: $Key"
        return
    }
    $src  = Join-Path $BackupRoot $Key
    $dest = $IncludePaths[$Key]

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "Backup missing for $Key at $src"
        return
    }

    Write-Title "Restore $Key"
    Write-Host "Source : $src"
    Write-Host "Target : $dest"
    if (-not $SilentConfirm) {
        if (-not (Confirm "Restore and overwrite existing files if needed?")) { 
            Write-Host "Skipped $Key."
            return
        }
    }
    Copy-WithRobocopy -Source $src -Dest $dest
    Write-Host "Restore of $Key done." -ForegroundColor Green
}

function Show-RestoreAllPlan {
    Write-Title "Restore All (User Dir Items)"
    foreach ($k in (Get-UserItems)) {
        $p = $IncludePaths[$k]
        Write-Host ("{0,-16}  ✓  {1}" -f $k, $p)
    }
}

function Restore-All {
    $userItems = Get-UserItems
    if (-not $userItems -or $userItems.Count -eq 0) {
        Write-Warning "No user-dir items found to restore."
        return
    }

    # Informative check for a Desktop backup
    $desktopCandidate = Get-LatestBackupRootOnDesktop
    if ($desktopCandidate) {
        Write-Host "Found PwshBkp_* on Desktop: $desktopCandidate"
    } else {
        Write-Warning "No PwshBkp_* found on Desktop."
    }

    Show-RestoreAllPlan
    $backupRoot = Select-BackupRoot
    Write-Host ""
    if (-not (Confirm "Restore ALL listed items from `"$backupRoot`"? (Overwrites when needed)")) {
        Write-Host "Restore all canceled."
        return
    }

    foreach ($k in $userItems) {
        Restore-One -BackupRoot $backupRoot -Key $k -SilentConfirm
    }
    Write-Host "`nRestore all completed." -ForegroundColor Green
}

function Restore-Item {
    $keys = Get-UserItems
    $key = Select-BackupItem -Keys $keys
    if (-not $key) { return }

    $desktopCandidate = Get-LatestBackupRootOnDesktop
    if ($desktopCandidate) {
        Write-Host "Found PwshBkp_* on Desktop: $desktopCandidate"
    } else {
        Write-Warning "No PwshBkp_* found on Desktop."
    }

    $backupRoot = Select-BackupRoot
    Restore-One -BackupRoot $backupRoot -Key $key
}

function Show-Documentation {
    Write-Title "Script Documentation"
    $ScriptDocumentation | Write-Host
}

# -------- Menu --------
function Show-MainMenu {
    do {
        Write-Title "PwshBkp Menu"
        Write-Host "1) Backup item"
        Write-Host "2) Backup all"
        Write-Host "3) Restore item"
        Write-Host "4) Restore all"
        Write-Host "5) Show backup items and paths"
        Write-Host "6) Show restore items and paths"
        Write-Host "7) Script Documentation"
        Write-Host "8) Quit"
        $choice = Read-Host "Choose option"

        switch ($choice) {
            '1' { Start-BackupItem }
            '2' { Start-Backup }
            '3' { Restore-Item }
            '4' { Restore-All }
            '5' { Show-IncludedPaths }
            '6' { Show-RestorePaths }
            '7' { Show-Documentation }
            '8' { return }  # <-- This exits the function immediately
            default { Write-Warning "Invalid selection." }
        }
    } while ($true)
}

# Entry
Show-MainMenu
