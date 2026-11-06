# Changelog

## 0.10.0 - 2026-11-06

- **A new window.** A sidebar on the left with one area each - **Backup**, **Drives**, **MD5 check** and
  **Settings** - tabs along the top, the area's buttons on the right and a status bar at the bottom (what is
  happening, and how many OFFLINE drives are plugged in). Drives, MD5 check and Settings are pages of the main
  window now instead of separate windows; the preview and the end-of-run summary still pop up, as they ask
  something. The tray icon and its menu work as before.
- **Progress under the drive list**, with two bars: the file being copied (its name and how far it is) and the
  whole run. Drag the divider to give either more room.
- Changes on the Drives and Settings pages wait for **Save**; **Undo changes** goes back to what was saved, and
  leaving a page with unsaved changes asks first. While a copy runs, every page can be looked at but not changed.
- **Open MD5 file...** starts in the plugged-in OFFLINE drive's mirror folder, where its `.md5` files are;
  **Check again** checks the same file again.
- Settings shows where VeraCrypt was found and where the settings file is kept.
- **Recording checksums** after a copy shows its progress: the file being read, files and bytes done, the reading
  rate and time left. On a first copy this step reads the whole backup again, so it takes a while.
- New setting, on the **MD5 check** page: **Record checksums after each copy** (on by default). Off, a copy ends
  sooner; its files get no checksum yet (so no move detection and no `.md5` entry for them), the end of the run
  says so, and **Verify drive** records the missing checksums later. Nothing is lost.
- The download (Lazarus edition) is now built with full optimization (-O3): checksums are computed about 1.6
  times faster (about 300 instead of 190 MB/s on the test PC), which shortens recording checksums, Verify drive
  and MD5 check whenever the drive or PC's disk is faster than that.
- With the window open, plugging in a drive says so in the status bar and flashes the taskbar button (the balloon
  is still only for when the window is hidden); a drive that goes away (unplugged or dismounted) is said in the
  status bar and the log.
- **About Offline Backup...** in the window's title-bar menu (click the icon at the top left, or Alt+Space):
  the version, the developer and links to the website and the source code.
- **The window opens when Offline Backup starts**, so it is plain that it is running; closing it keeps the program
  in the tray as before. Start it with `/tray` (for example from a shortcut in the Startup folder) to start in the
  tray only. `/show` is no longer needed.

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
