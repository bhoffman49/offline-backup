unit MainForm;

{ Main window of the Lazarus/LCL edition. Lives in the tray; closing the window only hides it.
  The copy itself is in ..\common\OfflineEngine.pas, shared with the Delphi edition. }

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Menus,
  OfflineEngine, DriveWatcher, SettingsForm, DriveForm, PreviewForm, CheckForm;

type

  { TFormMain }

  TFormMain = class(TForm)
    LabelDrives: TLabel;
    ButtonStart: TButton;
    ButtonCancel: TButton;
    ButtonSettings: TButton;
    ButtonDrives: TButton;
    ButtonCheck: TButton;
    Md5Dialog: TOpenDialog;
    LabelStatus: TLabel;
    LabelEta: TLabel;
    LabelCounts: TLabel;
    LabelRate: TLabel;
    ProgressBar: TProgressBar;
    MemoLog: TMemo;
    TrayIcon: TTrayIcon;
    TrayMenu: TPopupMenu;
    MenuShow: TMenuItem;
    MenuStart: TMenuItem;
    MenuSettings: TMenuItem;
    MenuDrives: TMenuItem;
    MenuCheck: TMenuItem;
    MenuSep: TMenuItem;
    MenuExit: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonCancelClick(Sender: TObject);
    procedure ButtonSettingsClick(Sender: TObject);
    procedure ButtonDrivesClick(Sender: TObject);
    procedure ButtonCheckClick(Sender: TObject);
    procedure TrayIconClick(Sender: TObject);
    procedure MenuShowClick(Sender: TObject);
    procedure MenuExitClick(Sender: TObject);
  private
    FWatcher: TDriveWatcher;
    FSettings: TBackupSettings;
    FDrives: TOfflineDriveArray;      // OFFLINE-x drives plugged in now
    FQueue: TOfflineDriveArray;       // drives still to copy in this run
    FStarting: Boolean;               // FormCreate is running
    FLastProgress: TCopyProgress;     // the last progress report of the run in progress
    FRunSummary: string;              // one line per drive done in this run, shown when the run ends
    FRunProblem: Boolean;             // ... with a warning icon if any of them did not go well
    FRunAllStopped: Boolean;          // every drive stopped by the user (Cancel in the preview): no popup
    FThread: TOfflineCopyThread;
    FQuitting: Boolean;
    procedure DrivesChanged(Sender: TObject);
    procedure RefreshDrives(Announce: Boolean);
    procedure LogDriveState(const D: TOfflineDrive);
    procedure StartNext;
    procedure StartVerify(const Drive: TOfflineDrive);
    procedure StartThread(T: TOfflineCopyThread);
    procedure UpdateButtons;
    procedure ShowWindow;
    procedure AddLog(const Msg: string);
    procedure QueryEndSession(var Cancel: Boolean);
    // the engine's events use UnicodeString; LCL strings are UTF-8
    procedure CopyLog(const Msg: UnicodeString);
    procedure CopyProgress(const P: TCopyProgress);
    procedure ClearProgress;
    procedure AddRunLine(T: TOfflineCopyThread);
    procedure ShowRunSummary;
    procedure CopyConfirm(const Folders: UnicodeString; var GoAhead: Boolean);
    procedure CopyMissing(const Path: UnicodeString; var Skip: Boolean);
    procedure CopyPreview(const P: TCopyPreview; var GoAhead: Boolean);
    procedure CopyDone(Sender: TObject);
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FSettings := LoadSettings(SettingsFileName);
  TrayIcon.Icon.Assign(Application.Icon);
  TrayIcon.Hint := 'Offline Backup';
  TrayIcon.Visible := True;
  Application.OnQueryEndSession := QueryEndSession;
  FWatcher := TDriveWatcher.Create;
  FWatcher.OnChange := DrivesChanged;
  FStarting := True;
  RefreshDrives(True);
  FStarting := False;
  if SettingsInAppData then
    AddLog('the app''s own folder can''t be written to, so settings are kept in ' + SettingsFileName);
  if FileExists(SettingsFileName) then AddLog('settings: ' + SettingsFileName)
  else AddLog('settings: defaults (saved to ' + SettingsFileName + ' when changed)');
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  FWatcher.Free;
  TrayIcon.Visible := False;
end;

procedure TFormMain.QueryEndSession(var Cancel: Boolean);
begin
  // Windows is shutting down: let the window close instead of hiding
  FQuitting := True;
  if Assigned(FThread) then FThread.Cancel;
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not FQuitting then
  begin
    CanClose := False;
    Hide;                             // the X button only hides; Exit is on the tray menu
  end;
end;

