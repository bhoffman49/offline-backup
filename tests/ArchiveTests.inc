{ Tests for the archive (0.11): ARCHIVE\MMDDYY folders, one per day, the archive switched off per folder, and old
  _versions sets moved into the archives. Included by EngineTest.dpr (uses its Check, Work, H, the file helpers,
  RunWithPreview and VersionsFileOn). }

procedure TestNoArchive;
var
  S: TBackupSettings;
  Info: TDriveInfo;
  D4, M4, Src, Kept, Txt: string;
  R: TCopyResult;
  P: TCopyPreview;
begin
  WriteLn('--- the archive switched off for one folder');
  D4 := Work + 'FAKEDRIVE4\';
  M4 := D4 + SourceLetter(Work) + '-mirror\';
  Src := Work + 'nover\Scratch';
  Kept := Work + 'nover\Keep';
  WriteFile(Src + '\a.txt', 'a one');
  WriteFile(Src + '\b.txt', 'b one');
  WriteFile(Kept + '\c.txt', 'c one');
  WriteFile(Kept + '\d.txt', 'd one');
  S := Settings;
  S.Sources := nil;
  S.Exclude := nil;
  S.PreviewAlways := False;
  ForceDirectories(D4);
  Info := NewDriveInfo('OFFLINE-T', 'archive test');
  Info.HasList := True;
  SetLength(Info.Sources, 2);
  Info.Sources[0].Path := Src;
  Info.Sources[0].Name := 'Scratch';
  Info.Sources[0].Enabled := True;
  Info.Sources[0].NoArchive := True;
  Info.Sources[1].Path := Kept;
  Info.Sources[1].Name := 'Keep';
  Info.Sources[1].Enabled := True;
  WriteDriveInfo(D4, Info);
  Txt := ReadUtf8(D4 + DriveMapName);
  Check((Pos('|Scratch|0', Txt) > 0) and (Pos('|Keep|1', Txt) > 0), 'the drive map stores the switch per folder');
  ReadDriveInfo(D4, Info);
  Check(Info.Sources[0].NoArchive and not Info.Sources[1].NoArchive, '... and reads it back');

  H.Previews := 0;
  H.PreviewAnswer := True;
  R := RunWithPreview(S, D4);
  Check((R = crOk) and FileExists(M4 + 'Scratch\a.txt') and FileExists(M4 + 'Keep\c.txt'), 'first copy ok');
  Check(H.Previews = 0, 'nothing to replace or delete yet: no preview needed');

  // change and delete a file in each folder (a new size, so the change is seen within the same second)
  WriteFile(Src + '\a.txt', 'a, second edition');
  DeleteFile(Src + '\b.txt');
  WriteFile(Kept + '\c.txt', 'c, second edition');
  DeleteFile(Kept + '\d.txt');
  H.Previews := 0;
  R := RunWithPreview(S, D4);
  Check(R = crOk, 'second copy ok (' + CopyResultText(R) + ')');
  Check(H.Previews = 1, 'the preview is shown');
  Check(H.LastPreview.NoArchive = 'Scratch', '... naming the folder that is not archived (' +
    H.LastPreview.NoArchive + ')');
  Check(Pos('The archive is off for Scratch', PreviewWarningText(H.LastPreview)) > 0, '... in its red text');
  Check((ReadFile(M4 + 'Scratch\a.txt') = 'a, second edition') and not FileExists(M4 + 'Scratch\b.txt'),
    'switched off: the drive is updated');
  Check(not VersionsFileOn(D4, 'Scratch\a.txt') and not VersionsFileOn(D4, 'Scratch\b.txt'),
    '... and nothing of it is archived');
  Check(VersionsFileOn(D4, 'Keep\c.txt') and VersionsFileOn(D4, 'Keep\d.txt'), 'the other folder is still archived');
  Check(DirectoryExists(D4 + ArchiveFolderName(Now)), '... in today''s ' + ArchiveFolderName(Now));
  Check(Pos('Scratch: not archived', H.LogText) > 0, 'the log says so');

  // the preview's text on its own
  P := Default(TCopyPreview);
  Check(PreviewWarningText(P) = '', 'no warning, no red text');
  P.Warning := 'Docs';
  Check(Pos('old files are kept in the archive', PreviewWarningText(P)) > 0, 'safety check alone: archived');
  P.NoArchive := 'Docs';
  Check((Pos('kept in the archive', PreviewWarningText(P)) = 0) and
    (Pos('archive is off for Docs', PreviewWarningText(P)) > 0), 'safety check on a folder that is not archived');

  // a drive map written by 0.10 (no fourth field) archives every folder
  WriteFileW(D4 + DriveMapName, AnsiString('[Drive]'#13#10'Id=x'#13#10'[Folders]'#13#10'Count=1'#13#10 +
    'Folder1=1|' + Src + '|Scratch'#13#10));
  ReadDriveInfo(D4, Info);
  Check((Length(Info.Sources) = 1) and not Info.Sources[0].NoArchive, 'an older drive map archives every folder');
end;

procedure TestArchiveFolders;
var
  S: TBackupSettings;
  Info: TDriveInfo;
  D6, M6, Src, Arc, L, Today: string;
  R: TCopyResult;
  When: TDateTime;
begin
  WriteLn('--- archive folders: ARCHIVE\MMDDYY, one per day');
  Check(ArchiveFolderName(EncodeDate(2026, 11, 23)) = 'ARCHIVE\112326', 'the name is month, day, year');
  Check(IsArchiveName('112326', When) and (When = EncodeDate(2026, 11, 23)), '... and is read back');
  Check(IsArchiveName('010520', When) and (When = EncodeDate(2020, 1, 5)), '... another one');
  Check(not IsArchiveName('131326', When) and not IsArchiveName('1123', When) and
    not IsArchiveName('11232x', When) and not IsArchiveName('Archive_112326', When), 'other names are not archives');

  D6 := Work + 'FAKEDRIVE6\';
  L := SourceLetter(Work) + '-mirror';
  M6 := D6 + L + '\';
  Src := Work + 'arch\Docs';
  Today := ArchiveFolderName(Now);
  Arc := D6 + Today + '\' + L + '\Docs\';
  WriteFile(Src + '\x.txt', 'x1');
  S := Settings;
  S.Sources := nil;
  S.Exclude := nil;
  S.PreviewAlways := False;
  S.KeepVersionDays := 90;
  ForceDirectories(D6);
  Info := NewDriveInfo('OFFLINE-T', 'archive folders');
  Info.HasList := True;
  SetLength(Info.Sources, 1);
  Info.Sources[0].Path := Src;
  Info.Sources[0].Name := 'Docs';
  Info.Sources[0].Enabled := True;
  WriteDriveInfo(D6, Info);
  // what an older app left: two _versions sets of 20 Nov 2026 with the same file, one of 2 Jan 2026,
  // one far too old, and an archive far too old
  WriteFile(D6 + '_versions\2026-11-20_1000\' + L + '\Docs\old.txt', 'morning');
  WriteFile(D6 + '_versions\2026-11-20_1500\' + L + '\Docs\old.txt', 'afternoon');
  WriteFile(D6 + '_versions\2026-11-20_1500\' + L + '\Docs\later.txt', 'later');
  WriteFile(D6 + '_versions\2026-01-02_0900\' + L + '\Docs\jan.txt', 'january');
  WriteFile(D6 + '_versions\2019-05-05_0800\' + L + '\Docs\ancient.txt', 'ancient');
  WriteFile(D6 + 'ARCHIVE\030320\' + L + '\Docs\gone.txt', 'gone');
  // ... and what the 0.11 test builds left in the root: an Archive_ folder of 20 Nov (merged) and of 21 Nov
  WriteFile(D6 + 'Archive_112026\' + L + '\Docs\old.txt', 'test build');
  WriteFile(D6 + 'Archive_112026\' + L + '\Docs\tb.txt', 'test build only');
  WriteFile(D6 + 'Archive_112126\' + L + '\Docs\nov21.txt', 'nov 21');
  WriteFile(D6 + '_versions\notes.txt', 'not a set');
  R := RunWithPreview(S, D6);
  Check(R = crOk, 'first copy ok (' + CopyResultText(R) + ')');
  Check(ReadFile(D6 + 'ARCHIVE\112026\' + L + '\Docs\old.txt') = 'morning',
    'old _versions sets of a day go into its archive, and the day''s first copy wins');
  Check(ReadFile(D6 + 'ARCHIVE\112026\' + L + '\Docs\later.txt') = 'later', '... the rest of the later set too');
  Check((ReadFile(D6 + 'ARCHIVE\112026\' + L + '\Docs\tb.txt') = 'test build only') and
    (ReadFile(D6 + 'ARCHIVE\112126\' + L + '\Docs\nov21.txt') = 'nov 21') and
    not DirectoryExists(D6 + 'Archive_112026') and not DirectoryExists(D6 + 'Archive_112126'),
    'Archive_ folders in the root move into ARCHIVE too');
  Check(not DirectoryExists(D6 + '_versions\2026-11-20_1000') and not DirectoryExists(D6 + '_versions\2026-11-20_1500'),
    '... and those sets are gone from _versions');
  Check(not DirectoryExists(D6 + 'ARCHIVE\010226') and not DirectoryExists(D6 + 'ARCHIVE\050519') and
    not DirectoryExists(D6 + 'ARCHIVE\030320'), 'archives older than 90 days are removed');
  Check(FileExists(D6 + '_versions\notes.txt'), 'anything else in _versions is left alone');
  Check((Pos('old _versions set(s) into ARCHIVE', H.LogText) > 0) and
    (Pos('Archive_ folder(s) into ARCHIVE', H.LogText) > 0), 'the log says so');

  // same day: the archive keeps the first copy of the day
  WriteFile(Src + '\x.txt', 'x, two');
  R := RunWithPreview(S, D6);
  Check((R = crOk) and (ReadFile(Arc + 'x.txt') = 'x1'), 'a changed file goes into today''s archive');
  WriteFile(Src + '\x.txt', 'x, three - longer');
  R := RunWithPreview(S, D6);
  Check((R = crOk) and (ReadFile(M6 + 'Docs\x.txt') = 'x, three - longer'), 'changed again the same day: copied');
  Check(ReadFile(Arc + 'x.txt') = 'x1', '... and the archive still has the day''s first copy');
  WriteFile(Src + '\sub\y.txt', 'y1');
  R := RunWithPreview(S, D6);
  DeleteFile(Src + '\sub\y.txt');
  RemoveDir(Src + '\sub');
  R := RunWithPreview(S, D6);
  Check((R = crOk) and FileExists(Arc + 'sub\y.txt') and not DirectoryExists(M6 + 'Docs\sub'),
    'a deleted folder is archived too');
  WriteFile(Src + '\sub\y.txt', 'y, back again');
  R := RunWithPreview(S, D6);
  DeleteFile(Src + '\sub\y.txt');
  RemoveDir(Src + '\sub');
  R := RunWithPreview(S, D6);
  Check((R = crOk) and not DirectoryExists(M6 + 'Docs\sub') and (ReadFile(Arc + 'sub\y.txt') = 'y1'),
    'deleted again the same day: gone from the copy, the archive keeps the first');
end;
