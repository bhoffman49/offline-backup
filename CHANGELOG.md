# Changelog

## 0.12.0 - 2026-11-25

- **Checksums are read several files at once**, like ExactFile: making a list in the **Checksum Applet**, the **MD5
  check** page, **Verify drive**, recording the checksums after a copy, and the `checksum.exe` the Checksum Applet
  makes. As many files are read at the same time as the PC has logical
  processors, less two (so the PC stays usable; the readers also run at a lower priority), and one at a time on a
  drive that says it is a spinning disk. Lists, reports and the log come out exactly as before, in list order. On
  this PC (20 logical processors, NVMe SSD, 6,000 files / 9 GB, MD5) the MD5 check went from 38 s to 6 s and the
  Checksum Applet list from 27 s to 3 s; a USB drive is mostly limited by the drive itself. The copy itself is
  still robocopy, one file at a time.
- **The files being read right now** are shown under the drive list during an MD5 check, Verify drive and recording
  checksums: each with a bar of how far it is, the biggest first, as many as fit.
- **Time taken** on the MD5 check page's Summary tab, with how much was read and how fast.
- The log lines of an MD5 check and Verify drive say how many files were read at once.
- Fixed: files with paths longer than 260 characters could not be read by Verify drive, the MD5 check, recording
  checksums or the Checksum Applet (robocopy copied them fine), and a list made for a whole drive also listed
  Windows' hidden `$RECYCLE.BIN` and `System Volume Information` folders.

## 0.11.0 - 2026-11-24

- **Checksum Applet**, a new area at the bottom of the sidebar (from the Checksum Applet Creator): makes a checksum list
  for any folder - 15 algorithms (MD5, SHA1, SHA256/384/512, CRC32, RIPEMD, Tiger and more) in the usual formats
  (hash \*name like ExactFile, md5sum, sha1sum, SFV, FileCheckMD5) - and, if you like, a small `checksum.exe` next
  to it that checks the files on any PC with nothing installed. Its report says when the checksums were created.
- **MD5 check** also checks `.sha1`, `.sha256`, `.sha512`, `.sfv` and the other lists the Checksum Applet area makes,
  and BSD-style `MD5 (name) = ...` lines.
- **Copy report** and **Save report...** on the MD5 check page: the result as text, like ExactFile's report.
- **The archive**: files a copy overwrites or deletes now go to one folder per day inside an `ARCHIVE` folder in
  the drive's root - `ARCHIVE\MMDDYY` (`ARCHIVE\112326` = 23 Nov 2026) - instead of `_versions\<date-time>`. All
  copies on one day
  share it, and a file already archived that day keeps its first copy. A drive's old `_versions` sets are moved into
  the archive of their day at its first copy with 0.11. Settings' tab is now **Safety and archive**.
- Easier to find your way the first time: the Backup page says how to name a drive OFFLINE-A; **Record checksums
  after each copy** moved from the MD5 check page to **Settings > Safety and archive**; the Settings tab *Starting
  folders* is now **Folders for new drives** (and the Drives button **Add folders from Settings**); the drive id moved
  from the top of the Drives page to its History tab; the greyed-out **Restore** button and the unfinished **Prepare a
  new drive...** button are hidden until they work.
- Fixed: with the preview switched off, the safety-check question said something went wrong "on G:" whatever the
  source was.
- **The archive on or off for each folder on a drive** (Drives > Edit..., on by default; a new **Archive** column
  shows it). Off, a copy replaces and deletes that folder's files on the drive straight away instead of archiving
  them. Switching it off asks first, and the preview says so in red. Stored in the drive's map; maps from 0.10
  archive every folder.

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