procedure TFormMain.ShowWindow;
begin
  Show;
  WindowState := wsNormal;
  BringToFront;
end;

procedure TFormMain.TrayIconClick(Sender: TObject);
begin
  ShowWindow;
end;

procedure TFormMain.MenuShowClick(Sender: TObject);
begin
  ShowWindow;
end;

procedure TFormMain.MenuExitClick(Sender: TObject);
begin
  if Assigned(FThread) then
  begin
    ShowWindow;
    MessageDlg('A copy is running. Cancel it first, then exit.', mtInformation, [mbOK], 0);
    Exit;
  end;
  FQuitting := True;
  Close;
end;

procedure TFormMain.AddLog(const Msg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Msg);
end;

procedure TFormMain.DrivesChanged(Sender: TObject);
begin
  RefreshDrives(True);
end;

procedure TFormMain.RefreshDrives(Announce: Boolean);
var
  Old: TOfflineDriveArray;
  I, J: Integer;
  Known: Boolean;
  Names, Added: string;
begin
  Old := FDrives;
  FDrives := FindOfflineDrives;
  Names := '';
  Added := '';
  for I := 0 to High(FDrives) do
  begin
    if Names <> '' then Names := Names + ', ';
    Names := Names + FDrives[I].VolLabel + ' on ' + Copy(FDrives[I].Root, 1, 2);
    if not FDrives[I].SetUp and (FDrives[I].Description <> '') then
      Names := Names + ' (' + FDrives[I].Description + ' - no folders chosen yet)'
    else if not FDrives[I].SetUp then Names := Names + ' (new - not set up)'
    else if FDrives[I].Description <> '' then Names := Names + ' (' + FDrives[I].Description + ')';
    Known := False;
    for J := 0 to High(Old) do
      if (Old[J].Root = FDrives[I].Root) and (Old[J].VolLabel = FDrives[I].VolLabel) then Known := True;
    if not Known then
    begin
      if Added <> '' then Added := Added + ', ';
      Added := Added + FDrives[I].VolLabel + ' (' + Copy(FDrives[I].Root, 1, 2) + ')';
    end;
  end;
  if Names = '' then LabelDrives.Caption := 'No OFFLINE-x drive plugged in.'
  else LabelDrives.Caption := 'Plugged in: ' + Names;
  UpdateButtons;
  if Announce and (Added <> '') then
  begin
    AddLog('plugged in: ' + Added);
    for I := 0 to High(FDrives) do
    begin
      Known := False;
      for J := 0 to High(Old) do
        if (Old[J].Root = FDrives[I].Root) and (Old[J].VolLabel = FDrives[I].VolLabel) then Known := True;
      if not Known then LogDriveState(FDrives[I]);
    end;
    TrayIcon.BalloonTitle := 'Offline Backup';
    TrayIcon.BalloonHint := Added + ' plugged in. Open the window to start the copy.';
    for I := 0 to High(FDrives) do
      if not FDrives[I].SetUp and (Pos(FDrives[I].VolLabel, Added) > 0) then
        TrayIcon.BalloonHint := Added + ' plugged in. New drive - set it up under Drives... before copying.';
    // only when the window is not on screen (or about to be, at a start with /show) - otherwise it is noise
    if not Visible and not (FStarting and Application.ShowMainForm) then TrayIcon.ShowBalloonHint;
    ShowWindow;
  end;
end;

{ One log line about a drive that was just plugged in: what it is for and how its last copy went }
procedure TFormMain.LogDriveState(const D: TOfflineDrive);
var
  Info: TDriveInfo;
  Folders: TBackupSourceArray;
  Names: string;
  I: Integer;
begin
  if not ReadDriveInfo(D.Root, Info) then
    AddLog(D.VolLabel + ': new drive, not set up yet - use Drives... to set it up')
  else
  begin
    if Length(Info.Runs) = 0 then
      AddLog(D.VolLabel + ': ' + Info.Description + ' - not copied to yet')
    else
      AddLog(D.VolLabel + ': ' + Info.Description + ' - last copy ' + DriveRunText(Info.Runs[High(Info.Runs)]));
    Folders := Info.Sources;
    Names := '';
    for I := 0 to High(Folders) do
      if Folders[I].Enabled then
      begin
        if Names <> '' then Names := Names + ', ';
        Names := Names + Folders[I].Name;
      end;
    if not Info.HasList then Names := 'nothing yet - choose its folders under Drives...'
    else if Names = '' then Names := 'nothing ticked';
    AddLog(D.VolLabel + ': backs up ' + Names);
    if Length(Info.Removed) > 0 then
      AddLog(D.VolLabel + ': ' + IntToStr(Length(Info.Removed)) + ' folder(s) to move to _versions at the next copy');
  end;
