program EngineTest;

{ Exercises OfflineEngine against throw-away folders: a folder stands in for the OFFLINE drive, and the log
  goes to the work folder too, so no real drive or log is touched.
  Usage: EngineTest <empty work folder>
  Builds with both Delphi (dcc64) and Free Pascal - see run-tests.cmd. }

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}

uses
  Windows, SysUtils, Classes, OfflineEngine;

type
  THandlers = class
    Answer: Boolean;
    Asked: string;
    Last: TCopyProgress;      // the last progress report of a run
    SkipMissing: Boolean;
    MissingAsked: string;
    procedure Log(const Msg: string);
    procedure Progress(const P: TCopyProgress);
    procedure Confirm(const Folders: string; var GoAhead: Boolean);
    procedure Missing(const Path: string; var Skip: Boolean);
  public
    PreviewAnswer: Boolean;
    Previews: Integer;            // how many times the preview was shown
    LastPreview: TCopyPreview;
    procedure Preview(const P: TCopyPreview; var GoAhead: Boolean);
  end;

var
  Work, Drive, Uni: string;
  Mirror: string;             // <Drive>\<letter of the work folder>-mirror\
  Settings: TBackupSettings;
  H: THandlers;
  Failures: Integer;

procedure THandlers.Log(const Msg: string);
begin
  WriteLn('  log: ', Msg);
end;

procedure THandlers.Progress(const P: TCopyProgress);
begin
  Last := P;
end;

procedure ShowLast;
begin
  WriteLn('  ', ProgressEtaLine(H.Last));
  WriteLn('  ', ProgressCountsLine(H.Last));
  WriteLn('  ', ProgressRateLine(H.Last));
end;

procedure THandlers.Confirm(const Folders: string; var GoAhead: Boolean);
begin
  Asked := Folders;
  GoAhead := Answer;
end;

procedure THandlers.Preview(const P: TCopyPreview; var GoAhead: Boolean);
begin
  Inc(Previews);
  LastPreview := P;
  GoAhead := PreviewAnswer;
end;

procedure THandlers.Missing(const Path: string; var Skip: Boolean);
begin
  MissingAsked := Path;
  Skip := SkipMissing;
end;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then WriteLn('PASS  ', What)
  else
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure WriteFile(const Path, Text: string);
var
  L: TStringList;
begin
  ForceDirectories(ExtractFileDir(Path));
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(Path);
  finally
    L.Free;
  end;
end;

{ Writes a file through the wide API, so names outside the ANSI code page work under both compilers }
procedure WriteFileW(const Path: string; const Text: AnsiString);
var
  H: THandle;
  N: DWORD;
