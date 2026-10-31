unit OfflineEngine;

{ Shared engine for the Offline Backup tray app (Delphi VCL and Lazarus LCL editions).
  A port of the Copy-OfflineBackup.ps1 PowerShell script it replaces - that script was the spec.

  Only writes to drives whose volume label is OFFLINE-<letter> (OFFLINE-A, OFFLINE-B, ...), never the Windows drive.
  Each ticked source folder is mirrored to <drive>\<its drive letter>-mirror\<name>, e.g. G:\Backups to
  G-mirror\Backups and D:\MUSIC to D-mirror\MUSIC. Every run:
    0. missing   - a source folder that is not there is skipped or stops the run (OnMissing decides)
    1. dry run   - robocopy /L lists what would be new, changed or deleted on the offline drive; a new file that is
                   a deleted one moved (same size, time and checksum) becomes a move, done on the drive in place
    2. brake     - if a large share of existing files would be changed or deleted, asks before touching the drive
    3. versions  - files about to be overwritten or deleted are first moved to <drive>\_versions\<date-time>\,
                   under the same path they have on the drive (G-mirror\Backups\...)
    4. copy      - robocopy mirror, progress read from its log as it goes
    5. prune     - versions older than KeepVersionDays are removed, then the oldest until the drive is at most
                   MaxDriveFullPct full
  Each copied file's CRC32 and MD5 are recorded in <drive>\_checksums\<letter>-mirror\<name>.crc (taken from the
  source just after the copy), and the MD5s also go to <drive>\<letter>-mirror\<name>.md5 in the usual
  "md5 *path" format, so other tools (ExactFile, md5sum) can check the drive too. Verify re-reads every file on the
  drive, past the Windows cache, and compares - so a drive that has sat in a drawer can be checked without the PC's
  folders. CheckMd5 checks the files listed in any .md5 file.

  No UI code in here: the forms hook the events of TOfflineCopyThread, which runs them on the main thread. }

{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}

interface

uses
  Windows, SysUtils, Classes;

type
  // plain string arrays rather than TStringList: under Free Pascal TStringList is AnsiString and would
  // mangle file names outside the ANSI code page
  TPathList = array of string;

  TBackupSource = record
    Name: string;                // folder name on the drive, under <letter>-mirror\
    Path: string;                // 'D:\MUSIC' - any local drive
    Enabled: Boolean;            // ticked in the list; unticked sources are left alone on the drive
  end;
  TBackupSourceArray = array of TBackupSource;

  TBackupSettings = record
    Sources: TBackupSourceArray;
    Exclude: TPathList;          // folder names or full paths for robocopy /XD (*.partial is always excluded)
    BrakePercent: Integer;       // ask first if more than this % of a folder's files would be changed or deleted ...
    BrakeMinFiles: Integer;      // ... and at least this many files
    KeepVersionDays: Integer;
    MaxDriveFullPct: Integer;
    LogFile: string;
    // show the preview before every copy; False: only when something would be deleted from the drive
    PreviewAlways: Boolean;
  end;

  TOfflineDrive = record
    Root: string;                // 'H:\'
    Letter: Char;
    VolLabel: string;            // 'OFFLINE-B'
    SetUp: Boolean;              // has a drive map (OFFLINE-BACKUP.ini) with a folder list; anything else is not copied to
    Description: string;         // from the drive map
  end;
  TOfflineDriveArray = array of TOfflineDrive;

  { One copy run, as kept in the drive map }
  TDriveRun = record
    When: string;                // 'yyyy-mm-dd hh:nn'
    PC: string;
    Result: string;              // CopyResultText: ok, incomplete, failed, ...
    Bytes: Int64;                // copied
    Folders: string;             // 'Backups, Music, Photos'
  end;

  { The drive map: <drive>\OFFLINE-BACKUP.ini says which drive this is, what it is for, and what was copied to it }
  TDriveInfo = record
    Id: string;                  // made once at set-up, never changes - two drives with the same label still differ
    VolLabel: string;
    Description: string;         // what the drive is for, in the user's words
    Created: string;             // 'yyyy-mm-dd hh:nn' of set-up
    // what this drive backs up. Unticked folders are not updated but stay on the drive as they are.
    // HasList False (a map from before drives had their own lists): nothing is copied until folders are chosen
    HasList: Boolean;
    Sources: TBackupSourceArray;
    Removed: TPathList;          // drive folders taken off the list ('D-mirror\MUSIC'): moved to _versions at the next copy
    Runs: array of TDriveRun;    // oldest first, at most MaxDriveRuns
  end;

  // what a copy would do to the drive, file by file - shown in the preview before anything is changed
  TPreviewKind = (pkAdd, pkUpdate, pkMove, pkDelete, pkDirAdd, pkDirDelete, pkFolderRemove);
  TPreviewItem = record
    Kind: TPreviewKind;
    Folder: string;              // the source's name on the drive ('MUSIC'); for pkFolderRemove 'D-mirror\OLD'
    Rel: string;                 // path inside it ('Albums\x.mp3'); '' for pkFolderRemove; for pkMove the new path
    From: string;                // pkMove: where the file is on the drive now
    Size: Int64;                 // bytes, -1 where it does not apply (folders)
  end;
  TPreviewItems = array of TPreviewItem;
  TCopyPreview = record
    Drive: string;               // 'OFFLINE-D (H:)'
    Items: TPreviewItems;
    Warning: string;             // safety check: folders with an unusually large share changed or deleted, '' if none
  end;

  TCopyPlan = class
  public
    Bytes: Int64;
    NewFiles, Changed, Deleted, Total: Integer;
    Overwrite, DeleteFiles, DeleteDirs: TPathList;
    Items: TPreviewItems;        // Folder is filled in by the caller
    Moved: Integer;              // pkMove items (taken out of NewFiles, Deleted and Bytes)
  end;

  // crIncomplete: copied, but a missing source folder was skipped
  TCopyResult = (crOk, crSkipped, crStopped, crFailed, crCancelled, crIncomplete);

  { Where a run has got to. Counts and bytes are for the whole run (all folders), like the progress bar. }
  TCopyProgress = record
    Status: string;              // 'Checking what has changed ...', 'Copying Backups  (folder 1 of 3)'
    Folder: string;              // folder being copied, '' while checking
    BytesCopied, BytesTotal: Int64;
    FilesDone, FilesTotal: Integer;
    FilesDoneBytes: Int64;
    Errors: Integer;             // files robocopy gave up on after its retries
    ErrorBytes: Int64;
    Skipped: Integer;            // files in the plan that were neither copied nor failed (gone from G: meanwhile)
    SkippedBytes: Int64;
    Speed: Int64;                // bytes per second over the last few seconds, -1 while not known
    Elapsed: Integer;            // seconds since copying started
    SecondsLeft: Integer;        // -1 while not known
    Percent: Integer;
    Moved: Integer;              // files moved on the drive instead of copied
    // a Verify run: FilesDone = files read, Errors = files that do not match their checksum (or could not be
    // read), Skipped = files that had no checksum yet and got one now
    Verifying: Boolean;
    // a CheckMd5 run: Errors = bad or unreadable, Skipped = missing
    Checking: Boolean;
  end;

  // one line of an .md5 file, after checking
  TCheckStatus = (csOk, csBad, csMissing, csUnreadable);
  TCheckItem = record
    Status: TCheckStatus;
    Path: string;                // as listed in the .md5 file
    Size: Int64;                 // -1 if missing
  end;
  TCheckItems = array of TCheckItem;

  TLogEvent = procedure(const Msg: string) of object;
  TProgressEvent = procedure(const P: TCopyProgress) of object;
  TConfirmEvent = procedure(const Folders: string; var GoAhead: Boolean) of object;
  // the preview: GoAhead = True copies, False leaves the drive untouched
  TPreviewEvent = procedure(const P: TCopyPreview; var GoAhead: Boolean) of object;
  // a source folder is not there: Skip = True copies the others, False stops the run (the default)
  TMissingEvent = procedure(const Path: string; var Skip: Boolean) of object;

  { One full run against one drive. Run blocks - call it from a worker thread (TOfflineCopyThread). }
  TOfflineCopy = class
  private
    FSettings: TBackupSettings;
    FDrive: string;              // drive root with trailing backslash, e.g. 'H:\'
    FLabel: string;
    FTempDir: string;
    FCancelled: Boolean;
    FProcess: THandle;
    FOnLog: TLogEvent;
    FOnProgress: TProgressEvent;
    FOnConfirm: TConfirmEvent;
    FOnMissing: TMissingEvent;
    FOnPreview: TPreviewEvent;
    FProgress: TCopyProgress;
    FCopyStarted: TDateTime;
    FInfo: TDriveInfo;           // the drive map, read at the start of Run
    FList: TBackupSourceArray;   // the folders this drive backs up (from its drive map)
    FCopied: TPathList;          // source paths robocopy copied in the folder just done (for the checksums)
    FLastReport: DWORD;
    FHistorySaved: Boolean;
    function DoRun: TCopyResult;
    procedure MoveRemovedFolders(const Stamp: string);
    procedure SaveHistory(R: TCopyResult);
    procedure Report;
    function DriveTag: string;
    procedure Log(const Msg: string);
    function RoboArgs(const Src, Dest: string): string;
    function GetCopyPlan(const Src, Dest: string): TCopyPlan;
    function NeedsConfirmation(Plan: TCopyPlan): Boolean;
    procedure SaveVersions(Plan: TCopyPlan; const Folder, Dest, Stamp: string; out Moved, Failed: Integer);
    function RemoveOldVersions: Integer;
    function CopyWithProgress(const Name, Src, Dest: string; Plan: TCopyPlan): Integer;
    function CheckTarget: Boolean;
    procedure RecordChecksums(const Folder, Src, Dest: string; Plan: TCopyPlan);
    procedure FindMoves(const Src: TBackupSource; Plan: TCopyPlan);
    procedure DoMoves(const Src: TBackupSource; Plan: TCopyPlan);
    procedure CountBytes(N: Int64);
  public
    AllowFolderTarget: Boolean;  // tests only: lets Drive be a plain folder instead of an OFFLINE-x drive
    AssumeYes: Boolean;          // skip the brake question (like the script's -Yes)
    CheckItems: TCheckItems;     // filled by CheckMd5
    // why a run ended crSkipped, in a few words for the end-of-run window; NothingChosen: all folders unticked,
    // which is the user's choice and not a problem
    SkipReason: string;
    NothingChosen: Boolean;
    constructor Create(const Settings: TBackupSettings; const DriveRoot, DriveLabel: string);
    function Run: TCopyResult;
    // re-reads every file of the drive's folders and checks it against its recorded CRC32; files without one get
    // one. crOk: all fine, crFailed: bad or unreadable files (listed in the log)
    function Verify: TCopyResult;
    // checks every file listed in an .md5 file (paths relative to the file's folder); results in CheckItems.
    // crOk: all match, crFailed: something bad, missing or unreadable. Works anywhere - no OFFLINE drive needed.
    function CheckMd5(const FileName: string): TCopyResult;
    procedure Cancel;            // safe to call from another thread
    property OnLog: TLogEvent read FOnLog write FOnLog;
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnConfirm: TConfirmEvent read FOnConfirm write FOnConfirm;
    property OnMissing: TMissingEvent read FOnMissing write FOnMissing;
    // when assigned, the preview replaces the safety-check question (its Warning says why)
    property OnPreview: TPreviewEvent read FOnPreview write FOnPreview;
  end;

  { Runs a TOfflineCopy in the background; its events fire on the main thread. }
  TOfflineCopyThread = class(TThread)
  private
    FCopy: TOfflineCopy;
    FMsg: string;
    FProgress: TCopyProgress;
    FGoAhead: Boolean;
    FOnLog: TLogEvent;
    FOnProgress: TProgressEvent;
    FOnConfirm: TConfirmEvent;
    FOnMissing: TMissingEvent;
    FOnPreview: TPreviewEvent;
    FPreview: TCopyPreview;
    procedure CopyLog(const Msg: string);
    procedure CopyProgress(const P: TCopyProgress);
    procedure CopyConfirm(const Folders: string; var GoAhead: Boolean);
    procedure CopyMissing(const Path: string; var Skip: Boolean);
    procedure CopyPreview(const P: TCopyPreview; var GoAhead: Boolean);
    procedure SyncLog;
    procedure SyncProgress;
    procedure SyncConfirm;
    procedure SyncMissing;
    procedure SyncPreview;
  protected
    procedure Execute; override;
  public
    CopyResult: TCopyResult;
    DriveLabel: string;
    Verifying: Boolean;          // runs Verify instead of a copy
    Checking: Boolean;           // runs CheckMd5(CheckFile) instead of a copy
    CheckFile: string;
    constructor Create(const Settings: TBackupSettings; const Drive: TOfflineDrive; VerifyOnly: Boolean = False);
    constructor CreateCheck(const Settings: TBackupSettings; const Md5File: string);
    destructor Destroy; override;
    procedure Cancel;
    property Engine: TOfflineCopy read FCopy;
    property OnLog: TLogEvent read FOnLog write FOnLog;
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnConfirm: TConfirmEvent read FOnConfirm write FOnConfirm;
    property OnMissing: TMissingEvent read FOnMissing write FOnMissing;
    property OnPreview: TPreviewEvent read FOnPreview write FOnPreview;
  end;

function PreviewKindText(K: TPreviewKind): string;   // 'Files to add', ...
const
  AppVersion = '0.9.0';         // shown in the window title; make-release.cmd reads it from this line

function DefaultSettings: TBackupSettings;
// settings file: OfflineBackup.ini next to the exe (each edition has its own), or in %APPDATA%\OfflineBackup\
// when the exe's folder can't be written to - SettingsInAppData is then True
function SettingsFileName: string;
function SettingsInAppData: Boolean;
// a missing file gives DefaultSettings; values out of range are pulled back in, duplicate names get a suffix
function LoadSettings(const FileName: string): TBackupSettings;
function SaveSettings(const FileName: string; const S: TBackupSettings): Boolean;
// sources: where each lands on the drive, and the checks the settings window uses
function SourceLetter(const Path: string): Char;           // 'D' for 'D:\MUSIC', #0 for anything else
function MirrorFolder(const Src: TBackupSource): string;   // 'D-mirror\MUSIC'
function DefaultSourceName(const Path: string): string;    // 'MUSIC' for 'D:\MUSIC', 'D-drive' for 'D:\'
function ValidSourceName(const Name: string): Boolean;
// Name, or Name (2), Name (3) ... so that no other source (Skip = its own index, or -1) lands in the same folder
function UniqueSourceName(const Sources: TBackupSourceArray; Skip: Integer; const Path, Name: string): string;
function NormalizeSourcePath(const Path: string): string;  // trims, drops a trailing backslash ('D:\' stays)
// drive map - the drive keeps the file; a copy also goes to <settings folder>\drives\<id>.ini
const
  DriveMapName = 'OFFLINE-BACKUP.ini';
  MaxDriveRuns = 50;
function ReadDriveInfo(const Root: string; out Info: TDriveInfo): Boolean;   // False: no map (or no Id) - a new drive
function WriteDriveInfo(const Root: string; const Info: TDriveInfo): Boolean;
function NewDriveInfo(const VolLabel, Description: string): TDriveInfo;
procedure AddDriveRun(var Info: TDriveInfo; const Run: TDriveRun);
function DriveRunText(const R: TDriveRun): string;                          // '2026-10-30 10:15  ok  12.63 KB  (MYPC)'
// CRC32 (the zip / Ethernet one) of a string's bytes, and of a file
function StringCrc32(const S: RawByteString): Cardinal;
function FileCrc32(const Path: string; out Crc: Cardinal): Boolean;
// MD5 as 32 lower-case hex digits, of a string's bytes and of a file
function StringMd5(const S: RawByteString): string;
function FileMd5(const Path: string; out Md5: string): Boolean;
function CheckStatusText(S: TCheckStatus): string;   // 'ok', 'BAD', 'missing', 'could not read'
function FindOfflineDrives: TOfflineDriveArray;
function IsOfflineLabel(const S: string): Boolean;
function FormatGB(Bytes: Int64): string;
function FormatSize(Bytes: Int64): string;
function FormatSpeed(BytesPerSec: Int64): string;
function FormatDuration(Seconds: Integer): string;
// the three lines of the progress panel, shared so both editions show the same thing
function ProgressEtaLine(const P: TCopyProgress): string;
function ProgressCountsLine(const P: TCopyProgress): string;
function ProgressRateLine(const P: TCopyProgress): string;
procedure AppendLogLine(const FileName, Msg: string);
function CopyResultText(R: TCopyResult): string;

