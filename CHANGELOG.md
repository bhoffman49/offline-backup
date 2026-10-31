# Changelog

## 0.9.0 - 2026-10-30 - first public beta

- Copies the folders you choose to USB drives labelled `OFFLINE-A`, `OFFLINE-B`, ... with robocopy: a mirror
  per folder under `<letter>-mirror\<name>`, from any local drive.
- Each drive knows what it is for: `OFFLINE-BACKUP.ini` on the drive holds an id, a description, the folders it
  backs up and its last 50 copies. A new drive is set up in the Drives window and is not copied to before that.
- Preview before every copy: files to add, update, move and delete, folders to add and delete - Copy or Cancel.
- Moved and renamed files (and renamed folders) are recognised and moved on the drive instead of copied again.
- Files about to be overwritten or deleted are kept in `_versions\<date>\` first; old sets are pruned after a
  number of days, or sooner when the drive gets full.
- Safety check: asks first when an unusually large share of a folder would change or be deleted.
- CRC32 and MD5 of every copied file are kept on the drive, plus an ExactFile-style `.md5` next to each folder.
  **Verify drive** reads everything back and checks it; bad files are copied again at the next copy.
  **Check MD5...** checks any `.md5` file.
- Unticking a folder leaves its copy as it is; removing it from a drive's list moves its copy to `_versions`.
- Missing source folders: skip them or stop - the app asks.
- Settings: starting folders, excluded folders, safety limits, version retention, log file. Portable (an INI next
  to the exe).
- Lives in the tray; notices OFFLINE drives being plugged in; progress panel; a summary window when a run ends.