begin
  H := CreateFileW(PWideChar(Path), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  Windows.WriteFile(H, PAnsiChar(Text)^, Length(Text), N, nil);
  CloseHandle(H);
end;

function FileSizeW(const Path: string): Int64;
var
  FD: TWin32FindDataW;
  H: THandle;
begin
  Result := -1;
  H := FindFirstFileW(PWideChar(Path), FD);
  if H = INVALID_HANDLE_VALUE then Exit;
  Result := FD.nFileSizeLow;
  Windows.FindClose(H);
end;

function ReadFile(const Path: string): string;
var
  L: TStringList;
begin
  Result := '';
  if not FileExists(Path) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(Path);
    Result := Trim(L.Text);
  finally
    L.Free;
  end;
end;

function RunCopyOn(const S: TBackupSettings; const D: string; AssumeYes: Boolean): TCopyResult;
var
  C: TOfflineCopy;
begin
  C := TOfflineCopy.Create(S, D, 'OFFLINE-T');
  try
    C.AllowFolderTarget := True;
    C.AssumeYes := AssumeYes;
    C.OnLog := H.Log;
    C.OnProgress := H.Progress;
    C.OnConfirm := H.Confirm;
    C.OnMissing := H.Missing;
    Result := C.Run;
  finally
    C.Free;
  end;
end;

function RunCopy(AssumeYes: Boolean): TCopyResult;
begin
  Result := RunCopyOn(Settings, Drive, AssumeYes);
end;

function VersionsFileOn(const D, Rel: string): Boolean;
var
  SR: TSearchRec;
begin
  // _versions\<stamp>\<letter>-mirror\<rel> - the same path as on the drive
  Result := False;
  if FindFirst(D + '_versions\*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and
         (FileSizeW(D + '_versions\' + SR.Name + '\' + SourceLetter(Work) + '-mirror\' + Rel) >= 0) then
        Result := True;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function VersionsFile(const Rel: string): Boolean;
begin
  Result := VersionsFileOn(Drive, Rel);
end;

procedure TestRealDriveGuard;
var
  C: TOfflineCopy;
  R: TCopyResult;
begin
  // a folder target without AllowFolderTarget must be refused before anything happens
  C := TOfflineCopy.Create(Settings, Drive, 'OFFLINE-T');
  try
    R := C.Run;
  finally
    C.Free;
  end;
  Check(R = crFailed, 'refuses a target that is not an OFFLINE-x drive');
  Check(not DirectoryExists(Mirror), '... and writes nothing to it');
end;

procedure TestDriveMap;
var
  Info, Back: TDriveInfo;
  Run: TDriveRun;
  I: Integer;
begin
  WriteLn('--- drive map');
  Check(not ReadDriveInfo(Drive, Info), 'a drive without a map is new');
  Check(RunCopy(False) = crSkipped, 'a new drive is not copied to');
  Check(not DirectoryExists(Mirror) and not FileExists(Drive + DriveMapName), '... and nothing is written to it');

  Info := NewDriveInfo('OFFLINE-T', 'test drive | kept in the drawer'#13#10'second line');
  Check(Length(Info.Id) = 36, 'set-up gives the drive an id (' + Info.Id + ')');
  Check(WriteDriveInfo(Drive, Info), 'drive map written');
  Check(ReadDriveInfo(Drive, Back) and (Back.Id = Info.Id) and (Back.VolLabel = 'OFFLINE-T') and
    (Back.Created = Info.Created), 'drive map read back');
  Check(Back.Description = 'test drive   kept in the drawer  second line', 'description kept on one line (' +
    Back.Description + ')');
  Check(FileExists(ExtractFilePath(SettingsFileName) + 'drives\' + Info.Id + '.ini'), 'the PC keeps a copy of the map');
  Check(NewDriveInfo('OFFLINE-T', '').Id <> Info.Id, 'every drive gets its own id');

  // history: newest kept, at most MaxDriveRuns, an empty folder list survives
  for I := 1 to MaxDriveRuns + 10 do
  begin
    Run.When := 'run ' + IntToStr(I);
    Run.PC := 'PC';
    Run.Result := 'ok';
    Run.Bytes := I;
    Run.Folders := '';
    AddDriveRun(Back, Run);
  end;
  Check((Length(Back.Runs) = MaxDriveRuns) and (Back.Runs[High(Back.Runs)].When = 'run ' + IntToStr(MaxDriveRuns + 10)),
    'history keeps the newest ' + IntToStr(MaxDriveRuns) + ' runs');
  WriteDriveInfo(Work, Back);
  ReadDriveInfo(Work, Back);
  Check((Length(Back.Runs) = MaxDriveRuns) and (Back.Runs[0].Bytes = 11) and (Back.Runs[0].Folders = ''),
    'history read back (' + IntToStr(Length(Back.Runs)) + ' runs)');
end;

{ Sets up a fake drive folder the way the Drives window would: a drive map with S's folders as its list }
procedure SetUpDrive(const D: string; const S: TBackupSettings);
var
  Info: TDriveInfo;
begin
  ForceDirectories(D);
  Info := NewDriveInfo('OFFLINE-T', 'test');
  Info.HasList := True;
  Info.Sources := Copy(S.Sources);
  WriteDriveInfo(D, Info);
end;

function LastRun(const D: string): TDriveRun;
var
  Info: TDriveInfo;
begin
  Result := Default(TDriveRun);
  if ReadDriveInfo(D, Info) and (Length(Info.Runs) > 0) then Result := Info.Runs[High(Info.Runs)];
end;

procedure AddSource(var S: TBackupSettings; const Path: string; Enabled: Boolean);
var
  N: Integer;
begin
  N := Length(S.Sources);
  SetLength(S.Sources, N + 1);
  S.Sources[N].Path := Path;
  S.Sources[N].Name := UniqueSourceName(S.Sources, N, Path, DefaultSourceName(Path));
  S.Sources[N].Enabled := Enabled;
end;

{ The checksum recorded on drive D for <letter>-mirror\<Folder>\<Rel>, as hex; '' if none }
function RecordedCrc(const D, Folder, Rel: string): string;
var
  F: THandle;
  U: RawByteString;
  Text, Line: string;
  Size, Got: DWORD;
  P: Integer;
begin
  // read through the wide API and decode UTF-8 here - TStringList is AnsiString under Free Pascal
  Result := '';
  F := CreateFileW(PWideChar(D + '_checksums\' + SourceLetter(Work) + '-mirror\' + Folder + '.crc'), GENERIC_READ,
    FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if F = INVALID_HANDLE_VALUE then Exit;
  Size := GetFileSize(F, nil);
  SetLength(U, Size);
  if Size > 0 then Windows.ReadFile(F, U[1], Size, Got, nil);
  CloseHandle(F);
  SetCodePage(U, CP_UTF8, False);
  {$IFDEF FPC}Text := UTF8Decode(U);{$ELSE}Text := UTF8ToString(U);{$ENDIF}
  Text := Text + #10;
  while Text <> '' do
  begin
    P := Pos(#10, Text);
    Line := Copy(Text, 1, P - 1);
    Delete(Text, 1, P);
    if (Line <> '') and (Line[Length(Line)] = #13) then SetLength(Line, Length(Line) - 1);
    if Copy(Line, Length(Line) - Length(Rel), MaxInt) = #9 + Rel then Result := Copy(Line, 1, 8);
  end;
end;

function CrcHex(const Path: string): string;
var
  C: Cardinal;
begin
  if FileCrc32(Path, C) then Result := IntToHex(C, 8) else Result := '?';
end;

function RunVerifyOn(const D: string): TCopyResult;
var
  C: TOfflineCopy;
begin
  C := TOfflineCopy.Create(Settings, D, 'OFFLINE-T');
  try
    C.AllowFolderTarget := True;
    C.OnLog := H.Log;
    C.OnProgress := H.Progress;
    Result := C.Verify;
  finally
    C.Free;
  end;
end;

{ Same size, same last-write time, different bytes - what a failing drive does to a file }
procedure SpoilFile(const Path: string);
var
  F: THandle;
  Created, Accessed, Written: TFileTime;
  B: AnsiChar;
  N: DWORD;
begin
  F := CreateFileW(PWideChar(Path), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if F = INVALID_HANDLE_VALUE then Exit;
  GetFileTime(F, @Created, @Accessed, @Written);
  B := 'X';
  Windows.WriteFile(F, B, 1, N, nil);
  SetFileTime(F, @Created, @Accessed, @Written);
  CloseHandle(F);
end;

{ A whole UTF-8 file as a string (wide API - see RecordedCrc) }
function ReadUtf8(const Path: string): string;
var
  F: THandle;
  U: RawByteString;
  Size, Got: DWORD;
begin
  Result := '';
  F := CreateFileW(PWideChar(Path), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if F = INVALID_HANDLE_VALUE then Exit;
  Size := GetFileSize(F, nil);
  SetLength(U, Size);
  if Size > 0 then Windows.ReadFile(F, U[1], Size, Got, nil);
  CloseHandle(F);
  SetCodePage(U, CP_UTF8, False);
  {$IFDEF FPC}Result := UTF8Decode(U);{$ELSE}Result := UTF8ToString(U);{$ENDIF}
end;

function RunCheckMd5(const Md5File: string; out Items: TCheckItems): TCopyResult;
var
  C: TOfflineCopy;
begin
  C := TOfflineCopy.Create(Settings, ExtractFilePath(Md5File), 'MD5');
  try
    C.OnLog := H.Log;
    C.OnProgress := H.Progress;
    Result := C.CheckMd5(Md5File);
    Items := C.CheckItems;
  finally
    C.Free;
  end;
end;

function CountStatus(const Items: TCheckItems; S: TCheckStatus): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Items) do
    if Items[I].Status = S then Inc(Result);
end;

procedure TestMd5;
var
  Big: RawByteString;
  Md5, Md5File, T: string;
  Items: TCheckItems;
  R: TCopyResult;
begin
  WriteLn('--- MD5');
  Check(StringMd5('') = 'd41d8cd98f00b204e9800998ecf8427e', 'MD5 of nothing');
  Check(StringMd5('abc') = '900150983cd24fb0d6963f7d28e17f72', 'MD5 of "abc"');
  Check(StringMd5('The quick brown fox jumps over the lazy dog') = '9e107d9d372bb6826bd81d3542a419d6', 'MD5 of the fox');
  SetLength(Big, 1000000);
  FillChar(Big[1], Length(Big), Ord('a'));
  Check(StringMd5(Big) = '7707d6ae4e027c70eea2a935c2296f21', 'MD5 of a million a''s (' + StringMd5(Big) + ')');

  // each drive folder gets <letter>-mirror\<name>.md5 next to it, in the "md5 *path" format
  Md5File := Mirror + 'One.md5';
  FileMd5(Work + 'src\One\a.txt', Md5);
  T := ReadUtf8(Md5File);
  Check(Pos(Md5 + ' *One\a.txt', T) > 0, 'One.md5 lists One\a.txt with its MD5');
  Check(Pos('; Checksums generated by Offline Backup', T) > 0, '... with an ExactFile-style header');
  R := RunCheckMd5(Md5File, Items);
  Check((R = crOk) and (Length(Items) > 0) and (CountStatus(Items, csOk) = Length(Items)),
    'checking One.md5: all ' + IntToStr(Length(Items)) + ' files match');
  Check(Pos(' *Two\' + Uni, ReadUtf8(Mirror + 'Two.md5')) > 0, 'Two.md5 lists the non-ANSI file');

  // a list from before MD5s were kept: Verify fills them in
  T := ReadUtf8(Drive + '_checksums\' + SourceLetter(Work) + '-mirror\One.crc');
  WriteFileW(Drive + '_checksums\' + SourceLetter(Work) + '-mirror\One.crc',
    AnsiString(StringReplace(StringReplace(T, #9 + Md5 + #9, #9, [rfReplaceAll]), #9'1', #9'1', [])));
  DeleteFile(Md5File);
  R := RunVerifyOn(Drive);
  Check((R = crOk) and (Pos(Md5 + ' *One\a.txt', ReadUtf8(Md5File)) > 0), 'Verify fills in a missing MD5 and the .md5');

  // any .md5 file: one ok, one bad, one missing, one in md5sum's text-mode format
  FileMd5(Work + 'src\Many\f1.txt', Md5);
  WriteFileW(Work + 'check.md5', AnsiString('; made by hand' + #13#10 +
    Md5 + ' *src\Many\f1.txt' + #13#10 +
    '00000000000000000000000000000000 *src\Many\f2.txt' + #13#10 +
    Md5 + ' *src\nothere.txt' + #13#10 +
    Md5 + '  src\Many\f1.txt' + #13#10 +
    'not a checksum line' + #13#10));
  R := RunCheckMd5(Work + 'check.md5', Items);
  Check((R = crFailed) and (Length(Items) = 4), 'hand-made .md5: 4 lines read (' + IntToStr(Length(Items)) + ')');
  Check((CountStatus(Items, csOk) = 2) and (CountStatus(Items, csBad) = 1) and (CountStatus(Items, csMissing) = 1),
    '... 2 ok, 1 bad, 1 missing');
  Check((Items[1].Status = csBad) and (Items[1].Path = 'src\Many\f2.txt') and (Items[2].Size = -1),
    '... and the right ones');
  Check(H.Last.Checking and (H.Last.Errors = 1) and (H.Last.Skipped = 1), 'progress counts bad and missing');
end;

procedure TestChecksums;
var
  R: TCopyResult;
begin
  WriteLn('--- checksums');
  Check(IntToHex(StringCrc32('123456789'), 8) = 'CBF43926', 'CRC32 of "123456789" is CBF43926 (' +
    IntToHex(StringCrc32('123456789'), 8) + ')');
  Check(StringCrc32('') = 0, 'CRC32 of nothing is 0');
  Check((RecordedCrc(Drive, 'One', 'a.txt') <> '') and (RecordedCrc(Drive, 'One', 'a.txt') = CrcHex(Work + 'src\One\a.txt')),
    'copy recorded the checksum of a copied file (' + RecordedCrc(Drive, 'One', 'a.txt') + ')');
  Check(RecordedCrc(Drive, 'Two', Uni) = CrcHex(Work + 'src\Two\' + Uni), '... a non-ANSI one too');
  Check(RecordedCrc(Drive, 'One', 'sub\b.txt') = '', 'a file deleted from the source left the list');

  WriteLn('--- verify drive');
  R := RunVerifyOn(Drive);
  ShowLast;
  Check(R = crOk, 'verify ok (' + CopyResultText(R) + ')');
  Check(H.Last.Verifying and (H.Last.Errors = 0) and (H.Last.FilesDone = H.Last.FilesTotal) and (H.Last.FilesTotal > 100),
    'every file read, none bad (' + IntToStr(H.Last.FilesDone) + ' of ' + IntToStr(H.Last.FilesTotal) + ')');
  Check(LastRun(Drive).Result = 'verified ok', 'verify recorded in the drive''s history');

  SpoilFile(Mirror + 'Many\f5.txt');
  R := RunVerifyOn(Drive);
  Check((R = crFailed) and (H.Last.Errors = 1), 'a spoilt file is found (' + CopyResultText(R) + ', ' +
    IntToStr(H.Last.Errors) + ' bad)');
  Check(LastRun(Drive).Result = 'verify: 1 bad', '... and the history says so');
  R := RunCopy(True);
  Check(ReadFile(Mirror + 'Many\f5.txt') = 'version two', 'the next copy puts the good file back');
  R := RunVerifyOn(Drive);
  Check((R = crOk) and (H.Last.Errors = 0) and (H.Last.Skipped = 0), 'verify ok again, with a fresh checksum for it');

  TestMd5;

  DeleteFile(Drive + '_checksums\' + SourceLetter(Work) + '-mirror\Many.crc');
  R := RunVerifyOn(Drive);
  Check((R = crOk) and (H.Last.Skipped = 120), 'files without a checksum get one (' + IntToStr(H.Last.Skipped) + ')');
  R := RunVerifyOn(Drive);
  Check((R = crOk) and (H.Last.Skipped = 0), '... and are checked the next time');
end;

function RunWithPreview(const S: TBackupSettings; const D: string): TCopyResult;
var
  C: TOfflineCopy;
begin
  C := TOfflineCopy.Create(S, D, 'OFFLINE-T');
  try
    C.AllowFolderTarget := True;
    C.OnLog := H.Log;
    C.OnProgress := H.Progress;
    C.OnConfirm := H.Confirm;
    C.OnMissing := H.Missing;
    C.OnPreview := H.Preview;
    Result := C.Run;
  finally
    C.Free;
  end;
end;

{ How many preview items of this kind, and is Rel among them }
function PreviewCount(K: TPreviewKind): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(H.LastPreview.Items) do
    if H.LastPreview.Items[I].Kind = K then Inc(Result);
end;

function PreviewHas(K: TPreviewKind; const Rel: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(H.LastPreview.Items) do
    if (H.LastPreview.Items[I].Kind = K) and (H.LastPreview.Items[I].Rel = Rel) then Result := True;
end;

procedure TestPreview;
var
  S: TBackupSettings;
  D4, M4: string;
  R: TCopyResult;
  N: Integer;
begin
  WriteLn('--- preview');
  D4 := Work + 'FAKEDRIVE4\';
  M4 := D4 + SourceLetter(Work) + '-mirror\Music\';
  WriteFile(Work + 'prev\Music\a.mp3', 'a');
  WriteFile(Work + 'prev\Music\b.mp3', 'b');
  WriteFile(Work + 'prev\Music\sub\c.mp3', 'c');
  S := Settings;
  S.Sources := nil;
  S.Exclude := nil;
  S.PreviewAlways := True;
  AddSource(S, Work + 'prev\Music', True);
  SetUpDrive(D4, S);

  H.PreviewAnswer := False;
  H.Previews := 0;
  R := RunWithPreview(S, D4);
  Check(R = crStopped, 'Cancel in the preview stops the copy (' + CopyResultText(R) + ')');
  Check(not DirectoryExists(M4), '... with nothing written to the drive');
  Check((H.Previews = 1) and (PreviewCount(pkAdd) = 3) and PreviewHas(pkAdd, 'sub\c.mp3') and
    (PreviewCount(pkDirAdd) = 1) and PreviewHas(pkDirAdd, 'sub'), 'preview lists 3 files and 1 folder to add');
  N := 0;
  while (N <= High(H.LastPreview.Items)) and (H.LastPreview.Items[N].Rel <> 'a.mp3') do Inc(N);
  Check((N <= High(H.LastPreview.Items)) and (H.LastPreview.Items[N].Folder = 'Music') and
    (H.LastPreview.Items[N].Size = FileSizeW(Work + 'prev\Music\a.mp3')) and (Pos('OFFLINE-T', H.LastPreview.Drive) = 1),
    '... with folder, size and drive');

  H.PreviewAnswer := True;
  R := RunWithPreview(S, D4);
  Check((R = crOk) and FileExists(M4 + 'sub\c.mp3'), 'Copy in the preview goes ahead (' + CopyResultText(R) + ')');

  // only "show when something would be deleted": a new file goes ahead without a preview
  S.PreviewAlways := False;
  WriteFile(Work + 'prev\Music\d.mp3', 'd');
  N := H.Previews;
  R := RunWithPreview(S, D4);
  Check((R = crOk) and (H.Previews = N) and FileExists(M4 + 'd.mp3'), 'new files alone: no preview when not "always"');

  // ... but a moved file (add + delete) does show it
  WriteFile(Work + 'prev\Music\a.mp3', 'a, longer now');
  ForceDirectories(Work + 'prev\Music\moved');
  RenameFile(Work + 'prev\Music\b.mp3', Work + 'prev\Music\moved\b.mp3');
  DeleteFile(Work + 'prev\Music\sub\c.mp3');
  RemoveDir(Work + 'prev\Music\sub');
  R := RunWithPreview(S, D4);
  Check((R = crOk) and (H.Previews = N + 1), 'a deletion shows the preview (' + CopyResultText(R) + ')');
  Check(PreviewHas(pkMove, 'moved\b.mp3') and not PreviewHas(pkDelete, 'b.mp3') and PreviewHas(pkDirAdd, 'moved'),
    'a moved file shows as a move (more in TestMoves)');
  Check(PreviewHas(pkUpdate, 'a.mp3') and PreviewHas(pkDirDelete, 'sub') and PreviewHas(pkDelete, 'sub\c.mp3'),
    'updates, deleted folders and the files in them are listed');
  Check(FileExists(M4 + 'moved\b.mp3') and not FileExists(M4 + 'b.mp3'), '... and done after Copy');

  // "always": shown even with nothing to do
  S.PreviewAlways := True;
  R := RunWithPreview(S, D4);
  Check((R = crOk) and (H.Previews = N + 2) and (Length(H.LastPreview.Items) = 0), 'always: shown with nothing to do');
end;

{ Gives ToPath the last-write time of FromPath }
procedure SameTime(const FromPath, ToPath: string);
var
  F: THandle;
  Created, Accessed, Written: TFileTime;
begin
  F := CreateFileW(PWideChar(FromPath), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  GetFileTime(F, @Created, @Accessed, @Written);
  CloseHandle(F);
  F := CreateFileW(PWideChar(ToPath), FILE_WRITE_ATTRIBUTES, 0, nil, OPEN_EXISTING, 0, 0);
  SetFileTime(F, nil, nil, @Written);
  CloseHandle(F);
end;

function PreviewMove(const FromRel, ToRel: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(H.LastPreview.Items) do
    if (H.LastPreview.Items[I].Kind = pkMove) and (H.LastPreview.Items[I].From = FromRel) and
       (H.LastPreview.Items[I].Rel = ToRel) then Result := True;
end;

procedure TestMoves;
var
  S: TBackupSettings;
  D5, M5, Src: string;
  R: TCopyResult;
begin
  WriteLn('--- moved files');
  D5 := Work + 'FAKEDRIVE5\';
  M5 := D5 + SourceLetter(Work) + '-mirror\Music\';
  Src := Work + 'mv\Music\';
  WriteFile(Src + 'x.mp3', 'the x song');
  WriteFile(Src + 'y.mp3', 'the y song');
  WriteFile(Src + 'z.mp3', 'the z song');
  WriteFile(Src + 'album\t1.mp3', 'track one');
  WriteFile(Src + 'album\t2.mp3', 'track two');
  S := Settings;
  S.Sources := nil;
  S.Exclude := nil;
  S.PreviewAlways := True;
  AddSource(S, Work + 'mv\Music', True);
  SetUpDrive(D5, S);
  H.PreviewAnswer := True;
  R := RunWithPreview(S, D5);
  Check(R = crOk, 'first copy ok (' + CopyResultText(R) + ')');

  // one file moved into a new folder
  ForceDirectories(Src + 'sub');
  RenameFile(Src + 'x.mp3', Src + 'sub\x.mp3');
  R := RunWithPreview(S, D5);
  Check(PreviewMove('x.mp3', 'sub\x.mp3'), 'a moved file shows as a move');
  Check((PreviewCount(pkAdd) = 0) and (PreviewCount(pkDelete) = 0) and (PreviewCount(pkMove) = 1),
    '... not as add + delete');
  Check((R = crOk) and (H.Last.FilesTotal = 0), 'nothing copied (' + IntToStr(H.Last.FilesTotal) + ' files)');
  Check(FileExists(M5 + 'sub\x.mp3') and not FileExists(M5 + 'x.mp3'), 'moved on the drive');
  Check(not VersionsFileOn(D5, 'Music\x.mp3'), '... and not put in _versions');
  Check((RecordedCrc(D5, 'Music', 'sub\x.mp3') = CrcHex(Src + 'sub\x.mp3')) and (RecordedCrc(D5, 'Music', 'x.mp3') = ''),
    'its checksum moved with it');
  Check(Pos(' *Music\sub\x.mp3', ReadUtf8(D5 + SourceLetter(Work) + '-mirror\Music.md5')) > 0, '... in the .md5 too');

  // a whole folder renamed
  RenameFile(Src + 'album', Src + 'album 2');
  R := RunWithPreview(S, D5);
  Check(PreviewMove('album\t1.mp3', 'album 2\t1.mp3') and PreviewMove('album\t2.mp3', 'album 2\t2.mp3'),
    'a renamed folder: its files show as moves');
  Check(PreviewHas(pkDirAdd, 'album 2') and PreviewHas(pkDirDelete, 'album'), '... the folders as add / delete');
  Check((R = crOk) and FileExists(M5 + 'album 2\t2.mp3') and not DirectoryExists(M5 + 'album'), '... and done');

  // same size and time but different bytes: not a move
  WriteFile(Src + 'w.mp3', 'THE Z SONG');
  SameTime(M5 + 'z.mp3', Src + 'w.mp3');
  DeleteFile(Src + 'z.mp3');
  R := RunWithPreview(S, D5);
  Check((PreviewCount(pkMove) = 0) and PreviewHas(pkAdd, 'w.mp3') and PreviewHas(pkDelete, 'z.mp3'),
    'same size and time, other content: add + delete, not a move');
  Check((R = crOk) and (ReadFile(M5 + 'w.mp3') = 'THE Z SONG') and VersionsFileOn(D5, 'Music\z.mp3'),
    '... copied, and the old one kept in _versions');

  // moved and then changed (time differs): not a move either
  RenameFile(Src + 'y.mp3', Src + 'y2.mp3');
  WriteFile(Src + 'y2.mp3', 'the y song');
  R := RunWithPreview(S, D5);
  Check((PreviewCount(pkMove) = 0) and PreviewHas(pkAdd, 'y2.mp3'), 'moved and touched: add + delete');

  R := RunVerifyOn(D5);
  Check((R = crOk) and (H.Last.Errors = 0) and (H.Last.Skipped = 0), 'Verify afterwards: all match, none new');
end;

{ Gives drive D the folder list S.Sources, the way the Drives window would }
procedure UseFolders(const D: string; const S: TBackupSettings);
var
  Info: TDriveInfo;
begin
  ReadDriveInfo(D, Info);
  Info.HasList := True;
  Info.Sources := Copy(S.Sources);
  WriteDriveInfo(D, Info);
end;

{ The drive's own folder list. Uses the folders made by TestSeveralFolders. }
procedure TestDriveFolders;
var
  S: TBackupSettings;
  Info: TDriveInfo;
  D3, M3, Uni: string;
  R: TCopyResult;
begin
  WriteLn('--- a drive with its own folder list');
  D3 := Work + 'FAKEDRIVE3\';
  M3 := D3 + SourceLetter(Work) + '-mirror\';
  Uni := Work + 'multi\Fotos-' + WideChar($00FC);
  WriteFile(Uni + '\u.txt', 'u');
  // Settings has nothing for this drive: the drive's list alone decides
  S := Settings;
  S.Sources := nil;
  S.Exclude := nil;
  AddSource(S, Work + 'multi\docs\Documents', True);
  ForceDirectories(D3);
  Info := NewDriveInfo('OFFLINE-T', 'photos only');
  Info.HasList := True;
  SetLength(Info.Sources, 2);
  Info.Sources[0].Path := Work + 'multi\deep\down\MY PHOTOS';
  Info.Sources[0].Name := 'MY PHOTOS';
  Info.Sources[0].Enabled := True;
  Info.Sources[1].Path := Uni;
  Info.Sources[1].Name := 'Fotos-' + WideChar($00FC);
  Info.Sources[1].Enabled := True;
  WriteDriveInfo(D3, Info);
  ReadDriveInfo(D3, Info);
  Check(Info.HasList and (Length(Info.Sources) = 2) and (Info.Sources[1].Path = Uni) and Info.Sources[1].Enabled,
    'folder list (path, name, ticked) read back from the drive');
  R := RunCopyOn(S, D3, False);
  Check(R = crOk, 'copy ok (' + CopyResultText(R) + ')');
  Check(FileExists(M3 + 'MY PHOTOS\p1.jpg') and FileExists(M3 + 'Fotos-' + WideChar($00FC) + '\u.txt') and
    not DirectoryExists(M3 + 'Documents'), 'only the drive''s folders copied, not the ones in Settings');
  Check(LastRun(D3).Folders = 'MY PHOTOS, Fotos-' + WideChar($00FC), 'history lists them');

  WriteLn('--- unticked: not updated, stays on the drive');
  Info.Sources[0].Enabled := False;
  WriteDriveInfo(D3, Info);
  WriteFile(Work + 'multi\deep\down\MY PHOTOS\p3.jpg', 'p3');
  R := RunCopyOn(S, D3, False);
  Check(R = crOk, 'copy ok (' + CopyResultText(R) + ')');
  Check(FileExists(M3 + 'MY PHOTOS\p1.jpg') and not FileExists(M3 + 'MY PHOTOS\p3.jpg'), 'its copy stays as it was');

  WriteLn('--- removed from the list: moved to _versions at the next copy');
  ReadDriveInfo(D3, Info);
  Delete(Info.Sources, 0, 1);
  SetLength(Info.Removed, 2);
  Info.Removed[0] := SourceLetter(Work) + '-mirror\MY PHOTOS';
  Info.Removed[1] := '..\..\Windows';                 // must never be touched
  WriteDriveInfo(D3, Info);
  R := RunCopyOn(S, D3, False);
  Check(R = crOk, 'copy ok (' + CopyResultText(R) + ')');
  Check(not DirectoryExists(M3 + 'MY PHOTOS'), 'its copy is gone from the mirror');
  Check(not FileExists(D3 + '_checksums\' + SourceLetter(Work) + '-mirror\MY PHOTOS.crc'), '... and its checksums');
  Check(VersionsFileOn(D3, 'MY PHOTOS\p1.jpg'), '... and kept in _versions');
  Check(FileExists(M3 + 'Fotos-' + WideChar($00FC) + '\u.txt'), 'the other folder is untouched');
  ReadDriveInfo(D3, Info);
  Check(Length(Info.Removed) = 0, 'remove list cleared');

  WriteLn('--- a removed folder added back is kept');
  SetLength(Info.Removed, 1);
  Info.Removed[0] := MirrorFolder(Info.Sources[0]);
  WriteDriveInfo(D3, Info);
  R := RunCopyOn(S, D3, False);
  Check(FileExists(M3 + 'Fotos-' + WideChar($00FC) + '\u.txt'), 'still on the list, so it stays');
end;

procedure TestSourceNames;
var
  A: TBackupSourceArray;
  Src: TBackupSource;
begin
  WriteLn('--- source names');
  Check((SourceLetter('d:\MUSIC') = 'D') and (SourceLetter('\\server\share') = #0) and (SourceLetter('MUSIC') = #0),
    'drive letter of a source');
  Src.Path := 'D:\MUSIC';
  Src.Name := 'MUSIC';
  Check(MirrorFolder(Src) = 'D-mirror\MUSIC', 'D:\MUSIC lands in D-mirror\MUSIC (' + MirrorFolder(Src) + ')');
  Check(DefaultSourceName('C:\Users\someone\Documents\') = 'Documents', 'default name is the folder name');
  Check((DefaultSourceName('D:\') = 'D-drive') and (DefaultSourceName('D:') = 'D-drive'), 'default name of a whole drive');
  Check(NormalizeSourcePath(' D:/MY PHOTOS/ ') = 'D:\MY PHOTOS', 'path tidied (' + NormalizeSourcePath(' D:/MY PHOTOS/ ') + ')');
  Check(ValidSourceName('MY PHOTOS') and not ValidSourceName('a\b') and not ValidSourceName('') and
    not ValidSourceName(' x') and not ValidSourceName('x.') and not ValidSourceName('a:b'), 'folder name checks');
  SetLength(A, 2);
  A[0].Path := 'G:\Backups';
  A[0].Name := 'Backups';
  A[1].Path := 'D:\MUSIC';
  A[1].Name := 'MUSIC';
  Check(UniqueSourceName(A, -1, 'G:\Old\Backups', 'Backups') = 'Backups (2)', 'same name on the same drive gets (2)');
  Check(UniqueSourceName(A, -1, 'E:\MUSIC', 'MUSIC') = 'MUSIC', 'same name on another drive is fine (E-mirror)');
  Check(UniqueSourceName(A, 0, 'G:\Backups', 'Backups') = 'Backups', 'a source does not clash with itself');
  SetLength(A, 3);
  A[2].Path := 'G:\x\Backups';
  A[2].Name := 'Backups (2)';
  Check(UniqueSourceName(A, -1, 'G:\y\Backups', 'backups') = 'backups (3)', 'next free number, any case');
end;

procedure TestSettingsFile;
var
  S, T: TBackupSettings;
  F, Fotos: string;
  Same: Boolean;
  I: Integer;
begin
  WriteLn('--- settings file');
  Check(SameText(SettingsFileName, ExtractFilePath(ParamStr(0)) + 'OfflineBackup.ini') and not SettingsInAppData,
    'settings next to the exe when its folder is writable (' + SettingsFileName + ')');
  S := LoadSettings(Work + 'no-such.ini');
  Check((Length(S.Sources) = 0) and (Length(S.Exclude) = 0) and (S.BrakePercent = 20) and S.PreviewAlways,
    'no file gives the defaults: no folders, nothing excluded');
  Check(SameText(S.LogFile, ExtractFilePath(ParamStr(0)) + 'offline-copy.log'),
    '... and the log next to the settings (' + S.LogFile + ')');

  F := Work + 'settings\OfflineBackup.ini';
  ForceDirectories(Work + 'settings');
  Fotos := 'D:\Fotos-' + WideChar($00FC) + WideChar($65E5);
  S.Sources := nil;
  AddSource(S, 'C:\Users\someone\Documents', True);
  AddSource(S, 'D:\MY PHOTOS', False);
  AddSource(S, Fotos, True);
  AddSource(S, 'D:\Old\MY PHOTOS', True);
  SetLength(S.Exclude, 2);
  S.Exclude[0] := 'build';
  S.Exclude[1] := 'D:\MUSIC\tmp';
  S.BrakePercent := 33;
  S.BrakeMinFiles := 7;
  S.KeepVersionDays := 30;
  S.MaxDriveFullPct := 90;
  S.LogFile := Work + 'log-' + WideChar($00FC) + '.log';
  Check(S.PreviewAlways, 'preview before every copy is the default');
  S.PreviewAlways := False;
  Check(SaveSettings(F, S), 'settings saved');
  Check(not FileExists(F + '.tmp'), '... no temp file left');
  T := LoadSettings(F);
  Same := Length(T.Sources) = Length(S.Sources);
  if Same then
    for I := 0 to High(S.Sources) do
      Same := Same and (T.Sources[I].Path = S.Sources[I].Path) and (T.Sources[I].Name = S.Sources[I].Name) and
        (T.Sources[I].Enabled = S.Sources[I].Enabled);
  Check(Same, 'sources read back (path, name, ticked)');
  Check((T.Sources[1].Enabled = False) and (T.Sources[3].Name = 'MY PHOTOS (2)') and (T.Sources[2].Path = Fotos),
    '... unticked, numbered and non-ANSI ones too');
  Check((Length(T.Exclude) = 2) and (T.Exclude[0] = 'build') and (T.Exclude[1] = 'D:\MUSIC\tmp'), 'exclusions read back');
  Check((T.BrakePercent = 33) and (T.BrakeMinFiles = 7) and (T.KeepVersionDays = 30) and (T.MaxDriveFullPct = 90) and
    (T.LogFile = S.LogFile) and not T.PreviewAlways, 'numbers, log file and preview setting read back');

  S.Sources := nil;
  S.Exclude := nil;
  SaveSettings(F, S);
  T := LoadSettings(F);
  Check((Length(T.Sources) = 0) and (Length(T.Exclude) = 0), 'empty lists stay empty (not the defaults)');

  // hand-edited file: bad numbers, a network path, duplicate names, a bad name
  WriteFile(F, '[General]'#13#10'BrakePercent=500'#13#10'KeepVersionDays=abc'#13#10 +
    '[Sources]'#13#10'Count=4'#13#10 +
    '[Source1]'#13#10'Path=D:\MUSIC'#13#10 +
    '[Source2]'#13#10'Path=D:\Old\MUSIC\'#13#10'Name=MUSIC'#13#10 +
    '[Source3]'#13#10'Path=\\server\share'#13#10 +
    '[Source4]'#13#10'Path=E:\MUSIC'#13#10'Name=bad|name'#13#10'Enabled=0'#13#10);
  T := LoadSettings(F);
  Check((T.BrakePercent = 100) and (T.KeepVersionDays = 90), 'numbers out of range pulled back in');
  Check(Length(T.Sources) = 3, 'network path left out (' + IntToStr(Length(T.Sources)) + ' sources)');
  if Length(T.Sources) = 3 then
  begin
    Check((T.Sources[0].Name = 'MUSIC') and (T.Sources[1].Name = 'MUSIC (2)') and (T.Sources[1].Path = 'D:\Old\MUSIC'),
      'duplicate name on the same drive numbered (' + T.Sources[1].Name + ')');
    Check((T.Sources[2].Name = 'MUSIC') and not T.Sources[2].Enabled, 'bad name replaced, unticked kept');
  end;
  Check(Length(T.Exclude) = 0, 'no [Exclude] section keeps the default (nothing excluded)');
end;

procedure TestSeveralFolders;
var
  S: TBackupSettings;
  Info: TDriveInfo;
  D2, M2, L: string;
  R: TCopyResult;
begin
  WriteLn('--- several folders, unticked, same names, missing');
  D2 := Work + 'FAKEDRIVE2\';
  L := SourceLetter(Work);
  M2 := D2 + L + '-mirror\';
  WriteFile(Work + 'multi\docs\Documents\a.txt', 'a');
  WriteFile(Work + 'multi\docs\Documents\later\x.txt', 'excluded after the first copy');
  WriteFile(Work + 'multi\deep\down\MY PHOTOS\p1.jpg', 'p1');
  WriteFile(Work + 'multi\other\Documents\b.txt', 'b');
  WriteFile(Work + 'multi\off\c.txt', 'c');
  S := Settings;
  S.Sources := nil;
  S.Exclude := nil;
  AddSource(S, Work + 'multi\docs\Documents', True);
  AddSource(S, Work + 'multi\deep\down\MY PHOTOS', True);
  AddSource(S, Work + 'multi\other\Documents', True);
  AddSource(S, Work + 'multi\off', False);
  SetUpDrive(D2, S);
  R := RunCopyOn(S, D2, False);
  Check(R = crOk, 'copy from several folders ok (' + CopyResultText(R) + ')');
  Check(H.Last.FilesTotal = 4, '4 files in the ticked folders (' + IntToStr(H.Last.FilesTotal) + ')');
  Check((ReadFile(M2 + 'Documents\a.txt') = 'a') and (ReadFile(M2 + 'MY PHOTOS\p1.jpg') = 'p1'), 'each folder in its place');
  Check(ReadFile(M2 + 'Documents (2)\b.txt') = 'b', 'second Documents went to Documents (2)');
  Check(not DirectoryExists(M2 + 'off'), 'unticked folder not copied');
  Check(Pos(Work + 'multi\docs\Documents -> ' + L + '-mirror\Documents', ReadFile(D2 + 'LAST-COPY.txt')) > 0,
    'LAST-COPY.txt lists source -> folder');
  Check(ReadDriveInfo(D2, Info) and Info.HasList and (Length(Info.Sources) = 4) and not Info.Sources[3].Enabled,
    'the drive''s list is kept, unticked folder included');

  WriteLn('--- a folder excluded after it was copied');
  SetLength(S.Exclude, 1);
  S.Exclude[0] := 'later';
  R := RunCopyOn(S, D2, False);
  Check(R = crOk, 'copy ok (' + CopyResultText(R) + ')');
  Check(ReadFile(M2 + 'Documents\later\x.txt') <> '', 'its earlier copy is left on the drive');

  WriteLn('--- missing source folder');
  AddSource(S, Work + 'multi\nope', True);
  UseFolders(D2, S);
  WriteFile(Work + 'multi\deep\down\MY PHOTOS\p2.jpg', 'p2');
  H.SkipMissing := False;
  H.MissingAsked := '';
  R := RunCopyOn(S, D2, False);
  Check(R = crStopped, 'stops when told to (' + CopyResultText(R) + ')');
  Check(H.MissingAsked = Work + 'multi\nope', 'asked about the missing folder (' + H.MissingAsked + ')');
  Check(not FileExists(M2 + 'MY PHOTOS\p2.jpg'), '... and nothing was copied');
  H.SkipMissing := True;
  R := RunCopyOn(S, D2, False);
  Check(R = crIncomplete, 'skips it when told to (' + CopyResultText(R) + ')');
  Check(ReadFile(M2 + 'MY PHOTOS\p2.jpg') = 'p2', '... the other folders are copied');
  Check((Pos('INCOMPLETE', ReadFile(D2 + 'LAST-COPY.txt')) > 0) and (Pos('multi\nope', ReadFile(D2 + 'LAST-COPY.txt')) > 0),
    '... and LAST-COPY.txt says what is missing');
  Check(LastRun(D2).Result = 'incomplete', '... and the drive map says incomplete');

  WriteLn('--- settings the engine refuses');
  S.Sources := nil;
  ForceDirectories(D2 + 'inside');
  AddSource(S, D2 + 'inside', True);
  UseFolders(D2, S);
  Check(RunCopyOn(S, D2, False) = crFailed, 'a source on the OFFLINE drive itself is refused');
  S.Sources := nil;
  AddSource(S, Work + 'multi\off', False);
  UseFolders(D2, S);
  Check(RunCopyOn(S, D2, False) = crSkipped, 'nothing ticked - nothing done');
end;

var
  I: Integer;
  R: TCopyResult;
  Drives: TOfflineDriveArray;
begin
  Failures := 0;
  if ParamCount < 1 then
  begin
    WriteLn('usage: EngineTest <empty work folder>');
    Halt(2);
  end;
  Work := IncludeTrailingPathDelimiter(ParamStr(1));
  Drive := Work + 'FAKEDRIVE\';
  Mirror := Drive + SourceLetter(Work) + '-mirror\';
  ForceDirectories(Drive);
  H := THandlers.Create;

  Settings := DefaultSettings;
  SetLength(Settings.Sources, 3);
  Settings.Sources[0].Name := 'One';
  Settings.Sources[0].Path := Work + 'src\One';
  Settings.Sources[1].Name := 'Two';
  Settings.Sources[1].Path := Work + 'src\Two';
  Settings.Sources[2].Name := 'Many';
  Settings.Sources[2].Path := Work + 'src\Many';
  for I := 0 to 2 do Settings.Sources[I].Enabled := True;
  Settings.LogFile := Work + 'offline-copy.log';
  // one excluded folder by full path, one by name (that one matches anywhere)
  SetLength(Settings.Exclude, 2);
  Settings.Exclude[0] := Work + 'src\One\build';
  Settings.Exclude[1] := 'cache';

  WriteFile(Work + 'src\One\a.txt', 'alpha');
  WriteFile(Work + 'src\One\sub\b.txt', 'bravo');
  WriteFile(Work + 'src\One\gone\c.txt', 'charlie');
  WriteFile(Work + 'src\Two\d.txt', 'delta');
  WriteFile(Work + 'src\Two\skip.partial\x.txt', 'half-finished');
  WriteFile(Work + 'src\One\build\app.exe', 'rebuilt every time');
  WriteFile(Work + 'src\Two\deep\cache\c.tmp', 'cached');
  WriteFile(Work + 'src\Two\build\keep.txt', 'only One\build is excluded');
  for I := 1 to 120 do WriteFile(Work + 'src\Many\f' + IntToStr(I) + '.txt', 'v1');
  Uni := 'Uni-' + WideChar($00FC) + WideChar($65E5) + WideChar($672C) + '.txt';   // u-umlaut + two CJK characters
  WriteFileW(Work + 'src\Two\' + Uni, 'abc');

  WriteLn('--- drive detection (read only)');
  Drives := FindOfflineDrives;
  for I := 0 to High(Drives) do WriteLn('  found ', Drives[I].VolLabel, ' on ', Drives[I].Root);
  Check(IsOfflineLabel('OFFLINE-A') and not IsOfflineLabel('OFFLINE-AB') and not IsOfflineLabel('offline-a'),
    'OFFLINE-x label matching');

  WriteLn('--- guard');
  TestRealDriveGuard;

  TestDriveMap;
  // a map without a folder list (written by an older build) is not copied to either
  Check(RunCopy(False) = crSkipped, 'a drive with no folders chosen is not copied to');
  Check(not DirectoryExists(Mirror), '... and nothing is written to it');
  SetUpDrive(Drive, Settings);

  WriteLn('--- first copy');
  R := RunCopy(False);
  Check(R = crOk, 'first copy ok (' + CopyResultText(R) + ')');
  Check((LastRun(Drive).Result = 'ok') and (LastRun(Drive).Bytes = H.Last.FilesDoneBytes) and
    (LastRun(Drive).Folders = 'One, Two, Many'), 'run recorded in the drive map (' + DriveRunText(LastRun(Drive)) + ')');
  ShowLast;
  Check((H.Last.FilesTotal = 126) and (H.Last.FilesDone = 126), 'all 126 files counted as done (' +
    IntToStr(H.Last.FilesDone) + ' of ' + IntToStr(H.Last.FilesTotal) + ')');
  Check((H.Last.Errors = 0) and (H.Last.Skipped = 0), 'no errors or skipped files');
  Check((H.Last.Percent = 100) and (H.Last.BytesCopied = H.Last.BytesTotal), 'progress ends at 100%');
  // 513 bytes can't have gone at MB/s - the final rate must be the real average, not robocopy's overhead
  Check((H.Last.Speed >= 0) and (H.Last.Speed < 100 * 1024), 'final rate is the real average (' +
    FormatSpeed(H.Last.Speed) + ')');
  Check(ReadFile(Mirror + 'One\sub\b.txt') = 'bravo', 'nested file mirrored');
  Check(ReadFile(Mirror + 'Many\f120.txt') = 'v1', 'third folder mirrored');
  Check(not DirectoryExists(Mirror + 'Two\skip.partial'), '*.partial folders skipped');
  Check(FileSizeW(Mirror + 'Two\' + Uni) = 3, 'non-ANSI file name mirrored');
  Check(Pos('Status: complete', ReadFile(Drive + 'LAST-COPY.txt')) > 0, 'LAST-COPY.txt written');
  Check(FileExists(Drive + 'G-mirror-robocopy.log'), 'robocopy summary kept on the drive');
  Check(not DirectoryExists(Mirror + 'One\build'), 'excluded folder (full path) skipped');
  Check(not DirectoryExists(Mirror + 'Two\deep\cache'), 'excluded folder (name) skipped');
  Check(ReadFile(Mirror + 'Two\build\keep.txt') <> '', '... a same-named folder elsewhere is still copied');

  WriteLn('--- second copy: one changed, one deleted file, one deleted folder');
  WriteFile(Work + 'src\One\a.txt', 'alpha, second edition');
  DeleteFile(Work + 'src\One\sub\b.txt');
  DeleteFile(Work + 'src\One\gone\c.txt');
  RemoveDir(Work + 'src\One\gone');
  WriteFileW(Work + 'src\Two\' + Uni, 'abcdef');
  R := RunCopy(False);
  Check(R = crOk, 'second copy ok (' + CopyResultText(R) + ')');
  ShowLast;
  Check((H.Last.FilesTotal = 2) and (H.Last.FilesDone = 2), 'second copy counts only the 2 changed files (' +
    IntToStr(H.Last.FilesDone) + ' of ' + IntToStr(H.Last.FilesTotal) + ')');
  Check(ReadFile(Mirror + 'One\a.txt') = 'alpha, second edition', 'changed file updated');
  Check(not FileExists(Mirror + 'One\sub\b.txt'), 'deleted file removed from mirror');
  Check(not DirectoryExists(Mirror + 'One\gone'), 'deleted folder removed from mirror');
  Check(VersionsFile('One\a.txt'), 'old a.txt kept in _versions');
  Check(VersionsFile('One\sub\b.txt'), 'deleted b.txt kept in _versions');
  Check(VersionsFile('One\gone\c.txt'), 'deleted folder kept in _versions');
  Check(FileSizeW(Mirror + 'Two\' + Uni) = 6, 'changed non-ANSI file updated');
  Check(VersionsFile('Two\' + Uni), 'old non-ANSI file kept in _versions');

  WriteLn('--- brake: all 120 files in Many changed');
  for I := 1 to 120 do WriteFile(Work + 'src\Many\f' + IntToStr(I) + '.txt', 'version two');
  H.Answer := False;
  R := RunCopy(False);
  Check(R = crStopped, 'large change stops when the answer is no (' + CopyResultText(R) + ')');
  Check(H.Asked = 'Many', 'asked about the right folder (' + H.Asked + ')');
  Check(LastRun(Drive).Result = 'stopped', 'a stopped run is recorded too');
  Check(ReadFile(Mirror + 'Many\f1.txt') = 'v1', '... and the mirror is untouched');
  H.Answer := True;
  R := RunCopy(False);
  Check(R = crOk, 'goes ahead when the answer is yes (' + CopyResultText(R) + ')');
  Check(ReadFile(Mirror + 'Many\f1.txt') = 'version two', '... mirror updated');
  Check(VersionsFile('Many\f1.txt'), '... old versions kept');

  TestChecksums;
  TestPreview;
  TestMoves;
  TestSourceNames;
  TestSettingsFile;
  TestSeveralFolders;
  TestDriveFolders;

  WriteLn('--- formatting');
  Check(FormatSize(26581402) = '25.35 MB', 'FormatSize MB (' + FormatSize(26581402) + ')');
  Check(FormatSize(0) = '0', 'FormatSize zero');
  Check(FormatDuration(50) = '50 sec', 'FormatDuration seconds');
  Check(FormatDuration(200) = '3 min 20 sec', 'FormatDuration minutes');
  Check(FormatDuration(3900) = '1 hr 5 min', 'FormatDuration hours');
  Check(FormatSpeed(1321206) = '1.26 MB/s', 'FormatSpeed (' + FormatSpeed(1321206) + ')');

  WriteLn('--- log');
  Check(Pos('OFFLINE-T', ReadFile(Settings.LogFile)) > 0, 'log written to the configured file');

  H.Free;
  WriteLn;
  if Failures = 0 then WriteLn('ALL PASSED') else WriteLn(Failures, ' FAILED');
  Halt(Failures);
end.
