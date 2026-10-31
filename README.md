# Offline Backup

A Windows tray app that copies the folders you choose onto USB drives you keep unplugged ("offline") -
labelled `OFFLINE-A`, `OFFLINE-B`, ... - so ransomware, a failed disk or a bad mistake on the PC can't reach
them. Each drive knows which folders it backs up. Before anything changes on a drive you see a preview; files
that would be overwritten or deleted are kept in `_versions` first; moved files are moved on the drive instead
of copied again; and CRC32 / MD5 checksums let you verify a drive at any time, even on another PC.

Version **0.9.0** - first public beta. MIT licensed (see `LICENSE`). See `CHANGELOG.md`.

## Download and install

1. Download `OfflineBackup-0.9.0-win64.zip` from the Releases page and unzip it to a folder you can write to
   (for example `Documents\OfflineBackup`).
2. Start `OfflineBackup.exe` - it sits in the tray (add `/show` to open its window too).
   Windows may warn that the program is unknown (it is not code-signed): **More info** > **Run anyway**.
3. Name a USB drive `OFFLINE-A` in File Explorer, plug it in, and set it up under **Drives...** (what it is
   for, which folders it backs up). Then **Start copy**.

Needs Windows 10 or 11, 64-bit (robocopy is part of Windows). The zip has a short how-to (`README.txt`).

## How it works

Each folder lands on the drive under its own drive letter: `D:\MUSIC` -> `<drive>\D-mirror\MUSIC`,
`C:\Users\you\Documents` -> `<drive>\C-mirror\Documents`. Old versions keep the same path under
`_versions\<yyyy-mm-dd_hhmm>\`. Every run: a dry run (robocopy `/L`), moved-file detection, the preview and the
safety check, then old versions are saved, robocopy mirrors each folder, checksums are recorded, old version
sets are pruned, and `LAST-COPY.txt` and the drive's history are written. The log goes to `offline-copy.log`
next to the settings unless you choose another file.

It comes in two editions built from one shared engine:

| Edition | Folder | Toolchain | Notes |
|---|---|---|---|
| Lazarus LCL | `lazarus\` | Lazarus 4.4 / FPC 3.2.2 | free to build; the published download |
| Delphi VCL | `delphi\` | Delphi 12 (dcc64) | same app, built with Delphi |

Only one of the two can run at a time (they share a single-instance mutex).

## Layout

```
common\
  OfflineEngine.pas    the backup itself: drive detection, settings, drive maps, dry run, moves, preview data,
                       brake, _versions, robocopy with progress, checksums (CRC32/MD5), verify, MD5 check,
                       prune, LAST-COPY.txt, flush. No UI code. Compiles under both compilers
                       ({$mode delphiunicode} under FPC).
  DriveWatcher.pas     WM_DEVICECHANGE via its own hidden window (works the same in VCL and LCL)
  OfflineBackup.ico    app + tray icon (made by tools\make-icon.py)
delphi\                VCL edition: OfflineBackup.dpr, .rc + manifest, build.cmd, and the forms (.pas/.dfm):
                       MainForm, SettingsForm, SourceForm, DriveForm, PreviewForm, CheckForm
lazarus\               LCL edition: OfflineBackup.lpi/.lpr, build.cmd, the same forms (.pas/.lfm)
tests\                 EngineTest.dpr - runs the engine against throw-away folders; run-tests.cmd
                       builds and runs it with both compilers
tools\                 make-icon.py, screenshot.ps1, release-readme.txt (the README.txt in the zip)
make-release.cmd       tests + both builds + the download zip in dist\
build\, dist\          compiler output and release zips (not in git)
```

### Engine / UI split

`TOfflineCopy` (in `OfflineEngine`) does one run against one drive - a copy, a Verify, or an MD5 check - and
reports through events: `OnLog`, `OnProgress`, `OnPreview` (Copy or Cancel), `OnConfirm` (the safety check
when there is no preview) and `OnMissing` (a source folder is gone). `TOfflineCopyThread` runs it in the
background and raises those events on the main thread, so the forms only show things and ask questions.
Everything that decides what happens to a drive is in the shared unit, tested once, for both editions.

Safety rules, enforced in the engine, not the UI:
- only drives labelled `OFFLINE-<A-Z>`, never the drive Windows is on; the label is checked again right
  before copying
- only drives that have been set up and have a folder list
- nothing on the drive is touched until the dry run, the preview and the brake have passed
- anything robocopy would overwrite or delete is moved to `_versions` first (only from inside that
  folder's mirror)
- old-version cleanup removes junctions without following them

## Build

```
lazarus\build.cmd       -> build\lazarus\OfflineBackup.exe   (set LAZBUILD if lazbuild.exe is not in F:\lazarus)
delphi\build.cmd        -> build\delphi\OfflineBackup.exe    (Delphi 12 in its default folder)
tests\run-tests.cmd     -> builds and runs the engine tests with both compilers (skips one that is not installed)
make-release.cmd        -> all of the above, then dist\OfflineBackup-<version>-win64.zip
```

The version is `AppVersion` in `common\OfflineEngine.pas`; keep `delphi\OfflineBackup.rc` and the version
info in `lazarus\OfflineBackup.lpi` in step with it.

Both projects also open in their IDEs. In the Delphi IDE, open `delphi\OfflineBackup.dpr`; the IDE
creates a `.dproj` and may regenerate `OfflineBackup.res` with its own icon. Set the icon to
`common\OfflineBackup.ico` in Project Options, or run `build.cmd` again.

## Use

Start `OfflineBackup.exe` (add `/show` to open the window as well). It sits in the tray. When an
`OFFLINE-x` drive is plugged in while the window is closed, it shows a balloon and opens its window.
**Start copy** copies to every set-up OFFLINE drive that is plugged in, one after another, each with its own
folders. While it copies, the window shows time left, files done / failed / skipped / total and the transfer
rate (also in the tray icon's tooltip); when the run ends, a small window says how each drive went. Closing the
window only hides it; **Exit** is on the tray icon's menu.

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

- browse a drive's backups and `_versions`, and restore files (for now: File Explorer - the files on the
  drive are plain copies)
- start with Windows (for now: a shortcut in the Startup folder, `shell:startup`)
- code signing (Windows warns about unsigned programs)

## License

MIT - see `LICENSE`. No warranty: keep more than one backup.