implementation

const
  kernel32 = 'kernel32.dll';
  VersionsDir = '_versions';
  ChecksumDir = '_checksums';
  GB = 1024.0 * 1024.0 * 1024.0;

// Declared here rather than taken from the Windows unit: Delphi and Free Pascal declare these differently
function GetDiskFreeSpaceExW_(lpDirectoryName: PWideChar; out FreeAvailable, TotalBytes, TotalFree: UInt64): BOOL;
  stdcall; external kernel32 name 'GetDiskFreeSpaceExW';
function GetVolumeInformationW_(lpRootPathName, lpVolumeNameBuffer: PWideChar; nVolumeNameSize: DWORD;
  lpVolumeSerialNumber, lpMaximumComponentLength, lpFileSystemFlags: PDWORD; lpFileSystemNameBuffer: PWideChar;
  nFileSystemNameSize: DWORD): BOOL; stdcall; external kernel32 name 'GetVolumeInformationW';
function CreateProcessW_(lpApplicationName, lpCommandLine: PWideChar; lpProcessAttributes, lpThreadAttributes: Pointer;
  bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: PWideChar;
  lpStartupInfo, lpProcessInformation: Pointer): BOOL; stdcall; external kernel32 name 'CreateProcessW';
function GetTempPathW_(nBufferLength: DWORD; lpBuffer: PWideChar): DWORD; stdcall; external kernel32 name 'GetTempPathW';
function GetComputerNameW_(lpBuffer: PWideChar; var nSize: DWORD): BOOL; stdcall; external kernel32 name 'GetComputerNameW';

type
  TIoCounters = record
    ReadOperationCount, WriteOperationCount, OtherOperationCount: UInt64;
    ReadTransferCount, WriteTransferCount, OtherTransferCount: UInt64;
  end;

function GetProcessIoCounters_(hProcess: THandle; out Counters: TIoCounters): BOOL; stdcall;
  external kernel32 name 'GetProcessIoCounters';

{ ---------- small helpers ---------- }

{ What a first start without a settings file gets: no folders (the user picks them), nothing excluded but the
  built-in *.partial, and the log next to the settings file. Nothing here is specific to one PC. }
function DefaultSettings: TBackupSettings;
begin
  Result.Sources := nil;
  Result.Exclude := nil;
  Result.BrakePercent := 20;
  Result.BrakeMinFiles := 100;
  Result.KeepVersionDays := 90;
  Result.MaxDriveFullPct := 85;
  Result.LogFile := ExtractFilePath(SettingsFileName) + 'offline-copy.log';
  Result.PreviewAlways := True;
end;

{ The letter of the drive Windows is on - never an OFFLINE target }
function SystemDriveLetter: Char;
var
  Buf: array[0..MAX_PATH] of WideChar;
begin
  Result := 'C';
  if GetWindowsDirectoryW(Buf, MAX_PATH) >= 2 then Result := UpCase(Buf[0]);
end;

function PreviewKindText(K: TPreviewKind): string;
const
  Names: array[TPreviewKind] of string = ('Files to add', 'Files to update', 'Files to move', 'Files to delete',
    'Folders to add', 'Folders to delete', 'Backup folders to take off the drive');
begin
  Result := Names[K];
end;

function IsOfflineLabel(const S: string): Boolean;
begin
  Result := (Length(S) = 9) and (Copy(S, 1, 8) = 'OFFLINE-') and CharInSet(S[9], ['A'..'Z']);
end;

function FormatGB(Bytes: Int64): string;
begin
  Result := FormatFloat('#,##0.0', Bytes / GB);
end;

function FormatSize(Bytes: Int64): string;
begin
  if Bytes <= 0 then Result := '0'
  else if Bytes < 1024 then Result := IntToStr(Bytes) + ' bytes'
  else if Bytes < 1024 * 1024 then Result := FormatFloat('0.00', Bytes / 1024.0) + ' KB'
  else if Bytes < 1024 * 1024 * 1024 then Result := FormatFloat('0.00', Bytes / (1024.0 * 1024.0)) + ' MB'
  else Result := FormatFloat('#,##0.00', Bytes / GB) + ' GB';
end;

function FormatSpeed(BytesPerSec: Int64): string;
begin
  if BytesPerSec < 0 then Result := '-'
  else Result := FormatSize(BytesPerSec) + '/s';
end;

function FormatDuration(Seconds: Integer): string;
begin
  if Seconds < 60 then Result := IntToStr(Seconds) + ' sec'
  else if Seconds < 3600 then Result := IntToStr(Seconds div 60) + ' min ' + IntToStr(Seconds mod 60) + ' sec'
  else Result := IntToStr(Seconds div 3600) + ' hr ' + IntToStr((Seconds mod 3600) div 60) + ' min';
end;

function ProgressEtaLine(const P: TCopyProgress): string;
begin
  if P.SecondsLeft < 0 then Result := 'Estimated time left: working it out'
  else Result := 'Estimated time left: ' + FormatDuration(P.SecondsLeft);
  Result := Result + '  (' + FormatSize(P.BytesCopied) + ' of ' + FormatSize(P.BytesTotal) + ' copied)';
end;

function ProgressCountsLine(const P: TCopyProgress): string;
begin
  if P.Checking then
    Exit(Format('Checked: %d (%s)     Bad: %d     Missing: %d     Tot: %d (%s)',
      [P.FilesDone, FormatSize(P.FilesDoneBytes), P.Errors, P.Skipped, P.FilesTotal, FormatSize(P.BytesTotal)]));
  if P.Verifying then
    Exit(Format('Checked: %d (%s)     Bad: %d     New checksums: %d     Tot: %d (%s)',
      [P.FilesDone, FormatSize(P.FilesDoneBytes), P.Errors, P.Skipped, P.FilesTotal, FormatSize(P.BytesTotal)]));
  Result := Format('Done: %d (%s)     Err: %d (%s)     Skipped: %d (%s)     Tot: %d (%s)',
    [P.FilesDone, FormatSize(P.FilesDoneBytes), P.Errors, FormatSize(P.ErrorBytes), P.Skipped,
     FormatSize(P.SkippedBytes), P.FilesTotal, FormatSize(P.BytesTotal)]);
end;

function ProgressRateLine(const P: TCopyProgress): string;
begin
  Result := 'Transfer rate: ' + FormatSpeed(P.Speed) + '  (' + FormatDuration(P.Elapsed) + ')';
end;

function CopyResultText(R: TCopyResult): string;
const
  Names: array[TCopyResult] of string = ('ok', 'skipped', 'stopped', 'failed', 'cancelled', 'incomplete');
begin
  Result := Names[R];
end;

function PathExists(const P: string): Boolean;
begin
  Result := GetFileAttributesW(PWideChar(P)) <> INVALID_FILE_ATTRIBUTES;
end;

function IsDir(const P: string): Boolean;
var
  A: DWORD;
begin
  A := GetFileAttributesW(PWideChar(P));
  Result := (A <> INVALID_FILE_ATTRIBUTES) and (A and FILE_ATTRIBUTE_DIRECTORY <> 0);
end;

function ParentDir(const P: string): string;
var
  I: Integer;
