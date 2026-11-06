unit MainForm;

{ Main window of the Delphi VCL edition. Lives in the tray; closing the window only hides it.
  The copy itself is in ..\common\OfflineEngine.pas, shared with the Delphi edition. }

interface

uses
  Windows, Messages, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Menus,
  OfflineEngine, DriveWatcher, SideBar, SettingsPage, DrivesPage, PreviewForm, CheckPage, AboutBox;

const
  // the areas of the sidebar, in its order
  AREA_BACKUP = 0;
  AREA_DRIVES = 1;
  AREA_CHECK = 2;
  AREA_SETTINGS = 3;

type
  TFormMain = class(TForm)
    StatusBar: TStatusBar;
    PanelBackup: TPanel;
    PanelBackupActions: TPanel;
    ButtonStart: TButton;
    ButtonCancel: TButton;
    ButtonDismount: TButton;
    PageBackup: TPageControl;
    TabDrivesIn: TTabSheet;
    LabelDrives: TLabel;
    ListDrives: TListView;
    SplitterProgress: TSplitter;
    PanelProgress: TPanel;
    TabLog: TTabSheet;
    LabelStatus: TLabel;
    LabelFile: TLabel;
    LabelFileBar: TLabel;
    ProgressFile: TProgressBar;
    LabelFilePct: TLabel;
    LabelTotalBar: TLabel;
    ProgressBar: TProgressBar;
    LabelTotalPct: TLabel;
    LabelEta: TLabel;
    LabelCounts: TLabel;
    LabelRate: TLabel;
    MemoLog: TMemo;
    TrayIcon: TTrayIcon;
    TrayMenu: TPopupMenu;
    MenuShow: TMenuItem;
    MenuStart: TMenuItem;
    MenuSettings: TMenuItem;
    MenuDrives: TMenuItem;
    MenuCheck: TMenuItem;
    MenuDismount: TMenuItem;
    MenuSep: TMenuItem;
    MenuExit: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonCancelClick(Sender: TObject);
    procedure ButtonDismountClick(Sender: TObject);
    procedure MenuSettingsClick(Sender: TObject);
    procedure MenuDrivesClick(Sender: TObject);
    procedure MenuCheckClick(Sender: TObject);
    procedure TrayIconClick(Sender: TObject);
    procedure TrayIconMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
    FSide: TSideBar;
    FDrivesPage: TFrameDrives;
    FCheckPage: TFrameCheck;
    FSettingsPage: TFrameSettings;
    FReadyHint: string;               // what the status bar says while nothing else has happened
    procedure SideChanging(Sender: TObject; NewIndex: Integer; var Allow: Boolean);
    procedure SideChange(Sender: TObject);
    procedure DrivesVerify(const Drive: TOfflineDrive);
    procedure DrivesPageChanged(Sender: TObject);
    procedure ShowProgressTab;
    procedure SetStatus(const S: string);
    procedure OpenSettings;
    procedure SettingsSaved(const Settings: TBackupSettings);
    procedure RecordChecksumsChanged(Sender: TObject);
    procedure OpenDrives;
    procedure CheckRequested(const Md5File: string);
    procedure DrivesChanged(Sender: TObject);
    procedure RefreshDrives(Announce: Boolean);
    procedure LogDriveState(const D: TOfflineDrive);
    function LastCopyText(const D: TOfflineDrive): string;
    procedure StartNext;
    procedure StartVerify(const Drive: TOfflineDrive);
    procedure StartThread(T: TOfflineCopyThread);
    procedure UpdateButtons;
    procedure ShowWindow;
    procedure FlashTaskbar;
    procedure AddLog(const Msg: string);
    procedure WMQueryEndSession(var Msg: TWMQueryEndSession); message WM_QUERYENDSESSION;
    procedure CopyLog(const Msg: string);
    procedure CopyProgress(const P: TCopyProgress);
    procedure ClearProgress;
    procedure AddRunLine(T: TOfflineCopyThread);
    function UnplugAdvice(T: TOfflineCopyThread): string;
    procedure ShowRunSummary;
    procedure CopyConfirm(const Folders: string; var GoAhead: Boolean);
    procedure CopyMissing(const Path: string; var Skip: Boolean);
    procedure CopyPreview(const P: TCopyPreview; var GoAhead: Boolean);
    procedure CopyDone(Sender: TObject);
    procedure WMSysCommand(var Msg: TWMSysCommand); message WM_SYSCOMMAND;
  protected
    procedure CreateWnd; override;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

