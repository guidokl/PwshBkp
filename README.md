# 💾 PwshBkp.ps1

A PowerShell backup script to quickly copy files and directories to a given location.

---

## 🖼️ Screenshot

<img src="assets/screenshot.png" alt="PwshBkp.ps1 Menu Screenshot" width="100%" />

---

## 📌 What This Does

- Backs up your config folders into `Desktop\PwshBkp_YYMMDD` (each item gets its own subfolder).
- Also creates `Desktop\PwshBkp_YYMMDD.zip` that **includes this script** for convenience.
- Restores from a chosen backup **folder** (not directly from `.zip`).

---

## ⚙️ Configure

Before running the script, adjust the included paths to match your environment.

- All paths to be backed up are defined in the `$IncludePaths` variable.  
- Each entry uses a **logical name** (key) mapped to its **actual filesystem path** (value).  
- You can add, remove, or modify entries as needed.  
- Restore operations are **non-destructive**: files are copied with `robocopy`, preserving timestamps and attributes, but nothing is deleted.

Example configuration in PwshBkp.ps1 (customize for your needs):

```powershell
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
```

---

## 📥 Backup

- **Backup item** – choose one logical item to copy into today's backup folder.
- **Backup all** – copies all `$IncludePaths` into today's backup folder.
- After copying:
  - The script file is copied into the folder.
  - A `.zip` is created next to the folder.

---

## ♻️ Restore

- Auto-detects backup root in this order:
  1. If the script lives inside a `PwshBkp_*` folder anywhere, use that.
  2. Newest `PwshBkp_*` folder on your Desktop.
  3. Otherwise, you’re prompted to enter a path.
- **Restore item** – choose one user-dir item to restore.
- **Restore all** – restores all user-dir items.
- **Note:** You must unzip if you only have a `.zip`; restore works on folders.

---

## 🛠️ To-Do & Contribution

- Add incremental backup support.
- Option to keep a fixed number of backups in a chosen folder.

If you find bugs or have ideas for improvements, please open an issue.  
Pull requests are always welcome!

---