begin
  I := Length(P);
  while (I > 0) and (P[I] <> '\') do Dec(I);
  Result := Copy(P, 1, I - 1);
end;

procedure MakeDirs(const Dir: string);
begin
  if (Dir = '') or IsDir(Dir) then Exit;
  if (Length(Dir) > 3) then MakeDirs(ParentDir(Dir));
  CreateDirectoryW(PWideChar(Dir), nil);
end;

procedure AddPath(var L: TPathList; const S: string);
begin
  SetLength(L, Length(L) + 1);
  L[High(L)] := S;
end;

{ Splits text into lines (CRLF or LF) }
function SplitLines(const Text: string): TPathList;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(Text) do
    if Text[I] = #10 then
    begin
      if (I > Start) and (Text[I - 1] = #13) then AddPath(Result, Copy(Text, Start, I - 1 - Start))
      else AddPath(Result, Copy(Text, Start, I - Start));
      Start := I + 1;
    end;
  if Start <= Length(Text) then AddPath(Result, Copy(Text, Start, MaxInt));
end;

function NoTrailingSlash(const P: string): string;
begin
  Result := P;
  while (Length(Result) > 3) and (Result[Length(Result)] = '\') do SetLength(Result, Length(Result) - 1);
end;

function WithSlash(const P: string): string;
begin
  Result := P;
  if (Result <> '') and (Result[Length(Result)] <> '\') then Result := Result + '\';
end;

function TempDir: string;
var
  Buf: array[0..MAX_PATH] of WideChar;
begin
  SetString(Result, Buf, GetTempPathW_(MAX_PATH, Buf));
  Result := WithSlash(Result);
end;

function ComputerName: string;
var
  Buf: array[0..255] of WideChar;
  N: DWORD;
begin
  N := 256;
  if GetComputerNameW_(Buf, N) then SetString(Result, Buf, N) else Result := '?';
end;

{ Appends Text to a file as UTF-8 (the script's log is plain ASCII, so it stays readable by both) }
procedure AppendText(const FileName, Text: string);
var
  H: THandle;
  U: UTF8String;
  Written: DWORD;
begin
  MakeDirs(ParentDir(FileName));
  H := CreateFileW(PWideChar(FileName), FILE_APPEND_DATA, FILE_SHARE_READ, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    U := UTF8Encode(Text);
    if Length(U) > 0 then WriteFile(H, PAnsiChar(U)^, Length(U), Written, nil);
  finally
    CloseHandle(H);
  end;
end;

procedure WriteTextFile(const FileName, Text: string);
begin
  DeleteFileW(PWideChar(FileName));
  AppendText(FileName, Text);
end;

procedure AppendLogLine(const FileName, Msg: string);
begin
  AppendText(FileName, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + Msg + #13#10);
end;

{ Reads a robocopy /UNILOG file (UTF-16LE) from byte offset Pos onwards; Pos is moved past what was read.
  Opened shared, so it can be read while robocopy is still writing it. }
function ReadUnicodeFrom(const FileName: string; var Pos: Int64): string;
var
  H: THandle;
  Size: Int64;
  Bytes: TBytes;
  Got: DWORD;
  Hi: DWORD;
begin
  Result := '';
  H := CreateFileW(PWideChar(FileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    Size := GetFileSize(H, @Hi);
    Size := Size or (Int64(Hi) shl 32);
    if Pos = 0 then Pos := 2;                           // skip the byte-order mark
    Size := (Size - Pos) and not Int64(1);              // whole characters only
    if Size <= 0 then Exit;
    if Size > 64 * 1024 * 1024 then Size := 64 * 1024 * 1024;
    Hi := DWORD(Pos shr 32);
    SetFilePointer(H, DWORD(Pos and $FFFFFFFF), @Hi, FILE_BEGIN);
    SetLength(Bytes, Size);
    if ReadFile(H, Bytes[0], DWORD(Size), Got, nil) and (Got > 1) then
    begin
      Got := Got and not DWORD(1);
      SetLength(Result, Got div 2);
      Move(Bytes[0], Result[1], Got);
      Inc(Pos, Got);
    end;
  finally
    CloseHandle(H);
  end;
end;

{ Splits a robocopy log line like "    New File  \t\t  123456\tG:\x\file.txt" into its keyword, number and path.
  Returns False when the line is not one of the given keywords. }
function ParseRoboLine(const Line: string; const Keywords: array of string; out Keyword: string; out Num: Int64;
  out Path: string): Boolean;
var
  S, Rest: string;
  I, P: Integer;
begin
  Result := False;
  S := Trim(Line);
  for I := Low(Keywords) to High(Keywords) do
    if (Copy(S, 1, Length(Keywords[I])) = Keywords[I]) and (Length(S) > Length(Keywords[I])) and
       CharInSet(S[Length(Keywords[I]) + 1], [' ', #9]) then
    begin
      Rest := TrimLeft(Copy(S, Length(Keywords[I]) + 1, MaxInt));
      P := 1;
      while (P <= Length(Rest)) and not CharInSet(Rest[P], [' ', #9]) do Inc(P);
      if not TryStrToInt64(Copy(Rest, 1, P - 1), Num) then Exit;
      Path := Trim(Copy(Rest, P, MaxInt));
      Keyword := Keywords[I];
      Result := Path <> '';
      Exit;
    end;
end;

const
  CopyKeywords: array[0..5] of string = ('New File', 'Newer', 'Older', 'Changed', 'Modified', 'Tweaked');

{ Runs robocopy with no window; returns the process handle (0 on failure) }
function StartRobocopy(const Args: string): THandle;
var
  SI: TStartupInfoW;
  PI: TProcessInformation;
  Cmd: string;
begin
  Result := 0;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  Cmd := 'robocopy.exe ' + Args;
  UniqueString(Cmd);                                    // CreateProcessW may write to the command line
  if CreateProcessW_(nil, PWideChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, @SI, @PI) then
  begin
    CloseHandle(PI.hThread);
    Result := PI.hProcess;
  end;
end;

function VolumeUsedPct(const Root: string; out FreeBytes: Int64): Double;
var
  Avail, Total, TotalFree: UInt64;
begin
  Result := 0;
  FreeBytes := 0;
  if GetDiskFreeSpaceExW_(PWideChar(Root), Avail, Total, TotalFree) and (Total > 0) then
  begin
    FreeBytes := Avail;
    Result := 100.0 * (Total - TotalFree) / Total;
  end;
end;

{ Deletes a folder and everything in it. Junctions/symlinks are unlinked, never followed. }
procedure DeleteTree(const Dir: string);
var
  H: THandle;
  FD: TWin32FindDataW;
  Name, Full: string;
begin
  H := FindFirstFileW(PWideChar(WithSlash(Dir) + '*'), FD);
  if H <> INVALID_HANDLE_VALUE then
  try
    repeat
      Name := FD.cFileName;
      if (Name = '.') or (Name = '..') then Continue;
      Full := WithSlash(Dir) + Name;
      if FD.dwFileAttributes and FILE_ATTRIBUTE_READONLY <> 0 then
        SetFileAttributesW(PWideChar(Full), FD.dwFileAttributes and not FILE_ATTRIBUTE_READONLY);
      if FD.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0 then
      begin
        if FD.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT = 0 then DeleteTree(Full)
        else RemoveDirectoryW(PWideChar(Full));
      end
      else
        DeleteFileW(PWideChar(Full));
    until not FindNextFileW(H, FD);
  finally
    Windows.FindClose(H);
  end;
  RemoveDirectoryW(PWideChar(Dir));
end;

{ Reads a UTF-8 text file (with or without byte-order mark); '' if it cannot be read }
function ReadTextFile(const FileName: string): string;
var
  H: THandle;
  U: RawByteString;
  Size, Got: DWORD;
begin
  Result := '';
  H := CreateFileW(PWideChar(FileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    Size := GetFileSize(H, nil);
    if (Size = 0) or (Size > 512 * 1024 * 1024) then Exit;
    SetLength(U, Size);
    if not ReadFile(H, U[1], Size, Got, nil) then Exit;
    SetLength(U, Got);
  finally
    CloseHandle(H);
  end;
  if (Length(U) >= 3) and (U[1] = AnsiChar($EF)) and (U[2] = AnsiChar($BB)) and (U[3] = AnsiChar($BF)) then
    Delete(U, 1, 3);
  SetCodePage(U, CP_UTF8, False);
  {$IFDEF FPC}Result := UTF8Decode(U);{$ELSE}Result := UTF8ToString(U);{$ENDIF}
end;

{ Writes Text as UTF-8 to a temp file next to FileName, then swaps it in - a failed save leaves the old file }
function SaveTextFile(const FileName, Text: string): Boolean;
var
  H: THandle;
  U: UTF8String;
  Tmp: string;
  Written, BomWritten: DWORD;
  Bom: array[0..2] of Byte;
begin
  Result := False;
  Tmp := FileName + '.tmp';
  H := CreateFileW(PWideChar(Tmp), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    Bom[0] := $EF; Bom[1] := $BB; Bom[2] := $BF;        // so Notepad opens it as UTF-8 too
    U := UTF8Encode(Text);
    Result := WriteFile(H, Bom[0], 3, BomWritten, nil) and
      WriteFile(H, PAnsiChar(U)^, Length(U), Written, nil) and (Written = DWORD(Length(U)));
  finally
    CloseHandle(H);
  end;
  Result := Result and MoveFileExW(PWideChar(Tmp), PWideChar(FileName), MOVEFILE_REPLACE_EXISTING);
  if not Result then DeleteFileW(PWideChar(Tmp));
end;

{ ---------- sources ---------- }

function NormalizeSourcePath(const Path: string): string;
var
  I: Integer;
begin
  Result := Trim(Path);
  for I := 1 to Length(Result) do
    if Result[I] = '/' then Result[I] := '\';
  if (Length(Result) = 2) and (Result[2] = ':') then Result := Result + '\';
  Result := NoTrailingSlash(Result);
end;

function SourceLetter(const Path: string): Char;
begin
  Result := #0;
  if (Length(Path) >= 3) and (Path[2] = ':') and (Path[3] = '\') and CharInSet(UpCase(Path[1]), ['A'..'Z']) then
    Result := UpCase(Path[1]);
end;

function MirrorFolder(const Src: TBackupSource): string;
begin
  Result := SourceLetter(NormalizeSourcePath(Src.Path)) + '-mirror\' + Src.Name;
end;

function DefaultSourceName(const Path: string): string;
var
  P: string;
  I: Integer;
begin
  P := NormalizeSourcePath(Path);
  if Length(P) <= 3 then
    Result := SourceLetter(P) + '-drive'
  else
  begin
    I := Length(P);
    while (I > 0) and (P[I] <> '\') do Dec(I);
    Result := Copy(P, I + 1, MaxInt);
  end;
end;

function ValidSourceName(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := (Name <> '') and (Name = Trim(Name)) and (Name[Length(Name)] <> '.');
  for I := 1 to Length(Name) do
    if (Name[I] < ' ') or CharInSet(Name[I], ['\', '/', ':', '*', '?', '"', '<', '>', '|']) then Result := False;
end;

function UniqueSourceName(const Sources: TBackupSourceArray; Skip: Integer; const Path, Name: string): string;

  function Taken(const N: string): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    for I := 0 to High(Sources) do
      if (I <> Skip) and (SourceLetter(NormalizeSourcePath(Sources[I].Path)) = SourceLetter(NormalizeSourcePath(Path)))
         and SameText(Sources[I].Name, N) then
        Result := True;
  end;

var
  N: Integer;
begin
  Result := Name;
  N := 1;
  while Taken(Result) do
  begin
    Inc(N);
    Result := Name + ' (' + IntToStr(N) + ')';
  end;
end;

{ ---------- settings file ---------- }

{ OfflineBackup.ini, UTF-8:
    [General]   BrakePercent, BrakeMinFiles, KeepVersionDays, MaxDriveFullPct, LogFile
    [Sources]   Count=N, then [Source1] .. [SourceN] with Path, Name, Enabled=1/0
    [Exclude]   Folder1, Folder2, ... (one folder name or full path each) }

type
  TIniEntry = record
    Section, Key, Value: string;
  end;
  TIniEntries = array of TIniEntry;

function ParseIni(const Text: string): TIniEntries;
var
  Lines: TPathList;
  Section, Line: string;
  I, P: Integer;
begin
  Result := nil;
  Section := '';
  Lines := SplitLines(Text);
  for I := 0 to High(Lines) do
  begin
    Line := Trim(Lines[I]);
    if (Line = '') or (Line[1] = ';') then Continue;
    if (Line[1] = '[') and (Line[Length(Line)] = ']') then
      Section := Trim(Copy(Line, 2, Length(Line) - 2))
    else
    begin
      P := Pos('=', Line);
      if P < 2 then Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Section := Section;
      Result[High(Result)].Key := Trim(Copy(Line, 1, P - 1));
      Result[High(Result)].Value := Trim(Copy(Line, P + 1, MaxInt));
    end;
  end;
end;

function IniHas(const E: TIniEntries; const Section, Key: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(E) do
    if SameText(E[I].Section, Section) and ((Key = '') or SameText(E[I].Key, Key)) then Exit(True);
end;

function IniStr(const E: TIniEntries; const Section, Key, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  for I := 0 to High(E) do
    if SameText(E[I].Section, Section) and SameText(E[I].Key, Key) then Result := E[I].Value;
end;

function IniInt(const E: TIniEntries; const Section, Key: string; Default, Min, Max: Integer): Integer;
begin
  if not TryStrToInt(IniStr(E, Section, Key, ''), Result) then Result := Default;
  if Result < Min then Result := Min;
  if Result > Max then Result := Max;
end;

var
  SettingsFile: string;          // worked out once, by SettingsFileName
  SettingsFallback: Boolean;

function DirWritable(const Dir: string): Boolean;
var
  H: THandle;
begin
  H := CreateFileW(PWideChar(Dir + '\offline-backup-write-test.tmp'), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_TEMPORARY or FILE_FLAG_DELETE_ON_CLOSE, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if Result then CloseHandle(H);
end;

{ Next to the exe (portable). If that folder can't be written to (e.g. under Program Files), settings go to
  %APPDATA%\OfflineBackup\ instead, and SettingsInAppData tells the window to say so. }
function SettingsFileName: string;
var
  Buf: array[0..1023] of WideChar;
  N: DWORD;
  Dir: string;
begin
  if SettingsFile = '' then
  begin
    N := GetModuleFileNameW(0, Buf, Length(Buf));
    SetString(Dir, Buf, N);
    Dir := ParentDir(Dir);
    SettingsFallback := not DirWritable(Dir);
    if SettingsFallback then
    begin
      N := GetEnvironmentVariableW('APPDATA', Buf, Length(Buf));
      SetString(Dir, Buf, N);
      Dir := NoTrailingSlash(Dir) + '\OfflineBackup';
      MakeDirs(Dir);
    end;
    SettingsFile := Dir + '\OfflineBackup.ini';
  end;
  Result := SettingsFile;
end;

function SettingsInAppData: Boolean;
begin
  SettingsFileName;
  Result := SettingsFallback;
end;

function LoadSettings(const FileName: string): TBackupSettings;
var
  E: TIniEntries;
  Src: TBackupSource;
  Sec, X: string;
  I, Count: Integer;
begin
  Result := DefaultSettings;
  if not PathExists(FileName) then Exit;
  E := ParseIni(ReadTextFile(FileName));
  Result.BrakePercent := IniInt(E, 'General', 'BrakePercent', Result.BrakePercent, 1, 100);
  Result.BrakeMinFiles := IniInt(E, 'General', 'BrakeMinFiles', Result.BrakeMinFiles, 1, 10000000);
  Result.KeepVersionDays := IniInt(E, 'General', 'KeepVersionDays', Result.KeepVersionDays, 1, 36500);
  Result.MaxDriveFullPct := IniInt(E, 'General', 'MaxDriveFullPct', Result.MaxDriveFullPct, 10, 100);
  Result.LogFile := IniStr(E, 'General', 'LogFile', Result.LogFile);
  if Result.LogFile = '' then Result.LogFile := DefaultSettings.LogFile;
  Result.PreviewAlways := IniStr(E, 'General', 'PreviewAlways', '1') <> '0';
  // a file without a [Sources] section keeps the default sources; Count=0 means none
  if IniHas(E, 'Sources', 'Count') then
  begin
    Result.Sources := nil;
    Count := IniInt(E, 'Sources', 'Count', 0, 0, 1000);
    for I := 1 to Count do
    begin
      Sec := 'Source' + IntToStr(I);
      Src.Path := NormalizeSourcePath(IniStr(E, Sec, 'Path', ''));
      if SourceLetter(Src.Path) = #0 then Continue;          // only folders on a local drive letter
      Src.Name := IniStr(E, Sec, 'Name', '');
      if not ValidSourceName(Src.Name) then Src.Name := DefaultSourceName(Src.Path);
      Src.Name := UniqueSourceName(Result.Sources, -1, Src.Path, Src.Name);
      Src.Enabled := IniStr(E, Sec, 'Enabled', '1') <> '0';
      SetLength(Result.Sources, Length(Result.Sources) + 1);
      Result.Sources[High(Result.Sources)] := Src;
    end;
  end;
  if IniHas(E, 'Exclude', '') or IniHas(E, 'General', 'ExcludeCount') then
  begin
    Result.Exclude := nil;
    for I := 0 to High(E) do
      if SameText(E[I].Section, 'Exclude') then
      begin
        X := NoTrailingSlash(E[I].Value);
        if X <> '' then AddPath(Result.Exclude, X);
      end;
  end;
end;

function SaveSettings(const FileName: string; const S: TBackupSettings): Boolean;
var
  T: string;
  I: Integer;
begin
  T := '; Offline Backup settings - written by the app''s Settings window' + #13#10 +
    #13#10'[General]'#13#10 +
    'BrakePercent=' + IntToStr(S.BrakePercent) + #13#10 +
    'BrakeMinFiles=' + IntToStr(S.BrakeMinFiles) + #13#10 +
    'KeepVersionDays=' + IntToStr(S.KeepVersionDays) + #13#10 +
    'MaxDriveFullPct=' + IntToStr(S.MaxDriveFullPct) + #13#10 +
    'LogFile=' + S.LogFile + #13#10 +
    'PreviewAlways=' + IntToStr(Ord(S.PreviewAlways)) + #13#10 +
    // the count also tells LoadSettings that an empty [Exclude] really is empty
    'ExcludeCount=' + IntToStr(Length(S.Exclude)) + #13#10 +
    #13#10'[Sources]'#13#10 +
    'Count=' + IntToStr(Length(S.Sources)) + #13#10;
  for I := 0 to High(S.Sources) do
    T := T + #13#10'[Source' + IntToStr(I + 1) + ']'#13#10 +
      'Path=' + S.Sources[I].Path + #13#10 +
      'Name=' + S.Sources[I].Name + #13#10 +
      'Enabled=' + IntToStr(Ord(S.Sources[I].Enabled)) + #13#10;
  T := T + #13#10'[Exclude]'#13#10;
  for I := 0 to High(S.Exclude) do
    T := T + 'Folder' + IntToStr(I + 1) + '=' + S.Exclude[I] + #13#10;
  Result := SaveTextFile(FileName, T);
end;

{ ---------- drive map ---------- }

{ <drive>\OFFLINE-BACKUP.ini, UTF-8:
    [Drive]    Id, Label, Description, Created
    [History]  Count=N, Run1..RunN = when|PC|result|bytes copied|folders  (oldest first) }

function OneLine(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if CharInSet(Result[I], [#13, #10, '|']) then Result[I] := ' ';
  Result := Trim(Result);
end;

function ReadDriveInfo(const Root: string; out Info: TDriveInfo): Boolean;
var
  E: TIniEntries;
  Parts: TPathList;
  S: string;
  I, P, Count: Integer;
  R: TDriveRun;
  Src: TBackupSource;
begin
  Info := Default(TDriveInfo);
  Result := False;
  if not PathExists(WithSlash(Root) + DriveMapName) then Exit;
  E := ParseIni(ReadTextFile(WithSlash(Root) + DriveMapName));
  Info.Id := IniStr(E, 'Drive', 'Id', '');
  Info.VolLabel := IniStr(E, 'Drive', 'Label', '');
  Info.Description := IniStr(E, 'Drive', 'Description', '');
  Info.Created := IniStr(E, 'Drive', 'Created', '');
  // [Folders] Count=N, FolderN = ticked (1/0)|source path|name on the drive
  Info.HasList := IniHas(E, 'Folders', 'Count');
  Count := IniInt(E, 'Folders', 'Count', 0, 0, 1000);
  for I := 1 to Count do
  begin
    S := IniStr(E, 'Folders', 'Folder' + IntToStr(I), '') + '|';
    Parts := nil;
    while S <> '' do
    begin
      P := Pos('|', S);
      AddPath(Parts, Copy(S, 1, P - 1));
      Delete(S, 1, P);
    end;
    if Length(Parts) < 3 then Continue;
    Src.Enabled := Parts[0] <> '0';
    Src.Path := NormalizeSourcePath(Parts[1]);
    if SourceLetter(Src.Path) = #0 then Continue;
    Src.Name := Parts[2];
    if not ValidSourceName(Src.Name) then Src.Name := DefaultSourceName(Src.Path);
    Src.Name := UniqueSourceName(Info.Sources, -1, Src.Path, Src.Name);
    SetLength(Info.Sources, Length(Info.Sources) + 1);
    Info.Sources[High(Info.Sources)] := Src;
  end;
  for I := 0 to High(E) do
    if SameText(E[I].Section, 'Remove') and (E[I].Value <> '') then AddPath(Info.Removed, E[I].Value);
  Count := IniInt(E, 'History', 'Count', 0, 0, 100000);
  for I := 1 to Count do
  begin
    S := IniStr(E, 'History', 'Run' + IntToStr(I), '') + '|';   // the extra | keeps an empty last field
    Parts := nil;
    while S <> '' do
    begin
      P := Pos('|', S);
      AddPath(Parts, Copy(S, 1, P - 1));
      Delete(S, 1, P);
    end;
    if Length(Parts) < 5 then Continue;
    R.When := Parts[0];
    R.PC := Parts[1];
    R.Result := Parts[2];
    if not TryStrToInt64(Parts[3], R.Bytes) then R.Bytes := 0;
    R.Folders := Parts[4];
    AddDriveRun(Info, R);
  end;
  Result := Info.Id <> '';
end;

function DriveInfoText(const Info: TDriveInfo): string;
var
  I: Integer;
begin
  Result := '; Offline Backup drive map - tells the app which drive this is and what was copied to it.' + #13#10 +
    '; Keep it on the drive. Without it the drive counts as new and is not copied to until it is set up again.' +
    #13#10#13#10'[Drive]'#13#10 +
    'Id=' + Info.Id + #13#10 +
    'Label=' + Info.VolLabel + #13#10 +
    'Description=' + OneLine(Info.Description) + #13#10 +
    'Created=' + Info.Created + #13#10 +
    '';
  if Info.HasList then
  begin
    Result := Result + #13#10'[Folders]'#13#10 +
      '; what this drive backs up: ticked (1/0)|source folder|name on the drive (under <letter>-mirror\)'#13#10 +
      'Count=' + IntToStr(Length(Info.Sources)) + #13#10;
    for I := 0 to High(Info.Sources) do
      Result := Result + 'Folder' + IntToStr(I + 1) + '=' + IntToStr(Ord(Info.Sources[I].Enabled)) + '|' +
        OneLine(Info.Sources[I].Path) + '|' + OneLine(Info.Sources[I].Name) + #13#10;
  end;
  if Length(Info.Removed) > 0 then
  begin
    Result := Result + #13#10'[Remove]'#13#10 +
      '; taken off the list - moved to _versions at the next copy'#13#10;
    for I := 0 to High(Info.Removed) do
      Result := Result + 'Folder' + IntToStr(I + 1) + '=' + OneLine(Info.Removed[I]) + #13#10;
  end;
  Result := Result + #13#10'[History]'#13#10 +
    'Count=' + IntToStr(Length(Info.Runs)) + #13#10;
  for I := 0 to High(Info.Runs) do
    Result := Result + 'Run' + IntToStr(I + 1) + '=' + OneLine(Info.Runs[I].When) + '|' + OneLine(Info.Runs[I].PC) + '|' +
      OneLine(Info.Runs[I].Result) + '|' + IntToStr(Info.Runs[I].Bytes) + '|' + OneLine(Info.Runs[I].Folders) + #13#10;
end;

function WriteDriveInfo(const Root: string; const Info: TDriveInfo): Boolean;
var
  Text, Dir: string;
begin
  Text := DriveInfoText(Info);
  Result := SaveTextFile(WithSlash(Root) + DriveMapName, Text);
  // the PC keeps a copy, so a lost or wiped drive still has a record (best effort)
  Dir := ParentDir(SettingsFileName) + '\drives';
  MakeDirs(Dir);
  SaveTextFile(Dir + '\' + Info.Id + '.ini', Text);
end;

function NewDriveInfo(const VolLabel, Description: string): TDriveInfo;
var
  G: TGUID;
begin
  Result := Default(TDriveInfo);
  CreateGUID(G);
  Result.Id := Copy(GUIDToString(G), 2, 36);          // without the { }
  Result.VolLabel := VolLabel;
  Result.Description := OneLine(Description);
  Result.Created := FormatDateTime('yyyy-mm-dd hh:nn', Now);
end;

procedure AddDriveRun(var Info: TDriveInfo; const Run: TDriveRun);
begin
  if Length(Info.Runs) >= MaxDriveRuns then Delete(Info.Runs, 0, Length(Info.Runs) - MaxDriveRuns + 1);
  SetLength(Info.Runs, Length(Info.Runs) + 1);
  Info.Runs[High(Info.Runs)] := Run;
end;

function DriveRunText(const R: TDriveRun): string;
begin
  Result := R.When + '  ' + R.Result + '  ' + FormatSize(R.Bytes) + ' copied  (' + R.PC + ')';
end;

{ ---------- CRC32 and checksum lists ---------- }

var
  CrcTable: array[0..7, 0..255] of Cardinal;     // slicing-by-8, filled in the initialization section

procedure MakeCrcTable;
var
  I, J, K: Integer;
  C: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := I;
    for J := 1 to 8 do
      if C and 1 <> 0 then C := (C shr 1) xor $EDB88320 else C := C shr 1;
    CrcTable[0, I] := C;
  end;
  for I := 0 to 255 do
    for K := 1 to 7 do
      CrcTable[K, I] := (CrcTable[K - 1, I] shr 8) xor CrcTable[0, CrcTable[K - 1, I] and $FF];
end;

{ Crc is the running value: start with $FFFFFFFF, finish with xor $FFFFFFFF }
function CrcUpdate(Crc: Cardinal; P: PByte; Len: NativeInt): Cardinal;
var
  One, Two: Cardinal;
begin
  while Len >= 8 do
  begin
    One := PCardinal(P)^ xor Crc;
    Inc(P, 4);
    Two := PCardinal(P)^;
    Inc(P, 4);
    Crc := CrcTable[7, One and $FF] xor CrcTable[6, (One shr 8) and $FF] xor
      CrcTable[5, (One shr 16) and $FF] xor CrcTable[4, One shr 24] xor
      CrcTable[3, Two and $FF] xor CrcTable[2, (Two shr 8) and $FF] xor
      CrcTable[1, (Two shr 16) and $FF] xor CrcTable[0, Two shr 24];
    Dec(Len, 8);
  end;
  while Len > 0 do
  begin
    Crc := (Crc shr 8) xor CrcTable[0, (Crc xor P^) and $FF];
    Inc(P);
    Dec(Len);
  end;
  Result := Crc;
end;

function StringCrc32(const S: RawByteString): Cardinal;
begin
  Result := $FFFFFFFF;
  if S <> '' then Result := CrcUpdate(Result, PByte(@S[1]), Length(S));
  Result := Result xor $FFFFFFFF;
end;

type
  TBytesEvent = procedure(N: Int64) of object;

{ ---------- MD5 (RFC 1321) ---------- }

{$OVERFLOWCHECKS OFF}{$RANGECHECKS OFF}

type
  TMd5 = record
    State: array[0..3] of Cardinal;
    Bytes: Int64;                  // message length so far
    Buf: array[0..63] of Byte;
    BufLen: Integer;
  end;

const
  Md5K: array[0..63] of Cardinal = (
    $d76aa478, $e8c7b756, $242070db, $c1bdceee, $f57c0faf, $4787c62a, $a8304613, $fd469501,
    $698098d8, $8b44f7af, $ffff5bb1, $895cd7be, $6b901122, $fd987193, $a679438e, $49b40821,
    $f61e2562, $c040b340, $265e5a51, $e9b6c7aa, $d62f105d, $02441453, $d8a1e681, $e7d3fbc8,
    $21e1cde6, $c33707d6, $f4d50d87, $455a14ed, $a9e3e905, $fcefa3f8, $676f02d9, $8d2a4c8a,
    $fffa3942, $8771f681, $6d9d6122, $fde5380c, $a4beea44, $4bdecfa9, $f6bb4b60, $bebfbc70,
    $289b7ec6, $eaa127fa, $d4ef3085, $04881d05, $d9d4d039, $e6db99e5, $1fa27cf8, $c4ac5665,
    $f4292244, $432aff97, $ab9423a7, $fc93a039, $655b59c3, $8f0ccc92, $ffeff47d, $85845dd1,
    $6fa87e4f, $fe2ce6e0, $a3014314, $4e0811a1, $f7537e82, $bd3af235, $2ad7d2bb, $eb86d391);
  Md5S: array[0..63] of Byte = (
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21);

procedure Md5Init(var M: TMd5);
begin
  M.State[0] := $67452301;
  M.State[1] := $efcdab89;
  M.State[2] := $98badcfe;
  M.State[3] := $10325476;
  M.Bytes := 0;
  M.BufLen := 0;
end;

{ One 64-byte block; words are little-endian, as on x86/x64 }
procedure Md5Block(var M: TMd5; P: PByte);
var
  W: array[0..15] of Cardinal;
  A, B, C, D, F, T: Cardinal;
  I, G: Integer;
begin
  Move(P^, W[0], 64);
  A := M.State[0];
  B := M.State[1];
  C := M.State[2];
  D := M.State[3];
  for I := 0 to 63 do
  begin
    case I shr 4 of
      0: begin F := (B and C) or ((not B) and D); G := I; end;
      1: begin F := (D and B) or ((not D) and C); G := (5 * I + 1) and 15; end;
      2: begin F := B xor C xor D; G := (3 * I + 5) and 15; end;
    else
      begin F := C xor (B or (not D)); G := (7 * I) and 15; end;
    end;
    T := D;
    D := C;
    C := B;
    F := A + F + Md5K[I] + W[G];
    B := B + ((F shl Md5S[I]) or (F shr (32 - Md5S[I])));
    A := T;
  end;
  Inc(M.State[0], A);
  Inc(M.State[1], B);
  Inc(M.State[2], C);
  Inc(M.State[3], D);
end;

procedure Md5Update(var M: TMd5; P: PByte; Len: NativeInt);
var
  N: NativeInt;
begin
  Inc(M.Bytes, Len);
  if M.BufLen > 0 then
  begin
    N := 64 - M.BufLen;
    if N > Len then N := Len;
    Move(P^, M.Buf[M.BufLen], N);
    Inc(M.BufLen, N);
    Inc(P, N);
    Dec(Len, N);
    if M.BufLen < 64 then Exit;
    Md5Block(M, @M.Buf[0]);
    M.BufLen := 0;
  end;
  while Len >= 64 do
  begin
    Md5Block(M, P);
    Inc(P, 64);
    Dec(Len, 64);
  end;
  if Len > 0 then
  begin
    Move(P^, M.Buf[0], Len);
    M.BufLen := Len;
  end;
end;

function Md5Final(var M: TMd5): string;
const
  Hex: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
var
  Pad: array[0..71] of Byte;
  Bits: Int64;
  N, I: Integer;
  B: Byte;
begin
  Bits := M.Bytes * 8;
  FillChar(Pad, SizeOf(Pad), 0);
  Pad[0] := $80;
  if M.BufLen < 56 then N := 56 - M.BufLen else N := 120 - M.BufLen;
  Move(Bits, Pad[N], 8);                  // little-endian bit count
  Md5Update(M, @Pad[0], N + 8);
  SetLength(Result, 32);
  for I := 0 to 15 do
  begin
    B := PByte(PAnsiChar(@M.State[0]) + I)^;
    Result[I * 2 + 1] := Hex[B shr 4];
    Result[I * 2 + 2] := Hex[B and 15];
  end;
end;

function StringMd5(const S: RawByteString): string;
var
  M: TMd5;
begin
  Md5Init(M);
  if S <> '' then Md5Update(M, PByte(@S[1]), Length(S));
  Result := Md5Final(M);
end;

const
  CrcBufSize = 1024 * 1024;

{ CRC32 and MD5 of a file in one read. NoCache reads past the Windows file cache, so a file just written is really
  read back from the drive. Progress (optional) gets the bytes read as it goes. False if the file could not be read
  or Cancel was set. }
function FileSums(const Path: string; NoCache: Boolean; out Crc: Cardinal; out Md5: string; Progress: TBytesEvent;
  Cancel: PBoolean): Boolean;
var
  H: THandle;
  Buf: Pointer;
  Got: DWORD;
  Flags: DWORD;
  M: TMd5;
begin
  Result := False;
  Crc := 0;
  Md5 := '';
  Flags := FILE_FLAG_SEQUENTIAL_SCAN;
  if NoCache then Flags := Flags or FILE_FLAG_NO_BUFFERING;   // needs a sector-aligned buffer: VirtualAlloc gives one
  H := CreateFileW(PWideChar(Path), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, Flags, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  Buf := VirtualAlloc(nil, CrcBufSize, MEM_COMMIT, PAGE_READWRITE);
  try
    Crc := $FFFFFFFF;
    Md5Init(M);
    repeat
      if (Cancel <> nil) and Cancel^ then Exit;
      if not ReadFile(H, Buf^, CrcBufSize, Got, nil) then Exit;
      if Got > 0 then
      begin
        Crc := CrcUpdate(Crc, PByte(Buf), Got);
        Md5Update(M, PByte(Buf), Got);
        if Assigned(Progress) then Progress(Got);
      end;
    until Got = 0;
    Crc := Crc xor $FFFFFFFF;
    Md5 := Md5Final(M);
    Result := True;
  finally
    VirtualFree(Buf, 0, MEM_RELEASE);
    CloseHandle(H);
  end;
end;

function FileCrc32(const Path: string; out Crc: Cardinal): Boolean;
var
  Md5: string;
begin
  Result := FileSums(Path, False, Crc, Md5, nil, nil);
end;

function FileMd5(const Path: string; out Md5: string): Boolean;
var
  Crc: Cardinal;
begin
  Result := FileSums(Path, False, Crc, Md5, nil, nil);
end;

function CheckStatusText(S: TCheckStatus): string;
const
  Names: array[TCheckStatus] of string = ('ok', 'BAD', 'missing', 'could not read');
begin
  Result := Names[S];
end;

{ Size and last-write time of a file; a checksum is only trusted while these are unchanged }
function FileStamp(const Path: string; out Size, Time: Int64): Boolean;
var
  H: THandle;
  FD: TWin32FindDataW;
begin
  Size := -1;
  Time := 0;
  H := FindFirstFileW(PWideChar(Path), FD);
  Result := H <> INVALID_HANDLE_VALUE;
  if not Result then Exit;
  Windows.FindClose(H);
  Size := Int64(FD.nFileSizeLow) or (Int64(FD.nFileSizeHigh) shl 32);
  Time := Int64(FD.ftLastWriteTime.dwLowDateTime) or (Int64(FD.ftLastWriteTime.dwHighDateTime) shl 32);
end;

type
  TCrcEntry = record
    Key: string;                 // UpperCase(Rel), the sort and search key
    Rel: string;                 // path inside the drive folder: 'sub\file.txt'
    Crc: Cardinal;
    Md5: string;                 // '' in lists made before MD5s were kept - Verify fills it in
    Size, Time: Int64;
  end;
  TCrcList = array of TCrcEntry;

procedure SortCrcList(var L: TCrcList; Lo, Hi: Integer);
var
  I, J: Integer;
  Pivot: string;
  T: TCrcEntry;
begin
  while Lo < Hi do
  begin
    Pivot := L[(Lo + Hi) div 2].Key;
    I := Lo;
    J := Hi;
    repeat
      while CompareStr(L[I].Key, Pivot) < 0 do Inc(I);
      while CompareStr(L[J].Key, Pivot) > 0 do Dec(J);
      if I <= J then
      begin
        T := L[I];
        L[I] := L[J];
        L[J] := T;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if J - Lo < Hi - I then
    begin
      SortCrcList(L, Lo, J);
      Lo := I;
    end
    else
    begin
      SortCrcList(L, I, Hi);
      Hi := J;
    end;
  end;
end;

{ Index of Key in a sorted list, or -1 }
function FindCrc(const L: TCrcList; const Key: string): Integer;
var
  Lo, Hi, Mid, C: Integer;
begin
  Lo := 0;
  Hi := High(L);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := CompareStr(L[Mid].Key, Key);
    if C = 0 then Exit(Mid);
    if C < 0 then Lo := Mid + 1 else Hi := Mid - 1;
  end;
  Result := -1;
end;

function CrcEntry(const Rel: string; Crc: Cardinal; const Md5: string; Size, Time: Int64): TCrcEntry;
begin
  Result.Key := UpperCase(Rel);
  Result.Rel := Rel;
  Result.Crc := Crc;
  Result.Md5 := Md5;
  Result.Size := Size;
  Result.Time := Time;
end;

{ <drive>\_checksums\G-mirror\Backups.crc, UTF-8, one line per file:
    crc32 (hex) TAB size TAB time TAB md5 TAB path   (older lists: no md5 field) }
function LoadCrcList(const FileName: string): TCrcList;
var
  Lines, F: TPathList;
  S: string;
  I, N, P: Integer;
  C: Int64;
begin
  Result := nil;
  if not PathExists(FileName) then Exit;
  Lines := SplitLines(ReadTextFile(FileName));
  SetLength(Result, Length(Lines));
  N := 0;
  for I := 0 to High(Lines) do
  begin
    S := Lines[I];
    if (S = '') or (S[1] = ';') then Continue;
    // file names cannot contain tabs, so every tab separates a field; the path is the last one
    F := nil;
    S := S + #9;
    while S <> '' do
    begin
      P := System.Pos(#9, S);
      AddPath(F, Copy(S, 1, P - 1));
      Delete(S, 1, P);
    end;
    if (Length(F) < 4) or (F[High(F)] = '') or not TryStrToInt64('$' + F[0], C) then Continue;
    Result[N].Crc := Cardinal(C);
    if not TryStrToInt64(F[1], Result[N].Size) or not TryStrToInt64(F[2], Result[N].Time) then Continue;
    if Length(F) >= 5 then Result[N].Md5 := LowerCase(F[3]) else Result[N].Md5 := '';
    Result[N].Rel := F[High(F)];
    Result[N].Key := UpperCase(Result[N].Rel);
    Inc(N);
  end;
  SetLength(Result, N);
  SortCrcList(Result, 0, N - 1);
end;

function SaveCrcList(const FileName: string; L: TCrcList): Boolean;
var
  Parts: TPathList;
  Text: string;
  I, N, Len: Integer;
begin
  SortCrcList(L, 0, High(L));
  SetLength(Parts, Length(L) + 1);
  Parts[0] := '; Offline Backup checksums: CRC32 (hex), size, last-write time, MD5, file - used by Verify drive'#13#10;
  for I := 0 to High(L) do
    Parts[I + 1] := IntToHex(L[I].Crc, 8) + #9 + IntToStr(L[I].Size) + #9 + IntToStr(L[I].Time) + #9 + L[I].Md5 + #9 +
      L[I].Rel + #13#10;
  // join in one go - adding 100,000 lines one by one would be slow
  Len := 0;
  for I := 0 to High(Parts) do Inc(Len, Length(Parts[I]));
  SetLength(Text, Len);
  N := 1;
  for I := 0 to High(Parts) do
    if Parts[I] <> '' then
    begin
      Move(Parts[I][1], Text[N], Length(Parts[I]) * SizeOf(Char));
      Inc(N, Length(Parts[I]));
    end;
  MakeDirs(ParentDir(FileName));
  Result := SaveTextFile(FileName, Text);
end;

{ Joins lines into one string in one go }
function JoinParts(const Parts: TPathList): string;
var
  I, N, Len: Integer;
begin
  Len := 0;
  for I := 0 to High(Parts) do Inc(Len, Length(Parts[I]));
  SetLength(Result, Len);
  N := 1;
  for I := 0 to High(Parts) do
    if Parts[I] <> '' then
    begin
      Move(Parts[I][1], Result[N], Length(Parts[I]) * SizeOf(Char));
      Inc(N, Length(Parts[I]));
    end;
end;

{ <drive>\<letter>-mirror\<Name>.md5 in the usual format ("md5 *Name\path"), like ExactFile writes, so any MD5 tool
  can check the drive. Files without an MD5 yet are left out, and the header says how many. }
function SaveMd5File(const FileName, Name: string; L: TCrcList): Boolean;
var
  Parts: TPathList;
  I, N, Without: Integer;
begin
  SortCrcList(L, 0, High(L));
  SetLength(Parts, Length(L) + 4);
  Without := 0;
  N := 3;
  for I := 0 to High(L) do
    if L[I].Md5 = '' then Inc(Without)
    else
    begin
      Parts[N] := L[I].Md5 + ' *' + Name + '\' + L[I].Rel + #13#10;
      Inc(N);
    end;
  Parts[0] := '; Checksums generated by Offline Backup'#13#10;
  Parts[1] := '; ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + #13#10;
  if Without > 0 then
    Parts[2] := '; ' + IntToStr(Without) + ' file(s) have no MD5 yet - Verify drive adds them'#13#10#13#10
  else
    Parts[2] := #13#10;
  Parts[N] := '; ' + IntToStr(N - 3) + ' files hashed.'#13#10;
  SetLength(Parts, N + 1);
  Result := SaveTextFile(FileName, JoinParts(Parts));
end;

{ ---------- drive detection ---------- }

function FindOfflineDrives: TOfflineDriveArray;
var
  Mask: DWORD;
  C: Char;
  Root: string;
  Buf: array[0..MAX_PATH] of WideChar;
  OldMode: UINT;
  N: Integer;
  Info: TDriveInfo;
begin
  Result := nil;
  OldMode := SetErrorMode(SEM_FAILCRITICALERRORS);      // no "insert a disk" pop-ups for empty card readers
  try
    Mask := GetLogicalDrives;
    for C := 'A' to 'Z' do
    begin
      if (Mask and (1 shl (Ord(C) - Ord('A')))) = 0 then Continue;
      if C = SystemDriveLetter then Continue;           // never the drive Windows is on
      Root := C + ':\';
      if not (GetDriveTypeW(PWideChar(Root)) in [DRIVE_FIXED, DRIVE_REMOVABLE]) then Continue;
      FillChar(Buf, SizeOf(Buf), 0);
      if not GetVolumeInformationW_(PWideChar(Root), Buf, MAX_PATH, nil, nil, nil, nil, 0) then Continue;
      if not IsOfflineLabel(string(PWideChar(@Buf[0]))) then Continue;
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Root := Root;
      Result[N].Letter := C;
      Result[N].VolLabel := PWideChar(@Buf[0]);
      Result[N].SetUp := ReadDriveInfo(Root, Info) and Info.HasList;
      Result[N].Description := Info.Description;
    end;
  finally
    SetErrorMode(OldMode);
  end;
end;

{ ---------- TOfflineCopy ---------- }

constructor TOfflineCopy.Create(const Settings: TBackupSettings; const DriveRoot, DriveLabel: string);
begin
  inherited Create;
  FSettings := Settings;
  FDrive := WithSlash(DriveRoot);
  FLabel := DriveLabel;
  FTempDir := TempDir + 'offline-copy-' + IntToStr(GetCurrentProcessId) + '-';
end;

procedure TOfflineCopy.Cancel;
begin
  FCancelled := True;
  if FProcess <> 0 then TerminateProcess(FProcess, 16);
end;

function TOfflineCopy.DriveTag: string;
begin
  Result := FLabel + ' (' + NoTrailingSlash(FDrive) + ')';
  if Length(FDrive) = 3 then Result := FLabel + ' (' + Copy(FDrive, 1, 2) + ')';
end;

procedure TOfflineCopy.Log(const Msg: string);
begin
  AppendLogLine(FSettings.LogFile, Msg);
  if Assigned(FOnLog) then FOnLog(Msg);
end;

{ robocopy options shared by the dry run and the real copy:
  /MIR mirror  /XJ skip junctions  /XD skip half-finished pulls and the excluded folders  /FFT tolerant timestamps
  /BYTES exact sizes  /FP full paths }
function TOfflineCopy.RoboArgs(const Src, Dest: string): string;

  function Q(const P: string): string;
  begin
    // a trailing backslash would escape the closing quote, so "G:\" becomes "G:\."
    Result := NoTrailingSlash(P);
    if Result[Length(Result)] = '\' then Result := Result + '.';
    Result := '"' + Result + '"';
  end;

var
  I: Integer;
begin
  Result := Q(Src) + ' ' + Q(Dest) + ' /MIR /XJ /FFT /BYTES /FP /NP /XD "*.partial"';
  for I := 0 to High(FSettings.Exclude) do
    if Trim(FSettings.Exclude[I]) <> '' then Result := Result + ' ' + Q(Trim(FSettings.Exclude[I]));
end;

{ Dry run: what would robocopy do? Counts, bytes to copy, and the destination paths it would overwrite or delete. }
function TOfflineCopy.GetCopyPlan(const Src, Dest: string): TCopyPlan;

  { the part of Path inside Root ('' for Root itself) }
  function Inside(const Path, Root: string): string;
  begin
    Result := Copy(Path, Length(Root) + 2, MaxInt);
  end;

  procedure AddItem(Kind: TPreviewKind; const Rel: string; Size: Int64);
  var
    N: Integer;
  begin
    N := Length(Result.Items);
    SetLength(Result.Items, N + 1);
    Result.Items[N].Kind := Kind;
    Result.Items[N].Rel := Rel;
    Result.Items[N].Size := Size;
  end;

var
  Preview, Text, Line, Kw, P, SrcRoot, DestRoot: string;
  Lines: TPathList;
  Pos: Int64;
  Num: Int64;
  H: THandle;
  I: Integer;
begin
  Result := TCopyPlan.Create;
  Preview := FTempDir + 'preview.log';
  DeleteFileW(PWideChar(Preview));
  H := StartRobocopy(RoboArgs(Src, Dest) + ' /L /NJH /R:0 /W:0 "/UNILOG:' + Preview + '"');
  if H = 0 then raise Exception.Create('could not start robocopy');
  FProcess := H;
  try
    WaitForSingleObject(H, INFINITE);
  finally
    FProcess := 0;
    CloseHandle(H);
  end;
  SrcRoot := NoTrailingSlash(Src);
  DestRoot := NoTrailingSlash(Dest);
  Pos := 0;
  Text := ReadUnicodeFrom(Preview, Pos);
  DeleteFileW(PWideChar(Preview));
  Lines := SplitLines(Text);
  for I := 0 to High(Lines) do
  begin
    Line := Lines[I];
    if ParseRoboLine(Line, ['New File'], Kw, Num, P) then
    begin
      Inc(Result.NewFiles);
      Inc(Result.Bytes, Num);
      AddItem(pkAdd, Inside(P, SrcRoot), Num);
    end
    else if ParseRoboLine(Line, ['Newer', 'Older', 'Changed', 'Modified', 'Tweaked'], Kw, Num, P) then
    begin
      Inc(Result.Changed);
      Inc(Result.Bytes, Num);
      AddPath(Result.Overwrite, DestRoot + Copy(P, Length(SrcRoot) + 1, MaxInt));   // source path -> same place on the drive
      AddItem(pkUpdate, Inside(P, SrcRoot), Num);
    end
    else if ParseRoboLine(Line, ['*EXTRA File'], Kw, Num, P) then
    begin
      Inc(Result.Deleted);
      AddPath(Result.DeleteFiles, P);
      AddItem(pkDelete, Inside(P, DestRoot), Num);
    end
    else if ParseRoboLine(Line, ['*EXTRA Dir'], Kw, Num, P) then
    begin
      AddPath(Result.DeleteDirs, NoTrailingSlash(P));
      AddItem(pkDirDelete, Inside(NoTrailingSlash(P), DestRoot), -1);
    end
    else if ParseRoboLine(Line, ['New Dir'], Kw, Num, P) then
    begin
      if Inside(NoTrailingSlash(P), SrcRoot) <> '' then     // the folder itself on a first copy is not news
        AddItem(pkDirAdd, Inside(NoTrailingSlash(P), SrcRoot), -1);
    end
    else if Copy(TrimLeft(Line), 1, 5) = 'Files' then
    begin
      // summary line "    Files :     1234    ..." - the first number is the total
      P := TrimLeft(Copy(TrimLeft(Line), 6, MaxInt));
      if (P <> '') and (P[1] = ':') then
      begin
        P := TrimLeft(Copy(P, 2, MaxInt));
        Kw := '';
        while (P <> '') and CharInSet(P[1], ['0'..'9']) do
        begin
          Kw := Kw + P[1];
          Delete(P, 1, 1);
        end;
        if Kw <> '' then Result.Total := StrToInt(Kw);
      end;
    end;
  end;
  // (robocopy also lists each file inside a folder it will remove as *EXTRA File, so those are already counted)
end;

{ Brake: does this plan change or delete a suspiciously large share of what is already on the drive? }
function TOfflineCopy.NeedsConfirmation(Plan: TCopyPlan): Boolean;
var
  Existing, Risky: Integer;
begin
  Existing := Plan.Total - Plan.NewFiles + Plan.Deleted;
  if Existing < 1 then Existing := 1;
  Risky := Plan.Changed + Plan.Deleted;
  Result := (Risky >= FSettings.BrakeMinFiles) and (100.0 * Risky / Existing > FSettings.BrakePercent);
end;

{ Move everything the copy would overwrite or delete into <drive>\_versions\<stamp>\<folder>\..., keeping its path.
  Folder is the source's place on the drive (G-mirror\Backups); sets made before sources had drive letters
  have just the name (Backups). }
procedure TOfflineCopy.SaveVersions(Plan: TCopyPlan; const Folder, Dest, Stamp: string; out Moved, Failed: Integer);
var
  VerRoot, DestRoot, Path, Target: string;
  All: TPathList;
  I: Integer;
  Flags: DWORD;
begin
  Moved := 0;
  Failed := 0;
  VerRoot := FDrive + VersionsDir + '\' + Stamp + '\' + Folder;
  DestRoot := NoTrailingSlash(Dest);
  All := nil;
  for I := 0 to High(Plan.Overwrite) do AddPath(All, Plan.Overwrite[I]);
  for I := 0 to High(Plan.DeleteFiles) do AddPath(All, Plan.DeleteFiles[I]);
  for I := 0 to High(Plan.DeleteDirs) do AddPath(All, Plan.DeleteDirs[I]);
  for I := 0 to High(All) do
  begin
    Path := NoTrailingSlash(All[I]);
    if not PathExists(Path) then Continue;
    // only ever move things that really are under this folder's mirror on this drive
    if not SameText(Copy(Path, 1, Length(DestRoot) + 1), DestRoot + '\') then
    begin
      Inc(Failed);
      Continue;
    end;
    Target := VerRoot + Copy(Path, Length(DestRoot) + 1, MaxInt);
    // a deleted folder that is empty by now (its files moved elsewhere on the drive, or already put in _versions
    // just above): nothing in it to keep, so it is simply removed - not counted as an old version
    if IsDir(Path) and RemoveDirectoryW(PWideChar(Path)) then Continue;
    MakeDirs(ParentDir(Target));
    Flags := 0;
    if not IsDir(Path) then Flags := MOVEFILE_REPLACE_EXISTING;
    if MoveFileExW(PWideChar(Path), PWideChar(Target), Flags) then Inc(Moved) else Inc(Failed);
  end;
end;

function IsStampName(const S: string; out When: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi: Integer;
begin
  // yyyy-MM-dd_HHmm
  Result := (Length(S) = 15) and (S[5] = '-') and (S[8] = '-') and (S[11] = '_') and
    TryStrToInt(Copy(S, 1, 4), Y) and TryStrToInt(Copy(S, 6, 2), Mo) and TryStrToInt(Copy(S, 9, 2), D) and
    TryStrToInt(Copy(S, 12, 2), H) and TryStrToInt(Copy(S, 14, 2), Mi) and
    TryEncodeDate(Y, Mo, D, When) and (H < 24) and (Mi < 60);
  if Result then When := When + EncodeTime(H, Mi, 0, 0);
end;

{ Remove versions older than KeepVersionDays, then the oldest until the drive is at most MaxDriveFullPct full }
function TOfflineCopy.RemoveOldVersions: Integer;
var
  Root: string;
  Sets, Kept: TPathList;
  H: THandle;
  FD: TWin32FindDataW;
  When: TDateTime;
  FreeBytes: Int64;
  I, J: Integer;
  T: string;
begin
  Result := 0;
  Root := FDrive + VersionsDir;
  if not IsDir(Root) then Exit;
  Sets := nil;
  H := FindFirstFileW(PWideChar(Root + '\*'), FD);
  if H <> INVALID_HANDLE_VALUE then
  try
    repeat
      if (FD.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0) and IsStampName(string(FD.cFileName), When) then
        AddPath(Sets, string(FD.cFileName));
    until not FindNextFileW(H, FD);
  finally
    Windows.FindClose(H);
  end;
  // oldest first (the names sort by date)
  for I := 1 to High(Sets) do
  begin
    T := Sets[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(Sets[J], T) > 0) do
    begin
      Sets[J + 1] := Sets[J];
      Dec(J);
    end;
    Sets[J + 1] := T;
  end;
  Kept := nil;
  for I := 0 to High(Sets) do
    if IsStampName(Sets[I], When) and (When < Now - FSettings.KeepVersionDays) then
    begin
      DeleteTree(Root + '\' + Sets[I]);
      Inc(Result);
    end
    else
      AddPath(Kept, Sets[I]);
  I := 0;
  while (Length(Kept) - I > 1) and (VolumeUsedPct(FDrive, FreeBytes) > FSettings.MaxDriveFullPct) do
  begin
    DeleteTree(Root + '\' + Kept[I]);
    Inc(Result);
    Inc(I);
  end;
end;

const
  SpeedSamples = 6;      // speed is averaged over the last 5 seconds (one sample a second)

{ Fills in the time-based fields of FProgress and passes it to OnProgress }
procedure TOfflineCopy.Report;
begin
  with FProgress do
  begin
    if BytesCopied > BytesTotal then BytesCopied := BytesTotal;   // files can grow between the dry run and the copy
    if BytesTotal > 0 then Percent := Trunc(100.0 * BytesCopied / BytesTotal)
    else if FilesTotal > 0 then Percent := Trunc(100.0 * FilesDone / FilesTotal)
    else Percent := 100;
    if Percent > 100 then Percent := 100;
    if FCopyStarted > 0 then Elapsed := Round((Now - FCopyStarted) * 86400) else Elapsed := 0;
    // time left from the whole run's average speed - steadier than the current speed
    if BytesCopied >= BytesTotal then SecondsLeft := 0
    else if (Elapsed >= 5) and (BytesCopied > 0) then SecondsLeft := Round((BytesTotal - BytesCopied) / (BytesCopied / Elapsed))
    else SecondsLeft := -1;
  end;
  if Assigned(FOnProgress) then FOnProgress(FProgress);
end;

{ Run robocopy and keep FProgress up to date from the files it logs and from its own write counter.
  The log names each file as it starts; the write counter moves smoothly even inside a large file. }
function TOfflineCopy.CopyWithProgress(const Name, Src, Dest: string; Plan: TCopyPlan): Integer;
var
  RunLog, Chunk, Pending, Line, Kw, P, CurPath: string;
  Lines: TPathList;
  Pos, Num, CurSize, BytesBefore, DoneBytes, ErrBytes: Int64;
  H: THandle;
  Code: DWORD;
  Finished, HaveCur: Boolean;
  I, Cut, Done, Errs: Integer;
  Io: TIoCounters;
  SampleBytes: array[0..SpeedSamples - 1] of UInt64;
  SampleTime: array[0..SpeedSamples - 1] of TDateTime;
  Samples: Integer;

  procedure FileFinished;
  begin
    if not HaveCur then Exit;
    AddPath(FCopied, CurPath);
    Inc(Done);
    Inc(DoneBytes, CurSize);
    Inc(FProgress.FilesDone);
    Inc(FProgress.FilesDoneBytes, CurSize);
    HaveCur := False;
  end;

begin
  FCopied := nil;
  RunLog := FTempDir + 'run.log';
  DeleteFileW(PWideChar(RunLog));
  H := StartRobocopy(RoboArgs(Src, Dest) + ' /NJH /R:2 /W:5 "/UNILOG:' + RunLog + '"');
  if H = 0 then raise Exception.Create('could not start robocopy');
  FProcess := H;
  BytesBefore := FProgress.BytesCopied;
  Pos := 0;
  Pending := '';
  Samples := 0;
  HaveCur := False;
  CurSize := 0;
  Done := 0;
  Errs := 0;
  DoneBytes := 0;
  ErrBytes := 0;
  try
    repeat
      Finished := WaitForSingleObject(H, 1000) = WAIT_OBJECT_0;
      Chunk := ReadUnicodeFrom(RunLog, Pos);
      if Chunk <> '' then
      begin
        // only whole lines - the last one may still be being written
        Pending := Pending + Chunk;
        Cut := Length(Pending);
        while (Cut > 0) and (Pending[Cut] <> #10) do Dec(Cut);
        Lines := SplitLines(Copy(Pending, 1, Cut));
        Delete(Pending, 1, Cut);
        for I := 0 to High(Lines) do
        begin
          Line := Lines[I];
          if ParseRoboLine(Line, CopyKeywords, Kw, Num, P) then
          begin
            // a file line means the one before it is finished - unless robocopy is retrying the same file
            if not (HaveCur and SameText(P, CurPath)) then FileFinished;
            HaveCur := True;
            CurPath := P;
            CurSize := Num;
          end
          else if HaveCur and (System.Pos('RETRY LIMIT EXCEEDED', Line) > 0) then
          begin
            Inc(Errs);
            Inc(ErrBytes, CurSize);
            Inc(FProgress.Errors);
            Inc(FProgress.ErrorBytes, CurSize);
            HaveCur := False;
          end;
        end;
      end;
      if Finished and not FCancelled then FileFinished;
      if GetProcessIoCounters_(H, Io) then
      begin
        FProgress.BytesCopied := BytesBefore + Int64(Io.WriteTransferCount);
        if Samples = SpeedSamples then
        begin
          Move(SampleBytes[1], SampleBytes[0], (SpeedSamples - 1) * SizeOf(UInt64));
          Move(SampleTime[1], SampleTime[0], (SpeedSamples - 1) * SizeOf(TDateTime));
          Dec(Samples);
        end;
        SampleBytes[Samples] := Io.WriteTransferCount;
        SampleTime[Samples] := Now;
        Inc(Samples);
        // with only one sample so far (a new folder), the last folder's speed stays on show
        if (Samples > 1) and (SampleTime[Samples - 1] > SampleTime[0]) then
          FProgress.Speed := Round((SampleBytes[Samples - 1] - SampleBytes[0]) /
            ((SampleTime[Samples - 1] - SampleTime[0]) * 86400));
      end;
      Report;
    until Finished;
    if not GetExitCodeProcess(H, Code) then Code := 16;
    Result := Integer(Code);
  finally
    FProcess := 0;
    CloseHandle(H);
  end;
  if not FCancelled then
  begin
    // whatever the plan listed but robocopy neither copied nor failed on was skipped (e.g. deleted from G: meanwhile)
    I := Plan.NewFiles + Plan.Changed - Done - Errs;
    if I > 0 then
    begin
      Inc(FProgress.Skipped, I);
      Num := Plan.Bytes - DoneBytes - ErrBytes;
      if Num > 0 then Inc(FProgress.SkippedBytes, Num);
    end;
    // the write counter also counts robocopy's own log, so settle on the folder's real size
    FProgress.BytesCopied := BytesBefore + Plan.Bytes;
    Report;
  end;
  // keep robocopy's end-of-run summary in the log on the drive
  Pos := 0;
  Lines := SplitLines(ReadUnicodeFrom(RunLog, Pos));
  Chunk := '===== ' + Name + '  ' + FormatDateTime('yyyy-mm-dd hh:nn', Now) + #13#10;
  for I := Length(Lines) - 14 to High(Lines) do
    if I >= 0 then Chunk := Chunk + Lines[I] + #13#10;
  AppendText(FDrive + 'G-mirror-robocopy.log', Chunk);
  DeleteFileW(PWideChar(RunLog));
end;

{ Folders taken off the drive's list: their copy on the drive is moved to _versions\<stamp>\<letter>-mirror\<name>,
  where the usual pruning removes it later. Runs only after the dry run and brake have passed. }
procedure TOfflineCopy.MoveRemovedFolders(const Stamp: string);
var
  Left: TPathList;
  R, Target: string;
  I, J, P: Integer;
  OnList: Boolean;
begin
  Left := nil;
  for I := 0 to High(FInfo.Removed) do
  begin
    R := NoTrailingSlash(FInfo.Removed[I]);
    // only ever '<letter>-mirror\<name>' - nothing else on the drive
    P := Pos('\', R);
    if (P <> 9) or (Copy(R, 2, 7) <> '-mirror') or not CharInSet(UpCase(R[1]), ['A'..'Z']) or
       not ValidSourceName(Copy(R, P + 1, MaxInt)) then
    begin
      Log(DriveTag + ': ignored odd entry in the remove list: ' + R);
      Continue;
    end;
    // added back since? then it stays
    OnList := False;
    for J := 0 to High(FList) do
      if SameText(MirrorFolder(FList[J]), R) then OnList := True;
    if OnList then Continue;
    if not IsDir(FDrive + R) then Continue;     // already gone
    Target := FDrive + VersionsDir + '\' + Stamp + '\' + R;
    MakeDirs(ParentDir(Target));
    if MoveFileExW(PWideChar(FDrive + R), PWideChar(Target), 0) then
    begin
      DeleteFileW(PWideChar(FDrive + ChecksumDir + '\' + R + '.crc'));
      DeleteFileW(PWideChar(FDrive + R + '.md5'));
      Log('  ' + R + ': taken off this drive''s list - moved to _versions\' + Stamp);
    end
    else
    begin
      Log('  ' + R + ': taken off this drive''s list, but could not be moved to _versions - tried again next time');
      AddPath(Left, FInfo.Removed[I]);
    end;
  end;
  FInfo.Removed := Left;
end;

{ Adds this run to the drive map and writes it to the drive (and the PC's copy) }
procedure TOfflineCopy.SaveHistory(R: TCopyResult);
var
  Run: TDriveRun;
  I: Integer;
begin
  FHistorySaved := True;
  Run.When := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  Run.PC := ComputerName;
  Run.Result := CopyResultText(R);
  Run.Bytes := FProgress.FilesDoneBytes;
  Run.Folders := '';
  for I := 0 to High(FList) do
    if FList[I].Enabled then
    begin
      if Run.Folders <> '' then Run.Folders := Run.Folders + ', ';
      Run.Folders := Run.Folders + FList[I].Name;
    end;
  if FInfo.VolLabel <> FLabel then
  begin
    if FInfo.VolLabel <> '' then Log(DriveTag + ': was labelled ' + FInfo.VolLabel + ' when it was set up');
    FInfo.VolLabel := FLabel;
  end;
  AddDriveRun(FInfo, Run);
  if not WriteDriveInfo(FDrive, FInfo) then Log(DriveTag + ': could not update ' + DriveMapName + ' on the drive');
end;

{ Files that only moved inside a backup folder: a "new" file with the same size and last-write time as a "deleted"
  one on the drive, whose CRC32 (and MD5, if recorded) from the source match the checksum recorded for the drive copy.
  Such pairs become one pkMove item; DoMoves moves the file on the drive, so nothing is copied again. Only the
  recorded checksums of files that have one can be matched - files copied before checksums were kept need a Verify. }
procedure TOfflineCopy.FindMoves(const Src: TBackupSource; Plan: TCopyPlan);
var
  List: TCrcList;
  Adds, Dels: array of Integer;     // indexes into Plan.Items
  Used: array of Boolean;
  Dest, SrcRoot, Key: string;
  Sums: array of record Done, Ok: Boolean; Crc: Cardinal; Md5: string; Time: Int64; end;
  Size, Time: Int64;
  I, J, K, N: Integer;
  Keep: TPreviewItems;
  DelKeys: TPathList;
begin
  Adds := nil;
  Dels := nil;
  for I := 0 to High(Plan.Items) do
    if Plan.Items[I].Kind = pkAdd then
    begin
      SetLength(Adds, Length(Adds) + 1);
      Adds[High(Adds)] := I;
    end
    else if Plan.Items[I].Kind = pkDelete then
    begin
      SetLength(Dels, Length(Dels) + 1);
      Dels[High(Dels)] := I;
    end;
  if (Length(Adds) = 0) or (Length(Dels) = 0) then Exit;
  List := LoadCrcList(FDrive + ChecksumDir + '\' + MirrorFolder(Src) + '.crc');
  if Length(List) = 0 then Exit;
  FProgress.Status := 'Looking for moved files in ' + Src.Name + ' ...';
  Report;
  Dest := FDrive + MirrorFolder(Src) + '\';
  SrcRoot := NoTrailingSlash(Src.Path) + '\';
  SetLength(Used, Length(Dels));
  SetLength(Sums, Length(Adds));
  for I := 0 to High(Adds) do
  begin
    if FCancelled then Exit;
    for J := 0 to High(Dels) do
    begin
      if Used[J] or (Plan.Items[Dels[J]].Size <> Plan.Items[Adds[I]].Size) then Continue;
      K := FindCrc(List, UpperCase(Plan.Items[Dels[J]].Rel));
      if (K < 0) or (List[K].Size <> Plan.Items[Dels[J]].Size) then Continue;
      // the drive copy must still be as recorded ...
      if not FileStamp(Dest + Plan.Items[Dels[J]].Rel, Size, Time) or (Time <> List[K].Time) then Continue;
      // ... and the source file must have its time (else robocopy would copy it anyway) and its checksums
      if not Sums[I].Done then
      begin
        Sums[I].Done := True;
        Sums[I].Ok := FileStamp(SrcRoot + Plan.Items[Adds[I]].Rel, Size, Sums[I].Time) and
          FileSums(SrcRoot + Plan.Items[Adds[I]].Rel, False, Sums[I].Crc, Sums[I].Md5, nil, @FCancelled);
      end;
      if not Sums[I].Ok or (Sums[I].Time <> List[K].Time) or (Sums[I].Crc <> List[K].Crc) or
         ((List[K].Md5 <> '') and (List[K].Md5 <> Sums[I].Md5)) then Continue;
      Used[J] := True;
      Plan.Items[Adds[I]].Kind := pkMove;
      Plan.Items[Adds[I]].From := Plan.Items[Dels[J]].Rel;
      Plan.Items[Dels[J]].Kind := pkFolderRemove;    // marks it for removal just below
      Dec(Plan.NewFiles);
      Dec(Plan.Deleted);
      Dec(Plan.Bytes, Plan.Items[Adds[I]].Size);
      Inc(Plan.Moved);
      Break;
    end;
  end;
  if Plan.Moved = 0 then Exit;
  // drop the matched deletes from the items and from the files robocopy's deletions would version
  Keep := nil;
  DelKeys := nil;
  N := 0;
  SetLength(Keep, Length(Plan.Items));
  for I := 0 to High(Plan.Items) do
    if Plan.Items[I].Kind = pkFolderRemove then AddPath(DelKeys, UpperCase(Dest + Plan.Items[I].Rel))
    else
    begin
      Keep[N] := Plan.Items[I];
      Inc(N);
    end;
  SetLength(Keep, N);
  Plan.Items := Keep;
  N := 0;
  for I := 0 to High(Plan.DeleteFiles) do
  begin
    Key := UpperCase(Plan.DeleteFiles[I]);
    K := 0;
    while (K <= High(DelKeys)) and (DelKeys[K] <> Key) do Inc(K);
    if K > High(DelKeys) then
    begin
      Plan.DeleteFiles[N] := Plan.DeleteFiles[I];
      Inc(N);
    end;
  end;
  SetLength(Plan.DeleteFiles, N);
end;

{ Carries out the moves FindMoves found: each file is moved on the drive (instantly, same volume) and its recorded
  checksum goes with it. A move that fails puts the old copy back on the delete list, so it is kept in _versions
  and robocopy copies the file as a new one - nothing is lost either way. }
procedure TOfflineCopy.DoMoves(const Src: TBackupSource; Plan: TCopyPlan);
var
  Dest, OldPath, NewPath, ListFile: string;
  List: TCrcList;
  I, K, Done: Integer;
  Bytes: Int64;
begin
  if Plan.Moved = 0 then Exit;
  Dest := FDrive + MirrorFolder(Src) + '\';
  ListFile := FDrive + ChecksumDir + '\' + MirrorFolder(Src) + '.crc';
  List := LoadCrcList(ListFile);
  Done := 0;
  Bytes := 0;
  for I := 0 to High(Plan.Items) do
  begin
    if Plan.Items[I].Kind <> pkMove then Continue;
    OldPath := Dest + Plan.Items[I].From;
    NewPath := Dest + Plan.Items[I].Rel;
    MakeDirs(ParentDir(NewPath));
    if not PathExists(NewPath) and MoveFileExW(PWideChar(OldPath), PWideChar(NewPath), 0) then
    begin
      Inc(Done);
      Inc(Bytes, Plan.Items[I].Size);
      K := FindCrc(List, UpperCase(Plan.Items[I].From));
      if K >= 0 then
      begin
        List[K].Rel := Plan.Items[I].Rel;
        List[K].Key := UpperCase(Plan.Items[I].Rel);
        SortCrcList(List, 0, High(List));
      end;
    end
    else
    begin
      Log('  ' + Src.Name + ': could not move ' + Plan.Items[I].From + ' - it is copied instead');
      if PathExists(OldPath) then AddPath(Plan.DeleteFiles, OldPath);
    end;
  end;
  Inc(FProgress.Moved, Done);
  if Done > 0 then
  begin
    if not SaveCrcList(ListFile, List) or not SaveMd5File(FDrive + MirrorFolder(Src) + '.md5', Src.Name, List) then
      Log('  ' + Src.Name + ': could not save its checksums');
    Log(Format('  %s: moved %d file(s) on the drive - %s not copied again', [Src.Name, Done, FormatSize(Bytes)]));
  end;
end;

{ safety: the target must be a drive whose label is OFFLINE-x and still is (unless a test points it at a folder) }
function TOfflineCopy.CheckTarget: Boolean;
var
  Buf: array[0..MAX_PATH] of WideChar;
begin
  Result := True;
  if AllowFolderTarget then Exit;
  FillChar(Buf, SizeOf(Buf), 0);
  if (Length(FDrive) <> 3) or (UpCase(FDrive[1]) = SystemDriveLetter) or
     not GetVolumeInformationW_(PWideChar(FDrive), Buf, MAX_PATH, nil, nil, nil, nil, 0) or
     not IsOfflineLabel(string(PWideChar(@Buf[0]))) then
  begin
    Log(DriveTag + ': not an OFFLINE-x drive any more - nothing done');
    Result := False;
  end;
end;

{ After a folder is copied: the CRC32 of each file robocopy copied, read from the source and kept only if the source
  still has the size and time the drive copy has (a file changed during the copy gets no checksum until next time).
  Files robocopy deleted from the drive leave the list. }
procedure TOfflineCopy.RecordChecksums(const Folder, Src, Dest: string; Plan: TCopyPlan);
var
  ListFile, SrcRoot, DestRoot, Rel, Md5: string;
  Old, New, Added, DelFiles: TCrcList;
  DelDirs: TPathList;
  Crc: Cardinal;
  SSize, STime, DSize, DTime: Int64;
  I, J, N: Integer;
  Gone: Boolean;
begin
  if (Length(FCopied) = 0) and (Length(Plan.DeleteFiles) = 0) and (Length(Plan.DeleteDirs) = 0) then Exit;
  ListFile := FDrive + ChecksumDir + '\' + Folder + '.crc';
  SrcRoot := NoTrailingSlash(Src) + '\';
  DestRoot := NoTrailingSlash(Dest) + '\';
  FProgress.Status := 'Recording checksums for ' + FProgress.Folder + ' (' + IntToStr(Length(FCopied)) + ' files)';
  Report;
  Added := nil;
  for I := 0 to High(FCopied) do
  begin
    if FCancelled then Exit;
    if not SameText(Copy(FCopied[I], 1, Length(SrcRoot)), SrcRoot) then Continue;
    Rel := Copy(FCopied[I], Length(SrcRoot) + 1, MaxInt);
    if FileSums(FCopied[I], False, Crc, Md5, nil, @FCancelled) and FileStamp(FCopied[I], SSize, STime) and
       FileStamp(DestRoot + Rel, DSize, DTime) and (SSize = DSize) and (STime = DTime) then
    begin
      SetLength(Added, Length(Added) + 1);
      Added[High(Added)] := CrcEntry(Rel, Crc, Md5, DSize, DTime);
    end;
  end;
  SortCrcList(Added, 0, High(Added));
  // files robocopy deleted (and whole deleted folders) - their paths are on the drive
  DelFiles := nil;
  for I := 0 to High(Plan.DeleteFiles) do
    if SameText(Copy(Plan.DeleteFiles[I], 1, Length(DestRoot)), DestRoot) then
    begin
      SetLength(DelFiles, Length(DelFiles) + 1);
      DelFiles[High(DelFiles)] := CrcEntry(Copy(Plan.DeleteFiles[I], Length(DestRoot) + 1, MaxInt), 0, '', 0, 0);
    end;
  DelDirs := nil;
  for I := 0 to High(Plan.DeleteDirs) do
    if SameText(Copy(Plan.DeleteDirs[I], 1, Length(DestRoot)), DestRoot) then
      AddPath(DelDirs, UpperCase(Copy(NoTrailingSlash(Plan.DeleteDirs[I]), Length(DestRoot) + 1, MaxInt)) + '\');
  // copied files also leave their old entry: a copied file without a new checksum (changed meanwhile) has none
  for I := 0 to High(FCopied) do
    if SameText(Copy(FCopied[I], 1, Length(SrcRoot)), SrcRoot) then
    begin
      SetLength(DelFiles, Length(DelFiles) + 1);
      DelFiles[High(DelFiles)] := CrcEntry(Copy(FCopied[I], Length(SrcRoot) + 1, MaxInt), 0, '', 0, 0);
    end;
  SortCrcList(DelFiles, 0, High(DelFiles));

  Old := LoadCrcList(ListFile);
  SetLength(New, Length(Old) + Length(Added));
  N := 0;
  for I := 0 to High(Old) do
  begin
    Gone := False;
    for J := 0 to High(DelDirs) do
      if Copy(Old[I].Key, 1, Length(DelDirs[J])) = DelDirs[J] then Gone := True;
    if FindCrc(DelFiles, Old[I].Key) >= 0 then Gone := True;
    if Gone or (FindCrc(Added, Old[I].Key) >= 0) then Continue;
    New[N] := Old[I];
    Inc(N);
  end;
  for I := 0 to High(Added) do
  begin
    New[N] := Added[I];
    Inc(N);
  end;
  SetLength(New, N);
  if not SaveCrcList(ListFile, New) or not SaveMd5File(FDrive + Folder + '.md5', FProgress.Folder, New) then
    Log('  ' + FProgress.Folder + ': could not save its checksums');
end;

{ seconds since Start, at least 1 }
function Seconds(Start: TDateTime): Double;
begin
  Result := (Now - Start) * 86400;
  if Result < 1 then Result := 1;
end;

procedure TOfflineCopy.CountBytes(N: Int64);
var
  T: DWORD;
begin
  Inc(FProgress.BytesCopied, N);
  T := GetTickCount;
  if T - FLastReport >= 500 then
  begin
    FLastReport := T;
    if FCopyStarted > 0 then FProgress.Speed := Round(FProgress.BytesCopied / Seconds(FCopyStarted));
    Report;
  end;
end;

{ Sets a file's last-write time to 1990, so robocopy sees it as older than the source and copies it again }
function MarkForRecopy(const Path: string): Boolean;
var
  H: THandle;
  T: Int64;
  FT: TFileTime;
begin
  T := Int64(Trunc(EncodeDate(1990, 1, 1) - EncodeDate(1601, 1, 1))) * 864000000000;
  FT.dwLowDateTime := DWORD(T and $FFFFFFFF);
  FT.dwHighDateTime := DWORD(T shr 32);
  H := CreateFileW(PWideChar(Path), FILE_WRITE_ATTRIBUTES, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if not Result then Exit;
  Result := SetFileTime(H, nil, nil, @FT);
  CloseHandle(H);
end;

function TOfflineCopy.Verify: TCopyResult;
type
  TFound = record
    Rel: string;
    Size: Int64;
  end;
var
  Files: array of array of TFound;
  Folders: TBackupSourceArray;
  Dirs: TPathList;
  Old, New: TCrcList;
  Crc: Cardinal;
  Md5: string;
  Size, Time: Int64;
  I, J, K, Good, Bad, Recorded, NewCount: Integer;
  Total: Int64;
  Run: TDriveRun;
  Names: string;

  procedure Scan(const Root, Sub: string; Idx: Integer);
  var
    H: THandle;
    FD: TWin32FindDataW;
    Name: string;
  begin
    H := FindFirstFileW(PWideChar(Root + Sub + '*'), FD);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      repeat
        Name := FD.cFileName;
        if (Name = '.') or (Name = '..') then Continue;
        if FD.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0 then
        begin
          if FD.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT = 0 then Scan(Root, Sub + Name + '\', Idx);
        end
        else
        begin
          SetLength(Files[Idx], Length(Files[Idx]) + 1);
          Files[Idx][High(Files[Idx])].Rel := Sub + Name;
          Files[Idx][High(Files[Idx])].Size := Int64(FD.nFileSizeLow) or (Int64(FD.nFileSizeHigh) shl 32);
          Inc(Total, Files[Idx][High(Files[Idx])].Size);
        end;
      until not FindNextFileW(H, FD);
    finally
      Windows.FindClose(H);
    end;
  end;

begin
  Result := crFailed;
  if not CheckTarget then Exit;
  if not ReadDriveInfo(FDrive, FInfo) or not FInfo.HasList then
  begin
    Log(DriveTag + ': not set up, or no folders chosen yet - nothing to verify');
    SkipReason := 'not set up, or no folders chosen yet - nothing to verify';
    Exit(crSkipped);
  end;
  try
    FProgress := Default(TCopyProgress);
    FProgress.Verifying := True;
    FProgress.Speed := -1;
    FProgress.Status := 'Listing the files on the drive ...';
    FCopyStarted := 0;
    Report;
    // every folder on the drive's list, ticked or not - an unticked folder's copy is still on the drive
    Folders := nil;
    Dirs := nil;
    Total := 0;
    for I := 0 to High(FInfo.Sources) do
      if IsDir(FDrive + MirrorFolder(FInfo.Sources[I])) then
      begin
        SetLength(Folders, Length(Folders) + 1);
        Folders[High(Folders)] := FInfo.Sources[I];
        AddPath(Dirs, FDrive + MirrorFolder(FInfo.Sources[I]) + '\');
      end;
    SetLength(Files, Length(Folders));
    for I := 0 to High(Folders) do Scan(Dirs[I], '', I);
    for I := 0 to High(Files) do Inc(FProgress.FilesTotal, Length(Files[I]));
    FProgress.BytesTotal := Total;
    Log(Format('%s: verifying %d files (%s) in %d folder(s)', [DriveTag, FProgress.FilesTotal, FormatSize(Total),
      Length(Folders)]));

    Good := 0;
    Bad := 0;
    Recorded := 0;
    FCopyStarted := Now;
    FLastReport := 0;
    for I := 0 to High(Folders) do
    begin
      if FCancelled then Break;
      FProgress.Folder := Folders[I].Name;
      FProgress.Status := 'Verifying ' + Folders[I].Name + '  (folder ' + IntToStr(I + 1) + ' of ' +
        IntToStr(Length(Folders)) + ')';
      Report;
      Old := LoadCrcList(FDrive + ChecksumDir + '\' + MirrorFolder(Folders[I]) + '.crc');
      SetLength(New, Length(Files[I]));
      NewCount := 0;
      for J := 0 to High(Files[I]) do
      begin
        if FCancelled then Break;
        if not FileSums(Dirs[I] + Files[I][J].Rel, True, Crc, Md5, CountBytes, @FCancelled) or
           not FileStamp(Dirs[I] + Files[I][J].Rel, Size, Time) then
        begin
          if FCancelled then Break;
          Inc(Bad);
          Inc(FProgress.Errors);
          Inc(FProgress.ErrorBytes, Files[I][J].Size);
          Log('  could not read ' + MirrorFolder(Folders[I]) + '\' + Files[I][J].Rel);
          K := FindCrc(Old, UpperCase(Files[I][J].Rel));
          if K >= 0 then
          begin
            New[NewCount] := Old[K];      // keep its checksum for the next try
            Inc(NewCount);
          end;
        end
        else
        begin
          K := FindCrc(Old, UpperCase(Files[I][J].Rel));
          if (K >= 0) and (Old[K].Size = Size) and (Old[K].Time = Time) then
          begin
            if (Old[K].Crc = Crc) and ((Old[K].Md5 = '') or (Old[K].Md5 = Md5)) then
            begin
              Inc(Good);
              New[NewCount] := Old[K];
              New[NewCount].Md5 := Md5;     // lists from before MD5s get them now
            end
            else
            begin
              Inc(Bad);
              Inc(FProgress.Errors);
              Inc(FProgress.ErrorBytes, Size);
              Log('  BAD: ' + MirrorFolder(Folders[I]) + '\' + Files[I][J].Rel + ' - does not match its checksum');
              // same size and time, so robocopy would never replace it: date it back so the next copy does
              if MarkForRecopy(Dirs[I] + Files[I][J].Rel) then Log('    it will be copied again at the next copy');
              Dec(NewCount);                // no checksum kept for it - the next copy records a fresh one
            end;
          end
          else
          begin
            // no checksum yet (copied before checksums, or changed since): record what is there now
            Inc(Recorded);
            Inc(FProgress.Skipped);
            Inc(FProgress.SkippedBytes, Size);
            New[NewCount] := CrcEntry(Files[I][J].Rel, Crc, Md5, Size, Time);
          end;
          Inc(NewCount);
        end;
        Inc(FProgress.FilesDone);
        Inc(FProgress.FilesDoneBytes, Files[I][J].Size);
      end;
      // a cancelled folder keeps its old list; files no longer on the drive drop out of a finished one
      if not FCancelled then
      begin
        SetLength(New, NewCount);
        if not SaveCrcList(FDrive + ChecksumDir + '\' + MirrorFolder(Folders[I]) + '.crc', New) or
           not SaveMd5File(FDrive + MirrorFolder(Folders[I]) + '.md5', Folders[I].Name, New) then
          Log('  ' + Folders[I].Name + ': could not save its checksums');
      end;
    end;
    if FCopyStarted > 0 then FProgress.Speed := Round(FProgress.BytesCopied / Seconds(FCopyStarted));
    Report;

    Names := '';
    for I := 0 to High(Folders) do
    begin
      if Names <> '' then Names := Names + ', ';
      Names := Names + Folders[I].Name;
    end;
    Run.When := FormatDateTime('yyyy-mm-dd hh:nn', Now);
    Run.PC := ComputerName;
    Run.Bytes := FProgress.BytesCopied;
    Run.Folders := Names;
    if FCancelled then
    begin
      Log(DriveTag + ': verify cancelled');
      Run.Result := 'verify cancelled';
      Result := crCancelled;
    end
    else if Bad > 0 then
    begin
      Log(Format('%s: verify found %d bad or unreadable file(s) - see above. %d ok, %d had no checksum yet and got one.',
        [DriveTag, Bad, Good, Recorded]));
      Run.Result := 'verify: ' + IntToStr(Bad) + ' bad';
      Result := crFailed;
    end
    else
    begin
      Log(Format('%s: verify ok - %d file(s) match, %d had no checksum yet and got one', [DriveTag, Good, Recorded]));
      Run.Result := 'verified ok';
      Result := crOk;
    end;
    AddDriveRun(FInfo, Run);
    if not WriteDriveInfo(FDrive, FInfo) then Log(DriveTag + ': could not update ' + DriveMapName + ' on the drive');
  except
    on E: Exception do
    begin
      Log('FAILED: ' + E.Message);
      Result := crFailed;
    end;
  end;
end;

function TOfflineCopy.CheckMd5(const FileName: string): TCopyResult;
var
  Lines: TPathList;
  Want: TPathList;                 // the MD5 of each item, same order as CheckItems
  Base, S, Path, Md5: string;
  Crc: Cardinal;
  Size, Time: Int64;
  I, P, Bad, Missing: Integer;

  function IsHex32(const H: string): Boolean;
  var
    K: Integer;
  begin
    Result := Length(H) = 32;
    for K := 1 to Length(H) do
      if not CharInSet(H[K], ['0'..'9', 'a'..'f', 'A'..'F']) then Result := False;
  end;

begin
  Result := crFailed;
  CheckItems := nil;
  try
    FProgress := Default(TCopyProgress);
    FProgress.Checking := True;
    FProgress.Speed := -1;
    FProgress.Status := 'Reading ' + ExtractFileName(FileName) + ' ...';
    FCopyStarted := 0;
    Report;
    if not PathExists(FileName) then
    begin
      Log(FileName + ' not found');
      Exit;
    end;
    Base := ParentDir(FileName) + '\';
    Lines := SplitLines(ReadTextFile(FileName));
    // "md5 *path" (binary, what ExactFile and we write) or "md5  path" (md5sum text mode); ; and # are comments
    Want := nil;
    for I := 0 to High(Lines) do
    begin
      S := Trim(Lines[I]);
      if (S = '') or CharInSet(S[1], [';', '#']) then Continue;
      P := System.Pos(' ', S);
      if (P <> 33) or not IsHex32(Copy(S, 1, 32)) then Continue;
      Path := TrimLeft(Copy(S, 34, MaxInt));
      if (Path <> '') and (Path[1] = '*') then Delete(Path, 1, 1);
      if Path = '' then Continue;
      SetLength(CheckItems, Length(CheckItems) + 1);
      CheckItems[High(CheckItems)].Path := Path;
      AddPath(Want, LowerCase(Copy(S, 1, 32)));
    end;
    FProgress.FilesTotal := Length(CheckItems);
    for I := 0 to High(CheckItems) do
    begin
      if (System.Pos(':', CheckItems[I].Path) > 0) or (Copy(CheckItems[I].Path, 1, 2) = '\\') then
        Path := CheckItems[I].Path
      else
        Path := Base + CheckItems[I].Path;
      if FileStamp(Path, Size, Time) then
      begin
        CheckItems[I].Size := Size;
        Inc(FProgress.BytesTotal, Size);
      end
      else
        CheckItems[I].Size := -1;
    end;
    Log(Format('%s: checking %d files (%s) against %s', [ParentDir(FileName), FProgress.FilesTotal,
      FormatSize(FProgress.BytesTotal), ExtractFileName(FileName)]));

    Bad := 0;
    Missing := 0;
    FCopyStarted := Now;
    FLastReport := 0;
    FProgress.Status := 'Checking ' + ExtractFileName(FileName);
    FProgress.Folder := ExtractFileName(FileName);     // the window shows the counts lines once Folder is set
    for I := 0 to High(CheckItems) do
    begin
      if FCancelled then Break;
      if (System.Pos(':', CheckItems[I].Path) > 0) or (Copy(CheckItems[I].Path, 1, 2) = '\\') then
        Path := CheckItems[I].Path
      else
        Path := Base + CheckItems[I].Path;
      if CheckItems[I].Size < 0 then
      begin
        CheckItems[I].Status := csMissing;
        Inc(Missing);
        Inc(FProgress.Skipped);
        Log('  missing: ' + CheckItems[I].Path);
      end
      else if not FileSums(Path, True, Crc, Md5, CountBytes, @FCancelled) then
      begin
        if FCancelled then Break;
        CheckItems[I].Status := csUnreadable;
        Inc(Bad);
        Inc(FProgress.Errors);
        Log('  could not read: ' + CheckItems[I].Path);
      end
      else if Md5 <> Want[I] then
      begin
        CheckItems[I].Status := csBad;
        Inc(Bad);
        Inc(FProgress.Errors);
        Log('  BAD: ' + CheckItems[I].Path + ' - does not match its MD5');
      end
      else
        CheckItems[I].Status := csOk;
      Inc(FProgress.FilesDone);
      if CheckItems[I].Size > 0 then Inc(FProgress.FilesDoneBytes, CheckItems[I].Size);
    end;
    if FCopyStarted > 0 then FProgress.Speed := Round(FProgress.BytesCopied / Seconds(FCopyStarted));
    Report;
    if FCancelled then
    begin
      SetLength(CheckItems, FProgress.FilesDone);
      Log(ExtractFileName(FileName) + ': check cancelled');
      Exit(crCancelled);
    end;
    if (Bad = 0) and (Missing = 0) then
    begin
      Log(Format('%s: all %d files match', [ExtractFileName(FileName), Length(CheckItems)]));
      Result := crOk;
    end
    else
      Log(Format('%s: %d bad or unreadable, %d missing, %d ok', [ExtractFileName(FileName), Bad, Missing,
        Length(CheckItems) - Bad - Missing]));
  except
    on E: Exception do
    begin
      Log('FAILED: ' + E.Message);
      Result := crFailed;
    end;
  end;
end;

function TOfflineCopy.Run: TCopyResult;
begin
  Result := crFailed;
  if not CheckTarget then Exit;
  // only drives that have been set up (they carry a drive map) are copied to
  if not ReadDriveInfo(FDrive, FInfo) then
  begin
    Log(DriveTag + ': new drive, not set up yet - nothing done. Set it up under Drives... first.');
    SkipReason := 'new drive, not set up yet - set it up under Drives... first';
    Exit(crSkipped);
  end;
  // ... and that have had their folders chosen - a drive is never filled with folders it was not set up for
  if not FInfo.HasList then
  begin
    Log(DriveTag + ': no folders chosen for this drive yet - nothing done. Choose them under Drives... first.');
    SkipReason := 'no folders chosen for this drive yet - choose them under Drives...';
    Exit(crSkipped);
  end;
  FList := Copy(FInfo.Sources);
  FHistorySaved := False;
  Result := DoRun;
  if not FHistorySaved then SaveHistory(Result);
end;

function TOfflineCopy.DoRun: TCopyResult;

  // deletes and moves change what is already on the drive - the preview shows for them even when not "always"
  function PlansDelete(const Plans: array of TCopyPlan): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to High(Plans) do
      if (Length(Plans[K].DeleteFiles) > 0) or (Length(Plans[K].DeleteDirs) > 0) or (Plans[K].Moved > 0) then
        Result := True;
  end;

  { is this remove-list entry a folder that MoveRemovedFolders will really move? }
  function RemovedWillMove(const R: string): Boolean;
  var
    K: Integer;
  begin
    Result := IsDir(FDrive + NoTrailingSlash(R));
    for K := 0 to High(FList) do
      if SameText(MirrorFolder(FList[K]), NoTrailingSlash(R)) then Result := False;
  end;

  function RemovedToMove: Integer;
  var
    K: Integer;
  begin
    Result := 0;
    for K := 0 to High(FInfo.Removed) do
      if RemovedWillMove(FInfo.Removed[K]) then Inc(Result);
  end;

var
  Preview: TCopyPreview;
  Stamp, Dest, Alarming, Status, Names, MissingNames, SrcSlash: string;
  Srcs: TBackupSourceArray;         // the ticked sources that are there, in list order
  Missing: TPathList;
  Plans: array of TCopyPlan;
  TotalBytes, FreeBytes: Int64;
  Moved, VerFailed, Rc, FailedCount, Pruned, I, J: Integer;
  GoAhead, Flushed, Skip: Boolean;
  H: THandle;
  Secs: Double;
  Src: TBackupSource;
begin
  Result := crFailed;
  // which sources, and are they all there? Settings problems stop the run before anything happens.
  Srcs := nil;
  Missing := nil;
  for I := 0 to High(FList) do
  begin
    if not FList[I].Enabled then Continue;      // unticked: left on the drive as it is
    Src := FList[I];
    Src.Path := NormalizeSourcePath(Src.Path);
    SrcSlash := WithSlash(Src.Path);
    if (SourceLetter(Src.Path) = #0) or not ValidSourceName(Src.Name) then
    begin
      Log(DriveTag + ': "' + Src.Path + '" is not a folder on a local drive - check the settings. Nothing done.');
      Exit;
    end;
    // never copy the drive onto itself, or into a folder that is being copied
    if SameText(Copy(SrcSlash, 1, Length(FDrive)), FDrive) or SameText(Copy(FDrive, 1, Length(SrcSlash)), SrcSlash) then
    begin
      Log(DriveTag + ': ' + Src.Path + ' is on the OFFLINE drive itself - check the settings. Nothing done.');
      Exit;
    end;
    for J := 0 to High(FList) do
      if (J <> I) and SameText(MirrorFolder(FList[J]), MirrorFolder(Src)) then
      begin
        Log(DriveTag + ': two folders would both go to ' + MirrorFolder(Src) + ' - check the settings. Nothing done.');
        Exit;
      end;
    if not IsDir(Src.Path) then
    begin
      Skip := False;
      if Assigned(FOnMissing) then FOnMissing(Src.Path, Skip);
      if not Skip then
      begin
        Log(DriveTag + ': ' + Src.Path + ' not found - stopped, nothing changed on the drive');
        Exit(crStopped);
      end;
      Log(DriveTag + ': ' + Src.Path + ' not found - skipped, its copy on the drive is left as it was');
      AddPath(Missing, Src.Path);
      Continue;
    end;
    SetLength(Srcs, Length(Srcs) + 1);
    Srcs[High(Srcs)] := Src;
  end;
  Stamp := FormatDateTime('yyyy-mm-dd_hhnn', Now);
  if Length(Srcs) = 0 then
  begin
    MoveRemovedFolders(Stamp);
    if Length(Missing) > 0 then
    begin
      Log(DriveTag + ': no folders to copy - the ticked ones were not found');
      SkipReason := 'its folders were not found, so nothing was copied';
    end
    else
    begin
      Log(DriveTag + ': no folders to copy - every folder on this drive is unticked');
      SkipReason := 'nothing to copy - every folder on this drive is unticked';
      NothingChosen := True;
    end;
    Exit(crSkipped);
  end;
  SetLength(Plans, Length(Srcs));
  try
    try
      FProgress := Default(TCopyProgress);
      FProgress.Speed := -1;
      FProgress.Status := 'Checking what has changed since the last copy ...';
      FCopyStarted := 0;
      Report;
      TotalBytes := 0;
      for I := 0 to High(Srcs) do
      begin
        if FCancelled then Exit(crCancelled);
        Plans[I] := GetCopyPlan(Srcs[I].Path, FDrive + MirrorFolder(Srcs[I]));
        FindMoves(Srcs[I], Plans[I]);
        Inc(TotalBytes, Plans[I].Bytes);
      end;
      VolumeUsedPct(FDrive, FreeBytes);
      if TotalBytes > FreeBytes then
      begin
        SkipReason := 'not enough space - needs ' + FormatSize(TotalBytes) + ', has ' + FormatSize(FreeBytes) + ' free';
        Log(DriveTag + ': not enough space - needs ' + FormatSize(TotalBytes) + ' more, has ' + FormatSize(FreeBytes) +
          ' free. Skipped.');
        Exit(crSkipped);
      end;
      for I := 0 to High(Srcs) do
        if Plans[I].Moved > 0 then
          Log(Format('%s %s: %d new, %d changed, %d deleted, %d moved, %s to copy',
            [DriveTag, Srcs[I].Name, Plans[I].NewFiles, Plans[I].Changed, Plans[I].Deleted, Plans[I].Moved,
             FormatSize(Plans[I].Bytes)]))
        else
          Log(Format('%s %s: %d new, %d changed, %d deleted, %s to copy',
            [DriveTag, Srcs[I].Name, Plans[I].NewFiles, Plans[I].Changed, Plans[I].Deleted,
             FormatSize(Plans[I].Bytes)]));

      // brake
      Alarming := '';
      for I := 0 to High(Srcs) do
        if NeedsConfirmation(Plans[I]) then
        begin
          if Alarming <> '' then Alarming := Alarming + ', ';
          Alarming := Alarming + Srcs[I].Name;
        end;
      if not AssumeYes and Assigned(FOnPreview) and (FSettings.PreviewAlways or (Alarming <> '') or
         PlansDelete(Plans) or (RemovedToMove > 0)) then
      begin
        // the preview shows everything - and answers the safety check too
        Preview := Default(TCopyPreview);
        Preview.Drive := DriveTag;
        Preview.Warning := Alarming;
        for I := 0 to High(Srcs) do
          for J := 0 to High(Plans[I].Items) do
          begin
            SetLength(Preview.Items, Length(Preview.Items) + 1);
            Preview.Items[High(Preview.Items)] := Plans[I].Items[J];
            Preview.Items[High(Preview.Items)].Folder := Srcs[I].Name;
          end;
        for I := 0 to High(FInfo.Removed) do
          if RemovedWillMove(FInfo.Removed[I]) then
          begin
            SetLength(Preview.Items, Length(Preview.Items) + 1);
            Preview.Items[High(Preview.Items)].Kind := pkFolderRemove;
            Preview.Items[High(Preview.Items)].Folder := NoTrailingSlash(FInfo.Removed[I]);
            Preview.Items[High(Preview.Items)].Rel := '';
            Preview.Items[High(Preview.Items)].Size := -1;
          end;
        GoAhead := False;
        FOnPreview(Preview, GoAhead);
        if not GoAhead then
        begin
          Log(DriveTag + ': cancelled at the preview - nothing changed on the drive');
          Exit(crStopped);
        end;
        if Alarming <> '' then Log(DriveTag + ': safety check - large change confirmed by user in the preview');
      end
      else if (Alarming <> '') and not AssumeYes then
      begin
        GoAhead := False;
        if Assigned(FOnConfirm) then FOnConfirm(Alarming, GoAhead);
        if not GoAhead then
        begin
          Log(DriveTag + ': stopped at the safety check - nothing changed on the drive');
          Exit(crStopped);
        end;
        Log(DriveTag + ': safety check - large change confirmed by user');
      end;

      MoveRemovedFolders(Stamp);
      FailedCount := 0;
      FProgress.BytesTotal := TotalBytes;
      for I := 0 to High(Plans) do Inc(FProgress.FilesTotal, Plans[I].NewFiles + Plans[I].Changed);
      FCopyStarted := Now;
      for I := 0 to High(Srcs) do
      begin
        if FCancelled then Break;
        FProgress.Folder := Srcs[I].Name;
        FProgress.Status := 'Copying ' + Srcs[I].Name + '  (folder ' + IntToStr(I + 1) + ' of ' +
          IntToStr(Length(Srcs)) + ')';
        Dest := FDrive + MirrorFolder(Srcs[I]);
        DoMoves(Srcs[I], Plans[I]);
        SaveVersions(Plans[I], MirrorFolder(Srcs[I]), Dest, Stamp, Moved, VerFailed);
        if (Moved > 0) or (VerFailed > 0) then
        begin
          Status := '';
          if VerFailed > 0 then Status := ' (' + IntToStr(VerFailed) + ' could not be moved)';
          Log('  ' + Srcs[I].Name + ': kept ' + IntToStr(Moved) + ' old version(s) in _versions\' + Stamp + Status);
        end;
        Rc := CopyWithProgress(Srcs[I].Name, Srcs[I].Path, Dest, Plans[I]);
        if not FCancelled and (Rc < 8) then RecordChecksums(MirrorFolder(Srcs[I]), Srcs[I].Path, Dest, Plans[I]);
        if FCancelled then
          Log('  ' + Srcs[I].Name + ': cancelled - the copy on the drive is incomplete')
        else if Rc >= 8 then
        begin
          Inc(FailedCount);
          Log('  ' + Srcs[I].Name + ': FAILED (robocopy code ' + IntToStr(Rc) + ') - see ' +
            Copy(FDrive, 1, 2) + '\G-mirror-robocopy.log');
        end
        else
          Log('  ' + Srcs[I].Name + ': ok (' + FormatSize(Plans[I].Bytes) + ' copied, robocopy code ' +
            IntToStr(Rc) + ')');
      end;

      if FCancelled then
      begin
        Log(DriveTag + ': cancelled by user - run it again to finish the copy');
        Exit(crCancelled);
      end;

      // the live rate counts robocopy's own overhead too, which swamps a small copy - so the run ends
      // showing its real average: what robocopy copied over the whole copying time
      Secs := (Now - FCopyStarted) * 86400;
      if Secs > 0 then FProgress.Speed := Round(FProgress.FilesDoneBytes / Secs);
      Report;

      Pruned := RemoveOldVersions;
      if Pruned > 0 then Log('  pruned ' + IntToStr(Pruned) + ' old version set(s)');
      if (FailedCount > 0) or (Length(Missing) > 0) then Status := 'INCOMPLETE' else Status := 'complete';
      Names := '';
      for I := 0 to High(Srcs) do
      begin
        if Names <> '' then Names := Names + ', ';
        Names := Names + Srcs[I].Path + ' -> ' + MirrorFolder(Srcs[I]);
      end;
      MissingNames := '';
      for I := 0 to High(Missing) do
      begin
        if MissingNames <> '' then MissingNames := MissingNames + ', ';
        MissingNames := MissingNames + Missing[I];
      end;
      Status := 'Folders: ' + Names + '. Status: ' + Status;
      if MissingNames <> '' then Status := 'Not found, so not copied: ' + MissingNames + '. ' + Status;
      WriteTextFile(FDrive + 'LAST-COPY.txt', 'Offline copy made ' + FormatDateTime('yyyy-mm-dd hh:nn', Now) +
        ' from ' + ComputerName + '. ' + Status + #13#10);

      if FailedCount > 0 then SaveHistory(crFailed)
      else if MissingNames <> '' then SaveHistory(crIncomplete)
      else SaveHistory(crOk);

      // These sticks show up as fixed disks, so Windows offers no "Safely Remove" and may still hold
      // writes in memory. Flush them to the drive; after that it is safe to unplug.
      Flushed := False;
      if Length(FDrive) = 3 then
      begin
        H := CreateFileW(PWideChar('\\.\' + Copy(FDrive, 1, 2)), GENERIC_READ or GENERIC_WRITE,
          FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
        if H <> INVALID_HANDLE_VALUE then
        begin
          Flushed := FlushFileBuffers(H);
          CloseHandle(H);
        end;
      end;

      if FailedCount > 0 then
      begin
        Log(DriveTag + ': finished with ' + IntToStr(FailedCount) + ' failure(s)');
        Exit(crFailed);
      end;
      if MissingNames <> '' then Status := 'finished, but not found so not copied: ' + MissingNames
      else Status := 'complete';
      if Flushed then Log(DriveTag + ': ' + Status + ' - everything written to the drive, safe to unplug')
      else Log(DriveTag + ': ' + Status + ' - could not flush the drive''s write cache; wait 30 seconds before unplugging');
      if MissingNames <> '' then Result := crIncomplete else Result := crOk;
    except
      on E: Exception do
      begin
        Log('FAILED: ' + E.Message);
        Result := crFailed;
      end;
    end;
  finally
    for I := 0 to High(Plans) do Plans[I].Free;
  end;
end;

{ ---------- TOfflineCopyThread ---------- }

constructor TOfflineCopyThread.Create(const Settings: TBackupSettings; const Drive: TOfflineDrive;
  VerifyOnly: Boolean);
begin
  Verifying := VerifyOnly;
  FCopy := TOfflineCopy.Create(Settings, Drive.Root, Drive.VolLabel);
  FCopy.OnLog := CopyLog;
  FCopy.OnProgress := CopyProgress;
  FCopy.OnConfirm := CopyConfirm;
  FCopy.OnMissing := CopyMissing;
  FCopy.OnPreview := CopyPreview;
  DriveLabel := Drive.VolLabel;
  CopyResult := crFailed;
  inherited Create(True);
end;

destructor TOfflineCopyThread.Destroy;
begin
  inherited;
  FCopy.Free;
end;

procedure TOfflineCopyThread.Cancel;
begin
  FCopy.Cancel;
end;

procedure TOfflineCopyThread.Execute;
begin
  if Checking then CopyResult := FCopy.CheckMd5(CheckFile)
  else if Verifying then CopyResult := FCopy.Verify
  else CopyResult := FCopy.Run;
end;

constructor TOfflineCopyThread.CreateCheck(const Settings: TBackupSettings; const Md5File: string);
var
  D: TOfflineDrive;
begin
  D := Default(TOfflineDrive);
  D.Root := ParentDir(Md5File);
  D.VolLabel := ExtractFileName(Md5File);
  Create(Settings, D, False);
  Checking := True;
  CheckFile := Md5File;
end;

procedure TOfflineCopyThread.CopyLog(const Msg: string);
begin
  FMsg := Msg;
  Synchronize(SyncLog);
end;

procedure TOfflineCopyThread.CopyProgress(const P: TCopyProgress);
begin
  FProgress := P;
  Synchronize(SyncProgress);
end;

procedure TOfflineCopyThread.CopyConfirm(const Folders: string; var GoAhead: Boolean);
begin
  FMsg := Folders;
  FGoAhead := False;
  Synchronize(SyncConfirm);
  GoAhead := FGoAhead;
end;

procedure TOfflineCopyThread.CopyPreview(const P: TCopyPreview; var GoAhead: Boolean);
begin
  FPreview := P;
  FGoAhead := False;
  Synchronize(SyncPreview);
  GoAhead := FGoAhead;
end;

procedure TOfflineCopyThread.SyncPreview;
begin
  // a form without a preview still gets the safety-check question
  if Assigned(FOnPreview) then FOnPreview(FPreview, FGoAhead)
  else if FPreview.Warning <> '' then
  begin
    if Assigned(FOnConfirm) then FOnConfirm(FPreview.Warning, FGoAhead);
  end
  else FGoAhead := True;
end;

procedure TOfflineCopyThread.CopyMissing(const Path: string; var Skip: Boolean);
begin
  FMsg := Path;
  FGoAhead := False;
  Synchronize(SyncMissing);
  Skip := FGoAhead;
end;

procedure TOfflineCopyThread.SyncLog;
begin
  if Assigned(FOnLog) then FOnLog(FMsg);
end;

procedure TOfflineCopyThread.SyncProgress;
begin
  if Assigned(FOnProgress) then FOnProgress(FProgress);
end;

procedure TOfflineCopyThread.SyncConfirm;
begin
  if Assigned(FOnConfirm) then FOnConfirm(FMsg, FGoAhead);
end;

procedure TOfflineCopyThread.SyncMissing;
begin
  if Assigned(FOnMissing) then FOnMissing(FMsg, FGoAhead);
end;

initialization
  MakeCrcTable;

end.
