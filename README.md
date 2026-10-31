# Offline Backup

A Windows tray app that copies the folders you choose onto rotating offline USB drives labelled `OFFLINE-A`,
`OFFLINE-B`, ... Each drive knows which folders it backs up. It grew out of a PowerShell script
(`Copy-OfflineBackup.ps1`) and keeps that script's behaviour: robocopy mirror, old versions moved to
`<drive>\_versions\<yyyy-mm-dd_hhmm>\` first, a safety brake on unusually large changes, pruning of old
versions, `LAST-COPY.txt` on the drive, and a log file (`offline-copy.log` next to the settings file unless
you choose another place).

Each source folder lands under its own drive letter: `G:\Backups` -> `<drive>\G-mirror\Backups` (where the
script put it), `D:\MUSIC` -> `<drive>\D-mirror\MUSIC`. Old versions keep the same path under
`_versions\<date>\` (sets made before 2026-10-28 23:00 have just `Backups\...`).

It comes in two editions built from one shared engine:

| Edition | Folder | Toolchain | Notes |
|---|---|---|---|
| Delphi VCL | `delphi\` | Delphi 12 (dcc64) | native Win64 exe for daily use |
| Lazarus LCL | `lazarus\` | Lazarus 4.4 / FPC 3.2.2 | free to build; the one to publish |

Only one of the two can run at a time (they share a single-instance mutex).

## Layout

```
common\
  OfflineEngine.pas    the backup itself: drive detection, settings file, dry run, brake, _versions,
                       robocopy with progress, prune, LAST-COPY.txt, flush. No UI code. Compiles under
                       both compilers ({$mode delphiunicode} under FPC).
  DriveWatcher.pas     WM_DEVICECHANGE via its own hidden window (works the same in VCL and LCL)
  OfflineBackup.ico    app + tray icon (made by tools\make-icon.py)
delphi\                VCL edition: OfflineBackup.dpr, MainForm, SettingsForm, SourceForm, DriveForm (.pas/.dfm),
                       .rc + manifest, build.cmd
lazarus\               LCL edition: OfflineBackup.lpi/.lpr, the same four forms (.pas/.lfm), build.cmd
tests\                 EngineTest.dpr - runs the engine against throw-away folders; run-tests.cmd
                       builds and runs it with both compilers
