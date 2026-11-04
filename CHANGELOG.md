# Changelog

## 0.9.2 - 2026-11-03

- VeraCrypt: OFFLINE drives that are mounted VeraCrypt volumes are marked `[VeraCrypt]`, and a **Dismount**
  button (also on the tray menu) asks VeraCrypt to dismount them - never forced, so open files are reported
  instead. After a copy such a drive says "dismount it in VeraCrypt, then unplug" rather than "safe to unplug".
- New setting: **Dismount VeraCrypt drives after a copy that went well** (off by default). `VeraCryptExe=` in the
  INI for a portable VeraCrypt.
- README: how to set up an encrypted backup drive with VeraCrypt.

## 0.9.1 - 2026-11-02

- Fixed: on exFAT and FAT32 drives (how most USB sticks come), about a third of the copied files got no
  checksum - so they were left out of Verify and of the `.md5` files - and moved files were copied again instead
  of moved. These drives keep file times in 2-second steps; checksums and move detection now allow for that,
  as robocopy does. Files copied by 0.9.0 without a checksum get one at the next **Verify drive**.
- Tested with a VeraCrypt volume labelled `OFFLINE-X`: encrypted drives work like any other OFFLINE drive.

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