end;

procedure TFormMain.UpdateButtons;
var
  I: Integer;
  Ready: Boolean;
begin
  Ready := False;                     // only drives that have been set up are copied to
  for I := 0 to High(FDrives) do
    if FDrives[I].SetUp then Ready := True;
  ButtonStart.Enabled := (FThread = nil) and Ready;
  MenuStart.Enabled := ButtonStart.Enabled;
  ButtonCancel.Enabled := FThread <> nil;
  // not while copying: the run in progress keeps the settings it started with
  ButtonSettings.Enabled := FThread = nil;
  MenuSettings.Enabled := ButtonSettings.Enabled;
  ButtonDrives.Enabled := (FThread = nil) and (Length(FDrives) > 0);
  MenuDrives.Enabled := ButtonDrives.Enabled;
  ButtonCheck.Enabled := FThread = nil;
  MenuCheck.Enabled := ButtonCheck.Enabled;
end;

procedure TFormMain.ButtonStartClick(Sender: TObject);
var
  I: Integer;
begin
  if Assigned(FThread) or (Length(FDrives) = 0) then Exit;
  FRunSummary := '';
  FRunProblem := False;
  FRunAllStopped := True;
  FQueue := nil;
  for I := 0 to High(FDrives) do
    if FDrives[I].SetUp then
    begin
      SetLength(FQueue, Length(FQueue) + 1);
      FQueue[High(FQueue)] := FDrives[I];
    end
    else
      AddLog(FDrives[I].VolLabel + ': not set up, or no folders chosen yet - skipped');
  if Length(FQueue) = 0 then Exit;
  ProgressBar.Position := 0;
  ClearProgress;
  StartNext;
end;

procedure TFormMain.StartNext;
var
  Drive: TOfflineDrive;
begin
  if Length(FQueue) = 0 then
  begin
    UpdateButtons;
    ShowRunSummary;
    Exit;
  end;
  Drive := FQueue[0];
  Delete(FQueue, 0, 1);
  AddLog('starting copy to ' + Drive.VolLabel + ' (' + Copy(Drive.Root, 1, 2) + ')');
  FThread := TOfflineCopyThread.Create(FSettings, Drive);
  FThread.OnLog := CopyLog;
  FThread.OnProgress := CopyProgress;
  FThread.OnConfirm := CopyConfirm;
  FThread.OnMissing := CopyMissing;
  FThread.OnPreview := CopyPreview;
  FThread.OnTerminate := CopyDone;
  FThread.FreeOnTerminate := True;
  UpdateButtons;
  FThread.Start;
end;

