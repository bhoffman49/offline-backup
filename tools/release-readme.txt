OFFLINE BACKUP
==============

Copies the folders you choose onto USB drives you keep unplugged ("offline"), so a
ransomware attack, a failed disk or a bad mistake on your PC cannot reach them.
Each drive remembers which folders it is for, and the app keeps old versions and
checksums on the drive.

This is a beta. It has been tested well, but on few PCs - keep more than one backup.


WHAT YOU NEED
-------------
- Windows 10 or 11, 64-bit.
- One or more USB drives you can dedicate to backups.


INSTALL
-------
1. Unzip this folder somewhere you can write to, for example
   Documents\OfflineBackup. (Under Program Files works too; the settings then go
   to %APPDATA%\OfflineBackup.)
2. Start OfflineBackup.exe. It sits in the tray, by the clock.
   Add  /show  to a shortcut to open its window as well.

The first time, Windows may say "Windows protected your PC" because the program is
new and not signed. Click "More info", then "Run anyway".


FIRST BACKUP
------------
1. Give a USB drive the name OFFLINE-A: in File Explorer, right-click the drive,
   Rename (or Properties), and type OFFLINE-A. The app only ever writes to drives
   named OFFLINE-A ... OFFLINE-Z - never to any other drive.
2. Plug it in. The window says it is new.
3. Click Drives..., type what the drive is for, click Add folder... for each
   folder it should back up, then Set up this drive.
4. Click Start copy. A preview shows what will be copied - click Copy.
5. When it says "safe to unplug", unplug the drive and keep it somewhere else.

Next time, plug the drive in and click Start copy: only what changed is copied,
moved files are moved on the drive, and the preview shows it all first.


GOOD TO KNOW
------------
- Nothing on the drive changes before you click Copy in the preview.
- Files that would be overwritten or deleted are kept in _versions on the drive
  first, for 90 days (Settings), or less when the drive gets full.
- Drives... > Verify drive reads every file back and checks it against the
  checksums taken when it was copied. Check MD5... checks any .md5 file - each
  backed-up folder has one next to it on the drive, readable by other tools too.
- Each drive keeps its own folder list. Untick a folder to stop updating it;
  Remove it to take its copy off the drive (into _versions).
- Settings... holds what is the same for every drive: starting folders, folders
  never copied, the safety check, how long old versions are kept, the log file.


UNINSTALL
---------
Exit it from the tray icon's menu and delete its folder. Your drives and their
backups stay as they are.


LICENSE
-------
MIT - see LICENSE.txt. No warranty.