// the window handle can be made again (LCL does that on some changes), so the About item is added each time
procedure TFormMain.CreateWnd;
begin
  inherited;
  AddAboutToSystemMenu(Handle);
end;

procedure TFormMain.WMSysCommand(var Msg: TWMSysCommand);
begin
  if (Msg.CmdType and $FFF0) = SC_ABOUTBOX then ShowAboutBox(Self)
  else inherited;
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FSettings := LoadSettings(SettingsFileName);
  TrayIcon.Icon.Assign(Application.Icon);
  TrayIcon.Hint := 'Offline Backup';
  TrayIcon.Visible := True;
  Caption := 'Offline Backup ' + AppVersion;
  FSide := TSideBar.Create(Self);
  FSide.Parent := Self;
  FSide.Align := alLeft;
  FSide.Width := FSide.PreferredWidth;
  FSide.AddItem('Backup', 'backup');
  FSide.AddItem('Drives', 'drives');
  FSide.AddItem('MD5 check', 'check');
  FSide.AddItem('Settings', 'settings');
  FSide.AddItem('Restore', 'restore', False);   // still to come
  FSide.ItemIndex := AREA_BACKUP;
  FSide.OnChanging := SideChanging;
  FSide.OnChange := SideChange;
  FDrivesPage := TFrameDrives.Create(Self);
  FDrivesPage.Visible := False;
  FDrivesPage.Parent := Self;
  FDrivesPage.Align := alClient;
  FDrivesPage.OnVerify := DrivesVerify;
  FDrivesPage.OnChanged := DrivesPageChanged;
  FCheckPage := TFrameCheck.Create(Self);
  FCheckPage.Visible := False;
  FCheckPage.Parent := Self;
  FCheckPage.Align := alClient;
  FCheckPage.OnCheck := CheckRequested;
  FCheckPage.SetRecordChecksums(FSettings.RecordChecksums);
  FCheckPage.OnRecordChange := RecordChecksumsChanged;
  FSettingsPage := TFrameSettings.Create(Self);
  FSettingsPage.Visible := False;
  FSettingsPage.Parent := Self;
  FSettingsPage.Align := alClient;
  FSettingsPage.Load(FSettings);
  FSettingsPage.OnSave := SettingsSaved;
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

procedure TFormMain.WMQueryEndSession(var Msg: TWMQueryEndSession);
begin
  // Windows is shutting down: let the window close instead of hiding
  FQuitting := True;
  if Assigned(FThread) then FThread.Cancel;
  inherited;
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