procedure TFormMain.ButtonCancelClick(Sender: TObject);
begin
  if not Assigned(FThread) then Exit;
  if FThread.Checking then
  begin
    if MessageDlg('Stop checking? The files checked so far are shown.', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      FThread.Cancel;
    Exit;
  end;
  if FThread.Verifying then
  begin
    if MessageDlg('Stop verifying? Folders already checked keep their results; nothing else changes.',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then FThread.Cancel;
    Exit;
  end;
  if MessageDlg('Stop the copy? The drive will be left part-copied until the next run.',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FQueue := nil;
    FThread.Cancel;
  end;
end;

procedure TFormMain.ButtonSettingsClick(Sender: TObject);
var
  S: TBackupSettings;
begin
  if Assigned(FThread) then Exit;
  ShowWindow;
  S := FSettings;
  if not TFormSettings.Execute(Self, S) then Exit;
  FSettings := S;
  if SaveSettings(SettingsFileName, FSettings) then AddLog('settings saved to ' + SettingsFileName)
  else MessageDlg('Could not save the settings to ' + SettingsFileName + '. They are used until the app is closed.',
    mtWarning, [mbOK], 0);
end;

procedure TFormMain.ButtonDrivesClick(Sender: TObject);
var
  I, Select, V: Integer;
begin
  if Assigned(FThread) or (Length(FDrives) = 0) then Exit;
  ShowWindow;
  Select := 0;                        // a new drive first, as that is usually why the window is opened
  for I := High(FDrives) downto 0 do
    if not FDrives[I].SetUp then Select := I;
  if TFormDrive.Execute(Self, FDrives, Select, FSettings, V) then RefreshDrives(False);
  if (V >= 0) and (V <= High(FDrives)) then StartVerify(FDrives[V]);
end;

procedure TFormMain.StartVerify(const Drive: TOfflineDrive);
begin
  if Assigned(FThread) then Exit;
  FQueue := nil;
  FRunSummary := '';
  FRunProblem := False;
  FRunAllStopped := True;
  ProgressBar.Position := 0;
  ClearProgress;
  AddLog('verifying ' + Drive.VolLabel + ' (' + Copy(Drive.Root, 1, 2) + ')');
  StartThread(TOfflineCopyThread.Create(FSettings, Drive, True));
end;

{ Hooks up and starts a verify or MD5 check (copies go through StartNext) }
procedure TFormMain.StartThread(T: TOfflineCopyThread);
begin
  FThread := T;
  FThread.OnLog := CopyLog;
  FThread.OnProgress := CopyProgress;
  FThread.OnConfirm := CopyConfirm;
  FThread.OnMissing := CopyMissing;
  FThread.OnPreview := CopyPreview;
  FThread.OnTerminate := CopyDone;
  FThread.FreeOnTerminate := True;
  UpdateButtons;
  FThread.Start;
end;

procedure TFormMain.ButtonCheckClick(Sender: TObject);
begin
  if Assigned(FThread) then Exit;
  ShowWindow;
  if not Md5Dialog.Execute then Exit;
  FQueue := nil;
  ProgressBar.Position := 0;
  ClearProgress;
  AddLog('checking ' + Md5Dialog.FileName);
  StartThread(TOfflineCopyThread.CreateCheck(FSettings, Md5Dialog.FileName));
end;

procedure TFormMain.CopyLog(const Msg: UnicodeString);
begin
  AddLog(Msg);
end;

procedure TFormMain.CopyProgress(const P: TCopyProgress);
begin
  FLastProgress := P;
  LabelStatus.Caption := P.Status;
  if P.Folder = '' then
    ClearProgress
  else
  begin
    LabelEta.Caption := ProgressEtaLine(P);
    LabelCounts.Caption := ProgressCountsLine(P);
    LabelRate.Caption := ProgressRateLine(P);
  end;
  ProgressBar.Position := P.Percent;
  if P.Speed < 0 then TrayIcon.Hint := 'Offline Backup - ' + IntToStr(P.Percent) + '%'
  else TrayIcon.Hint := 'Offline Backup - ' + IntToStr(P.Percent) + '% at ' + FormatSpeed(P.Speed);
end;

procedure TFormMain.ClearProgress;
begin
  LabelEta.Caption := '';
  LabelCounts.Caption := '';
  LabelRate.Caption := '';
end;

procedure TFormMain.CopyConfirm(const Folders: UnicodeString; var GoAhead: Boolean);
begin
  ShowWindow;
  GoAhead := MessageDlg('An unusually large number of files would be changed or deleted in: ' + Folders + '.' +
    sLineBreak + sLineBreak +
    'That can mean something went wrong on G: (ransomware, a deleted folder, a bad restore). ' +
    'Nothing on the drive has been touched yet. Old versions would be kept in _versions if you go ahead.' +
    sLineBreak + sLineBreak + 'Copy anyway?', mtWarning, [mbYes, mbNo], 0, mbNo) = mrYes;
end;

procedure TFormMain.CopyPreview(const P: TCopyPreview; var GoAhead: Boolean);
var
  Always: Boolean;
begin
  ShowWindow;
  Always := FSettings.PreviewAlways;
  GoAhead := TFormPreview.Execute(Self, P, Always);
  if Always <> FSettings.PreviewAlways then
  begin
    FSettings.PreviewAlways := Always;
    SaveSettings(SettingsFileName, FSettings);
    if Always then AddLog('the preview now shows before every copy')
    else AddLog('the preview now shows only when files would be deleted or moved (change it back in Settings)');
  end;
end;

procedure TFormMain.CopyMissing(const Path: UnicodeString; var Skip: Boolean);
begin
  ShowWindow;
  Skip := MessageDlg(Path + ' is not there (drive not plugged in, or the folder renamed or moved?).' +
    sLineBreak + sLineBreak +
    'Skip it and copy the other folders? Its copy on the OFFLINE drive is left as it was.' + sLineBreak + sLineBreak +
    'Yes = skip it and go on.   No = stop this copy, nothing is changed on the drive.',
    mtWarning, [mbYes, mbNo], 0) = mrYes;
end;

{ One line of the end-of-run popup for the drive T has just finished }
procedure TFormMain.AddRunLine(T: TOfflineCopyThread);
var
  Line: string;
  P: TCopyProgress;
begin
  P := FLastProgress;
  if T.CopyResult <> crStopped then FRunAllStopped := False;
  if not (T.CopyResult in [crOk]) and not T.Engine.NothingChosen then FRunProblem := True;
  if T.Verifying then
    case T.CopyResult of
      crOk: Line := 'verified ok - all ' + FormatFloat('#,##0', P.FilesDone) + ' files match their checksums.';
      crCancelled: Line := 'verify cancelled.';
      crSkipped: Line := T.Engine.SkipReason + '.';
    else
      Line := 'verify found ' + IntToStr(P.Errors) + ' bad or unreadable file(s) - see the log. ' +
        'They are copied again at the next copy.';
    end
  else
    case T.CopyResult of
      crOk:
        if (P.FilesDone = 0) and (P.Moved > 0) then
          Line := 'ok - ' + FormatFloat('#,##0', P.Moved) + ' file(s) moved on the drive, nothing needed copying. ' +
            'Safe to unplug.'
        else if P.FilesDone = 0 then Line := 'ok - already up to date, nothing needed copying. Safe to unplug.'
        else if P.Moved > 0 then
          Line := 'ok - ' + FormatFloat('#,##0', P.FilesDone) + ' file(s), ' + FormatSize(P.FilesDoneBytes) +
            ' copied, ' + FormatFloat('#,##0', P.Moved) + ' moved on the drive. Safe to unplug.'
        else Line := 'ok - ' + FormatFloat('#,##0', P.FilesDone) + ' file(s), ' + FormatSize(P.FilesDoneBytes) +
          ' copied. Safe to unplug.';
      crIncomplete: Line := 'copied, but missing folder(s) were skipped - see the log. Safe to unplug.';
      crStopped: Line := 'stopped - nothing was changed on the drive.';
      crSkipped: Line := T.Engine.SkipReason + '.';
      crCancelled: Line := 'cancelled - the copy on the drive is incomplete until the next run.';
    else
      Line := 'FAILED - see the log.';
    end;
  if FRunSummary <> '' then FRunSummary := FRunSummary + sLineBreak;
  FRunSummary := FRunSummary + T.DriveLabel + ': ' + Line;
end;

{ When the last drive of a run is done: a small window, so nobody has to read the log to know it finished }
procedure TFormMain.ShowRunSummary;
var
  S: string;
begin
  S := FRunSummary;
  FRunSummary := '';
  if (S = '') or FRunAllStopped or FQuitting then Exit;
  ShowWindow;
  if FRunProblem then MessageDlg('Finished, with problems:' + sLineBreak + sLineBreak + S, mtWarning, [mbOK], 0)
  else MessageDlg('Finished.' + sLineBreak + sLineBreak + S, mtInformation, [mbOK], 0);
end;

procedure TFormMain.CopyDone(Sender: TObject);
var
  T: TOfflineCopyThread;
begin
  T := Sender as TOfflineCopyThread;
  FThread := nil;                     // frees itself after this
  AddLog(T.DriveLabel + ': ' + CopyResultText(T.CopyResult));
  TrayIcon.Hint := 'Offline Backup';
  if T.Checking then
  begin
    if T.CopyResult = crOk then LabelStatus.Caption := ExtractFileName(T.CheckFile) + ': all files match'
    else if T.CopyResult = crCancelled then LabelStatus.Caption := ExtractFileName(T.CheckFile) + ': check cancelled'
    else LabelStatus.Caption := ExtractFileName(T.CheckFile) + ': problems found - see the list';
  end
  else if T.Verifying then
  begin
    if T.CopyResult = crOk then LabelStatus.Caption := T.DriveLabel + ': verified ok - every file matches'
    else if T.CopyResult = crCancelled then LabelStatus.Caption := T.DriveLabel + ': verify cancelled'
    else LabelStatus.Caption := T.DriveLabel + ': verify found problems - see the log below';
  end
  else if T.CopyResult = crOk then LabelStatus.Caption := T.DriveLabel + ': done - safe to unplug'
  else if T.CopyResult = crIncomplete then
    LabelStatus.Caption := T.DriveLabel + ': done except the missing folder(s) - safe to unplug'
  else LabelStatus.Caption := T.DriveLabel + ': ' + CopyResultText(T.CopyResult) + ' - see the log below';
  if not Visible then
  begin
    TrayIcon.BalloonTitle := 'Offline Backup';
    TrayIcon.BalloonHint := LabelStatus.Caption;
    TrayIcon.ShowBalloonHint;
  end;
  if not T.Checking then AddRunLine(T);
  if T.Checking and not FQuitting then
  begin
    TrayIcon.Hint := 'Offline Backup';
    UpdateButtons;
    ShowWindow;
    TFormCheck.Execute(Self, T.CheckFile, T.Engine.CheckItems, T.CopyResult);
    Exit;
  end;
  if FQuitting then Close else StartNext;
end;

end.