tools\                 make-icon.py, screenshot.ps1
build\                 compiler output (not in git)
```

### Engine / UI split

`TOfflineCopy` (in `OfflineEngine`) does one full run against one drive and reports through three
events: `OnLog`, `OnProgress` and `OnConfirm` (the brake question). `TOfflineCopyThread` runs it in the
background and raises those events on the main thread, so the forms only show things and ask
questions. Everything that decides what happens to the drive is in the shared unit, tested once,
for both editions.

Safety rules kept from the script and enforced in the engine, not the UI:
- only drives labelled `OFFLINE-<A-Z>`, never the drive Windows is on; the label is checked again right
  before copying
- nothing on the drive is touched until the dry run and brake have passed
- anything robocopy would overwrite or delete is moved to `_versions` first (only from inside that
  folder's mirror)
- old-version cleanup removes junctions without following them

## Build

```
delphi\build.cmd        -> build\delphi\OfflineBackup.exe
lazarus\build.cmd       -> build\lazarus\OfflineBackup.exe   (set LAZBUILD if Lazarus is not in F:\lazarus)
tests\run-tests.cmd     -> builds and runs the engine tests with both compilers
```

Both projects also open in their IDEs. In the Delphi IDE, open `delphi\OfflineBackup.dpr`; the IDE
creates a `.dproj` and may regenerate `OfflineBackup.res` with its own icon. Set the icon to
`common\OfflineBackup.ico` in Project Options, or run `build.cmd` again.

## Use

Start `OfflineBackup.exe` (add `/show` to open the window as well). It sits in the tray. When an
`OFFLINE-x` drive is plugged in, it shows a balloon and opens its window. Press **Start copy** to copy
the ticked folders to every OFFLINE drive that is plugged in, one after another. While it copies, the window shows time left,
files done / failed / skipped / total and the transfer rate (also in the tray icon's tooltip). Closing the window only hides it;
**Exit** is on the tray icon's menu.

## Drives

Each OFFLINE drive says for itself what it is for. Its **drive map**, `OFFLINE-BACKUP.ini` at the root, holds:

- a drive id made once at set-up (so two drives with the same label still differ), the label, and what the
  drive is for in your words
- **the folders it backs up**: source folder, name on the drive, ticked or not
- folders taken off its list that are still to be moved to `_versions`
- the newest 50 copies to it (when, PC, result, size, folders)

The app keeps a copy of each map in `drives\<id>.ini` next to its settings, so a lost drive still has a record.

A drive is copied to only when it has a map **with a folder list**. A drive without a map is **new**; a map
without a folder list (written before drives had their own lists) counts as "no folders chosen yet". Both show
in the window, Start copy skips them, and the engine refuses them too.

**Drives...** (window button or tray menu) picks a plugged-in drive and, for that drive:

- **What this drive is for** - a short description
- **Folders this drive backs up** - `source  to  <letter>-mirror\<name>`. **Add folder...** picks any folder on
  a local drive (not network, not an OFFLINE drive); **Add starting folders** adds the folders ticked in
  Settings; **Edit...** changes folder or name.
  - **Unticked**: not updated, its copy stays on the drive as it is.
  - **Remove**: at the next copy (after the dry run and safety check) its copy is moved to
    `_versions\<date>\<letter>-mirror\<name>` and cleared out like other old versions. Changing a folder's
    path or name does the same for the old copy. A removed folder added back before that copy stays.
- **Set up this drive** / **Save** writes the map; nothing else on the drive changes.
- the drive's history, newest first.

When a set-up drive is plugged in, the log shows what it is for, which folders it backs up and how its last
copy went.

### Preview before copying

After the dry run and before anything on the drive changes, a **Preview** window (modelled on ViceVersa's
"Preview: Synchronization") shows per drive: files to add, update and delete, folders to add and delete, and
backup folders being taken off the drive, and **files to move** - with counts and sizes. Clicking a line lists its files (folder, path,
size); "All changes" lists everything. **Copy** goes ahead, **Cancel** leaves the drive untouched ("cancelled at
the preview" in the log). When the safety check would have asked, the preview shows it as a red warning instead.

"Show this preview before every copy" (in the preview and in Settings, on by default): when off, the preview only
appears when something would be deleted or moved on the drive.

**Moved files.** A file moved or renamed inside a backup folder (or a whole folder renamed) is found and shown as
"Files to move" (old path -> new path) instead of one add and one delete: a "new" file counts as a move when a
"deleted" file on the drive has the same size and last-write time, and the new file's CRC32 (and MD5, where
recorded) match the checksum recorded for the drive copy. On Copy it is moved on the drive - instant, nothing copied
again, nothing put in `_versions` - and its checksum moves with it. Same size and time but other content, or a
changed time, stays add + delete. Files with no checksum yet (copied before checksums were kept) can't be matched
until a Verify has recorded one.

### Checksums and Verify drive

Each copied file's **CRC32 and MD5** are recorded on the drive in `_checksums\<letter>-mirror\<name>.crc` (one
line per file: CRC32, size, last-write time, MD5, path), computed in the same read. The MD5s also go to
`<letter>-mirror\<name>.md5` next to each backup folder - the usual `md5 *path` format (with an ExactFile-style
header), so ExactFile, md5sum and similar tools can check a drive without this app. It is taken from the source right after the copy, and only kept if the
source still has the size and time the drive copy has. Files robocopy deletes leave the list; a removed folder's
list goes with it.

**Verify drive...** (in Drives...) reads every file of the drive's folders back from the drive - past the Windows
file cache, so it really is the drive being read - and compares it with its recorded CRC32. It needs nothing from
the PC's folders, so a drive that has sat in a drawer can be checked anywhere. The window shows progress
(Checked / Bad / New checksums) and can be cancelled. Results:

- **ok** - matches.
- **bad** - listed in the log. Its date on the drive is set back to 1990, so the next copy replaces it from the
  source (the bad copy goes to `_versions` like any other old version).
- **no checksum yet** (copied before checksums existed, or changed since) - its checksum is recorded now and
  checked from the next Verify on.

Each Verify goes into the drive's history ("verified ok", "verify: 2 bad"). Lists from before MD5s were kept get
their MD5s (and their `.md5` file) at the next Verify.

**Check MD5...** (main window and tray menu) checks the files listed in any `.md5` file - one of the drive's, or
one made by ExactFile or md5sum (`md5 *path` and `md5  path` lines; `;` and `#` comments; paths relative to the
file's folder). Progress shows Checked / Bad / Missing; the result window lists the files that match, are bad,
missing or unreadable.

## Settings

**Settings...** (window button or tray menu; not while a copy runs) holds what is the same for every drive:

- **Starting folders** - the folders Drives... offers with "Add starting folders" when you set up a drive
  (empty at first - you add your own). The name on the drive is the folder's name, with ` (2)`, ` (3)` ...
  if that name is already used on the same drive letter.
- **Folders never copied** - robocopy `/XD`: a full path, or a name skipped everywhere. `*.partial` is
  always skipped; nothing else is by default. A folder excluded after it was copied stays on the drives as
  it was.
- safety check %, minimum files, days to keep old versions, max drive full %, log file (default:
  `offline-copy.log` next to the settings file).

Saved as `OfflineBackup.ini` (UTF-8) next to the exe, so the Delphi and Lazarus builds each have their own
(in `%APPDATA%\OfflineBackup\` if the exe's folder can't be written to). No file = the defaults above. If a
ticked folder is missing at copy time, the app asks: skip it (the rest is copied, result and `LAST-COPY.txt`
say INCOMPLETE) or stop that drive's copy.

## Not done yet

- browse `G-mirror` / `_versions` and restore files
- start with Windows