{ Flashes the window's taskbar button until the window is looked at (does nothing while it is in front) }
procedure TFormMain.FlashTaskbar;
var
  FI: TFlashWInfo;
begin
  FillChar(FI, SizeOf(FI), 0);
  FI.cbSize := SizeOf(FI);
  FI.hwnd := Handle;
  FI.dwFlags := FLASHW_TRAY or FLASHW_TIMERNOFG;
  FlashWindowEx(FI);
end;

procedure TFormMain.TrayIconClick(Sender: TObject);
begin
  ShowWindow;
end;

{ The tray menu is shown here rather than through TrayIcon.PopupMenu: with MainFormOnTaskbar the VCL tray icon
  brings the wrong window to the front, and Windows then closes the menu as soon as it opens. }
procedure TFormMain.TrayIconMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  if Button <> mbRight then Exit;
  GetCursorPos(P);
  SetForegroundWindow(PopupList.Window);         // the window that owns the menu must be in front
  TrayMenu.Popup(P.X, P.Y);
  PostMessage(PopupList.Window, WM_NULL, 0, 0);  // Microsoft's advice, so the next right-click works too
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
  if FDrivesPage.Modified or FSettingsPage.Modified then
  begin
    ShowWindow;
    if not FDrivesPage.AskToSave or not FSettingsPage.AskToSave then Exit;
  end;
  FQuitting := True;
  Close;
end;

{ Leaving an area with unsaved changes: save them, drop them, or stay }
procedure TFormMain.SideChanging(Sender: TObject; NewIndex: Integer; var Allow: Boolean);
begin
  if FSide.ItemIndex = AREA_DRIVES then Allow := FDrivesPage.AskToSave
  else if FSide.ItemIndex = AREA_SETTINGS then Allow := FSettingsPage.AskToSave;
end;

{ The sidebar picked another area: show its page }
procedure TFormMain.SideChange(Sender: TObject);
begin
  PanelBackup.Visible := FSide.ItemIndex = AREA_BACKUP;
  FDrivesPage.Visible := FSide.ItemIndex = AREA_DRIVES;
  FCheckPage.Visible := FSide.ItemIndex = AREA_CHECK;
  FSettingsPage.Visible := FSide.ItemIndex = AREA_SETTINGS;
end;

procedure TFormMain.DrivesVerify(const Drive: TOfflineDrive);
begin
  StartVerify(Drive);
end;

{ A drive was set up or its folders saved }
procedure TFormMain.DrivesPageChanged(Sender: TObject);
begin
  RefreshDrives(False);
end;

{ A copy, verify or check is starting: show its progress, under the drives plugged in }
procedure TFormMain.ShowProgressTab;
begin
  if FSide.ItemIndex <> AREA_BACKUP then FSide.ItemIndex := AREA_BACKUP;
  PageBackup.ActivePage := TabDrivesIn;
end;

{ The latest news, both on the Progress tab and in the status bar, where it shows whatever area is open }
procedure TFormMain.SetStatus(const S: string);
begin
  LabelStatus.Caption := S;
  StatusBar.Panels[0].Text := S;
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
  Added, Gone, Hint, Said: string;
begin
  Old := FDrives;
  FDrives := FindOfflineDrives;
  Gone := '';
  FDrivesPage.SetDrives(FDrives, FSettings);
  FCheckPage.SetDrives(FDrives);
  Added := '';
  ListDrives.Items.BeginUpdate;
  try
    ListDrives.Items.Clear;
    for I := 0 to High(FDrives) do
      with ListDrives.Items.Add do
      begin
        Caption := Copy(FDrives[I].Root, 1, 2);
        if FDrives[I].VeraCrypt then SubItems.Add(FDrives[I].VolLabel + ' [VeraCrypt]')
        else SubItems.Add(FDrives[I].VolLabel);
        if not FDrives[I].SetUp and (FDrives[I].Description <> '') then
          SubItems.Add(FDrives[I].Description + ' - no folders chosen yet')
        else if not FDrives[I].SetUp then SubItems.Add('new - set it up under Drives')
        else SubItems.Add(FDrives[I].Description);
        SubItems.Add(LastCopyText(FDrives[I]));
      end;
  finally
    ListDrives.Items.EndUpdate;
  end;
  for I := 0 to High(FDrives) do
  begin
    Known := False;
    for J := 0 to High(Old) do
      if (Old[J].Root = FDrives[I].Root) and (Old[J].VolLabel = FDrives[I].VolLabel) then Known := True;
    if not Known then
    begin
      if Added <> '' then Added := Added + ', ';
      Added := Added + FDrives[I].VolLabel + ' (' + Copy(FDrives[I].Root, 1, 2) + ')';
    end;
  end;
  for J := 0 to High(Old) do
  begin
    Known := False;
    for I := 0 to High(FDrives) do
      if (Old[J].Root = FDrives[I].Root) and (Old[J].VolLabel = FDrives[I].VolLabel) then Known := True;
    if not Known then
    begin
      if Gone <> '' then Gone := Gone + ', ';
      Gone := Gone + Old[J].VolLabel + ' (' + Copy(Old[J].Root, 1, 2) + ')';
    end;
  end;
  if Length(FDrives) = 0 then
    LabelDrives.Caption := 'No OFFLINE-x drive plugged in. Plug in a backup drive whose name (volume label) is ' +
      'OFFLINE-A, OFFLINE-B, ... and it shows up here.'
  else LabelDrives.Caption := 'Start copy copies to every drive below that has been set up. A new drive is set up ' +
    'under Drives first.';
  if Length(FDrives) = 0 then StatusBar.Panels[1].Text := 'No OFFLINE drive plugged in'
  else if Length(FDrives) = 1 then StatusBar.Panels[1].Text := '1 OFFLINE drive plugged in'
  else StatusBar.Panels[1].Text := IntToStr(Length(FDrives)) + ' OFFLINE drives plugged in';
  // until there is news of a copy, the status bar says what to do next
  if Length(FDrives) = 0 then Hint := 'Plug in an OFFLINE drive to back up to.'
  else Hint := 'Ready - press Start copy.';
  for I := High(FDrives) downto 0 do
    if not FDrives[I].SetUp then Hint := FDrives[I].VolLabel + ' is new - set it up under Drives first.';
  if (StatusBar.Panels[0].Text = '') or (StatusBar.Panels[0].Text = FReadyHint) then
    StatusBar.Panels[0].Text := Hint;
  FReadyHint := Hint;
  UpdateButtons;
  // a drive that went away (unplugged, or dismounted in VeraCrypt) - said in the window, not in a balloon
  if Announce and (Gone <> '') then
  begin
    AddLog('gone: ' + Gone + ' (unplugged or dismounted)');
    if FThread = nil then StatusBar.Panels[0].Text := Gone + ' is gone - unplugged or dismounted.';
  end;
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
    Said := Added + ' plugged in.';
    for I := 0 to High(FDrives) do
      if not FDrives[I].SetUp and (Pos(FDrives[I].VolLabel, Added) > 0) then
      begin
        TrayIcon.BalloonHint := Added + ' plugged in. New drive - set it up under Drives before copying.';
        Said := Added + ' plugged in - a new drive: set it up under Drives first.';
      end;
    // only when the window is not on screen (or about to be, at a start with /show) - otherwise it is noise
    if not Visible and not (FStarting and Application.ShowMainForm) then TrayIcon.ShowBalloonHint;
    ShowWindow;
    // with the window open the balloon is left out, so say it in the window, and flash its taskbar button in case
    // it is behind other windows
    if not FStarting then
    begin
      if FThread = nil then StatusBar.Panels[0].Text := Said;
      FlashTaskbar;
    end;
    // not away from unsaved changes on the Drives or Settings page
    if (FThread = nil) and not FDrivesPage.Modified and not FSettingsPage.Modified then
    begin
      if FSide.ItemIndex <> AREA_BACKUP then FSide.ItemIndex := AREA_BACKUP;
      PageBackup.ActivePage := TabDrivesIn;
    end;
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
    AddLog(D.VolLabel + ': new drive, not set up yet - set it up under Drives')
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
    if not Info.HasList then Names := 'nothing yet - choose its folders under Drives'
    else if Names = '' then Names := 'nothing ticked';
    AddLog(D.VolLabel + ': backs up ' + Names);
    if Length(Info.Removed) > 0 then
      AddLog(D.VolLabel + ': ' + IntToStr(Length(Info.Removed)) + ' folder(s) to move to _versions at the next copy');
  end;
end;

{ The Last copy column of the drive list }
function TFormMain.LastCopyText(const D: TOfflineDrive): string;
var
  Info: TDriveInfo;
begin
  if not ReadDriveInfo(D.Root, Info) then Result := ''
  else if Length(Info.Runs) = 0 then Result := 'not copied to yet'
  else    // without the PC's name, which the History tab under Drives shows
    Result := Info.Runs[High(Info.Runs)].When + '  ' + Info.Runs[High(Info.Runs)].Result + '  ' +
      FormatSize(Info.Runs[High(Info.Runs)].Bytes) + ' copied';
end;

procedure TFormMain.UpdateButtons;
var
  I, Vera: Integer;
  Ready: Boolean;
  VeraName: string;
begin
  Ready := False;                     // only drives that have been set up are copied to
  for I := 0 to High(FDrives) do
    if FDrives[I].SetUp then Ready := True;
  ButtonStart.Enabled := (FThread = nil) and Ready;
  MenuStart.Enabled := ButtonStart.Enabled;
  ButtonCancel.Enabled := FThread <> nil;
  // not while copying: the run in progress keeps the settings it started with
  FDrivesPage.SetBusy(FThread <> nil);
  FCheckPage.SetBusy(FThread <> nil);
  FSettingsPage.SetBusy(FThread <> nil);
  MenuCheck.Enabled := FThread = nil;
  // Dismount only shows when a VeraCrypt OFFLINE volume is mounted - everyone else never sees it
  Vera := 0;
  VeraName := '';
  for I := 0 to High(FDrives) do
    if FDrives[I].VeraCrypt then
    begin
      Inc(Vera);
      VeraName := Copy(FDrives[I].Root, 1, 2);
    end;
  ButtonDismount.Visible := Vera > 0;
  if Vera = 1 then ButtonDismount.Caption := 'Dismount ' + VeraName else ButtonDismount.Caption := 'Dismount all';
  ButtonDismount.Enabled := FThread = nil;
  MenuDismount.Visible := ButtonDismount.Visible;
  MenuDismount.Caption := ButtonDismount.Caption + ' (VeraCrypt)';
  MenuDismount.Enabled := ButtonDismount.Enabled;
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
  ShowProgressTab;
  StartNext;
end;

procedure TFormMain.StartNext;
var
  Drive: TOfflineDrive;
begin
  if Length(FQueue) = 0 then
  begin
    RefreshDrives(False);             // the drive list's Last copy, from the drive maps the run updated
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

procedure TFormMain.MenuSettingsClick(Sender: TObject);
begin
  ShowWindow;
  OpenSettings;
end;

procedure TFormMain.MenuDrivesClick(Sender: TObject);
begin
  ShowWindow;
  OpenDrives;
end;

procedure TFormMain.MenuCheckClick(Sender: TObject);
begin
  ShowWindow;
  FSide.ItemIndex := AREA_CHECK;
  if FSide.ItemIndex = AREA_CHECK then FCheckPage.OpenFile;    // not if the Drives page kept its unsaved edits
end;

procedure TFormMain.OpenSettings;
begin
  FSide.ItemIndex := AREA_SETTINGS;
end;

{ The 'record checksums after each copy' tick on the MD5 check page: saved straight away, like the preview's tick }
procedure TFormMain.RecordChecksumsChanged(Sender: TObject);
begin
  FSettings.RecordChecksums := FCheckPage.RecordChecksums;
  SaveSettings(SettingsFileName, FSettings);
  if not FSettingsPage.Modified then FSettingsPage.Load(FSettings);
  if FSettings.RecordChecksums then AddLog('checksums are recorded after each copy again')
  else AddLog('checksums are no longer recorded after each copy - Verify drive adds them (switch it back on under MD5 check)');
end;

{ Save on the Settings page }
procedure TFormMain.SettingsSaved(const Settings: TBackupSettings);
var
  Keep: Boolean;
begin
  Keep := FSettings.RecordChecksums;   // set on the MD5 check page, not on the Settings page
  FSettings := Settings;
  FSettings.RecordChecksums := Keep;
  FDrivesPage.SetDrives(FDrives, FSettings);    // Add starting folders uses the new ones
  if SaveSettings(SettingsFileName, FSettings) then AddLog('settings saved to ' + SettingsFileName)
  else MessageDlg('Could not save the settings to ' + SettingsFileName + '. They are used until the app is closed.',
    mtWarning, [mbOK], 0);
end;

procedure TFormMain.OpenDrives;
begin
  FSide.ItemIndex := AREA_DRIVES;
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
  ShowProgressTab;
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

{ VeraCrypt does the dismount (VeraCrypt.exe /dismount X /quit /silent); never forced, so open files are reported }
procedure TFormMain.ButtonDismountClick(Sender: TObject);
var
  I: Integer;
  Problem, Problems, Done, Line: string;
begin
  if Assigned(FThread) then Exit;
  ShowWindow;
  Problems := '';
  Done := '';
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(FDrives) do
      if FDrives[I].VeraCrypt then
        if DismountVeraCrypt(FSettings.VeraCryptExe, FDrives[I].Letter, Problem) then
        begin
          Line := FDrives[I].VolLabel + ' (' + Copy(FDrives[I].Root, 1, 2) + '): dismounted in VeraCrypt - safe to unplug';
          AddLog(Line);
          AppendLogLine(FSettings.LogFile, Line);   // in the log file too, like a dismount after a copy
          if Done <> '' then Done := Done + ', ';
          Done := Done + FDrives[I].VolLabel;
        end
        else
        begin
          Line := FDrives[I].VolLabel + ': not dismounted: ' + Problem;
          AddLog(Line);
          AppendLogLine(FSettings.LogFile, Line);
          if Problems <> '' then Problems := Problems + sLineBreak + sLineBreak;
          Problems := Problems + FDrives[I].VolLabel + ': ' + Problem + '.';
        end;
  finally
    Screen.Cursor := crDefault;
  end;
  RefreshDrives(False);
  if Done <> '' then SetStatus(Done + ': dismounted - safe to unplug');
  if Problems <> '' then MessageDlg(Problems, mtWarning, [mbOK], 0);
end;

{ Open MD5 file or Check again on the MD5 check page: the progress shows under Backup, the result back on the page }
procedure TFormMain.CheckRequested(const Md5File: string);
begin
  if Assigned(FThread) then Exit;
  FQueue := nil;
  ProgressBar.Position := 0;
  ClearProgress;
  ShowProgressTab;
  AddLog('checking ' + Md5File);
  StartThread(TOfflineCopyThread.CreateCheck(FSettings, Md5File));
end;

procedure TFormMain.CopyLog(const Msg: string);
begin
  AddLog(Msg);
end;

procedure TFormMain.CopyProgress(const P: TCopyProgress);
begin
  FLastProgress := P;
  SetStatus(P.Status);
  if P.Folder = '' then
    ClearProgress
  else
  begin
    LabelEta.Caption := ProgressEtaLine(P);
    LabelCounts.Caption := ProgressCountsLine(P);
    LabelRate.Caption := ProgressRateLine(P);
    LabelTotalPct.Caption := IntToStr(P.Percent) + '% of ' + FormatSize(P.BytesTotal);
  end;
  ProgressBar.Position := P.Percent;
  // while checksums are recorded, the lower bar shows how far that is (the copy itself is done)
  if P.Hashing then
  begin
    LabelTotalBar.Caption := 'Checksums:';
    if P.HashBytes > 0 then ProgressBar.Position := Trunc(100.0 * P.HashBytesDone / P.HashBytes)
    else ProgressBar.Position := 100;
    LabelTotalPct.Caption := IntToStr(ProgressBar.Position) + '% of ' + FormatSize(P.HashBytes);
  end
  else LabelTotalBar.Caption := 'Total:';
  // the file bar: copies only - a verify or MD5 check reads files without reporting each one
  LabelFileBar.Visible := not P.Verifying and not P.Checking;
  ProgressFile.Visible := LabelFileBar.Visible;
  LabelFilePct.Visible := LabelFileBar.Visible;
  if P.CurrentFile = '' then
  begin
    LabelFile.Caption := '';
    LabelFilePct.Caption := '';
    ProgressFile.Position := 0;
  end
  else
  begin
    if P.Hashing then LabelFile.Caption := 'Reading: ' + ExtractFileName(P.CurrentFile)
    else LabelFile.Caption := 'Copying: ' + ExtractFileName(P.CurrentFile);
    if P.CurrentFileSize > 0 then ProgressFile.Position := Trunc(100.0 * P.CurrentFileDone / P.CurrentFileSize)
    else ProgressFile.Position := 100;
    LabelFilePct.Caption := IntToStr(ProgressFile.Position) + '% of ' + FormatSize(P.CurrentFileSize);
  end;
  if P.Speed < 0 then TrayIcon.Hint := 'Offline Backup - ' + IntToStr(P.Percent) + '%'
  else TrayIcon.Hint := 'Offline Backup - ' + IntToStr(P.Percent) + '% at ' + FormatSpeed(P.Speed);
end;

procedure TFormMain.ClearProgress;
begin
  LabelFile.Caption := '';
  LabelFilePct.Caption := '';
  LabelTotalPct.Caption := '';
  ProgressFile.Position := 0;
  LabelEta.Caption := '';
  LabelCounts.Caption := '';
  LabelRate.Caption := '';
end;

procedure TFormMain.CopyConfirm(const Folders: string; var GoAhead: Boolean);
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
    if not FSettingsPage.Modified then FSettingsPage.Load(FSettings);   // the tick on the page too
    if Always then AddLog('the preview now shows before every copy')
    else AddLog('the preview now shows only when files would be deleted or moved (change it back in Settings)');
  end;
end;

procedure TFormMain.CopyMissing(const Path: string; var Skip: Boolean);
begin
  ShowWindow;
  Skip := MessageDlg(Path + ' is not there (drive not plugged in, or the folder renamed or moved?).' +
    sLineBreak + sLineBreak +
    'Skip it and copy the other folders? Its copy on the OFFLINE drive is left as it was.' + sLineBreak + sLineBreak +
    'Yes = skip it and go on.   No = stop this copy, nothing is changed on the drive.',
    mtWarning, [mbYes, mbNo], 0) = mrYes;
end;

{ What to do before unplugging the drive T has just copied to: a VeraCrypt volume has to be dismounted first }
function TFormMain.UnplugAdvice(T: TOfflineCopyThread): string;
begin
  if T.Engine.Dismounted then Result := 'dismounted - safe to unplug'
  else if T.Engine.VeraCrypt then Result := 'dismount it in VeraCrypt (or with Dismount), then unplug'
  else Result := 'safe to unplug';
end;

{ One line of the end-of-run popup for the drive T has just finished }
procedure TFormMain.AddRunLine(T: TOfflineCopyThread);
var
  Line, Unplug: string;
  P: TCopyProgress;
begin
  Unplug := UnplugAdvice(T);
  Unplug := ' ' + UpperCase(Copy(Unplug, 1, 1)) + Copy(Unplug, 2, MaxInt) + '.';
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
          Line := 'ok - ' + FormatFloat('#,##0', P.Moved) + ' file(s) moved on the drive, nothing needed copying.' +
            Unplug
        else if P.FilesDone = 0 then Line := 'ok - already up to date, nothing needed copying.' + Unplug
        else if P.Moved > 0 then
          Line := 'ok - ' + FormatFloat('#,##0', P.FilesDone) + ' file(s), ' + FormatSize(P.FilesDoneBytes) +
            ' copied, ' + FormatFloat('#,##0', P.Moved) + ' moved on the drive.' + Unplug
        else Line := 'ok - ' + FormatFloat('#,##0', P.FilesDone) + ' file(s), ' + FormatSize(P.FilesDoneBytes) +
          ' copied.' + Unplug;
      crIncomplete: Line := 'copied, but missing folder(s) were skipped - see the log.' + Unplug;
      crStopped: Line := 'stopped - nothing was changed on the drive.';
      crSkipped: Line := T.Engine.SkipReason + '.';
      crCancelled: Line := 'cancelled - the copy on the drive is incomplete until the next run.';
    else
      Line := 'FAILED - see the log.';
    end;
  if not T.Verifying and T.Engine.ChecksumsSkipped and (T.CopyResult in [crOk, crIncomplete]) then
    Line := Line + ' Checksums not recorded - run Verify drive to add them.';
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
    if T.CopyResult = crOk then SetStatus(ExtractFileName(T.CheckFile) + ': all files match')
    else if T.CopyResult = crCancelled then SetStatus(ExtractFileName(T.CheckFile) + ': check cancelled')
    else SetStatus(ExtractFileName(T.CheckFile) + ': problems found - see MD5 check');
  end
  else if T.Verifying then
  begin
    if T.CopyResult = crOk then SetStatus(T.DriveLabel + ': verified ok - every file matches')
    else if T.CopyResult = crCancelled then SetStatus(T.DriveLabel + ': verify cancelled')
    else SetStatus(T.DriveLabel + ': verify found problems - see the Log tab');
  end
  else if T.CopyResult = crOk then SetStatus(T.DriveLabel + ': done - ' + UnplugAdvice(T))
  else if T.CopyResult = crIncomplete then
    SetStatus(T.DriveLabel + ': done except the missing folder(s) - ' + UnplugAdvice(T))
  else SetStatus(T.DriveLabel + ': ' + CopyResultText(T.CopyResult) + ' - see the Log tab');
  if not Visible then
  begin
    TrayIcon.BalloonTitle := 'Offline Backup';
    TrayIcon.BalloonHint := LabelStatus.Caption;
    TrayIcon.ShowBalloonHint;
  end;
  if not T.Checking then AddRunLine(T);
  if T.Engine.Dismounted then RefreshDrives(False);  // in case VeraCrypt's own "drive gone" notice is late
  if T.Checking and not FQuitting then
  begin
    TrayIcon.Hint := 'Offline Backup';
    UpdateButtons;
    ShowWindow;
    FCheckPage.ShowResult(T.CheckFile, T.Engine.CheckItems, T.CopyResult);
    FSide.ItemIndex := AREA_CHECK;
    Exit;
  end;
  if FQuitting then Close else StartNext;
end;

end.
