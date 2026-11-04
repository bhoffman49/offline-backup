unit SettingsPage;

{ Settings area of the Lazarus/LCL main window: the starting folders, the folders never copied, the safety limits,
  VeraCrypt and the log file. Changes wait for Save; the main window keeps and writes the settings.
  The Delphi edition has the same page in ..\delphi\SettingsPage.pas. }

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  OfflineEngine;

type
  TSettingsEvent = procedure(const Settings: TBackupSettings) of object;

  TFrameSettings = class(TFrame)
    PanelActions: TPanel;
    ButtonSave: TButton;
    ButtonUndo: TButton;
    PageSettings: TPageControl;
    TabSources: TTabSheet;
    LabelSources: TLabel;
    ListSources: TListView;
    PanelSourceButtons: TPanel;
    ButtonAdd: TButton;
    ButtonEdit: TButton;
    ButtonRemove: TButton;
    TabExclude: TTabSheet;
    LabelExclude: TLabel;
    ListExclude: TListBox;
    PanelExcludeButtons: TPanel;
    ButtonExcludeFolder: TButton;
    ButtonExcludeName: TButton;
    ButtonExcludeRemove: TButton;
    TabSafety: TTabSheet;
    LabelBrakePct: TLabel;
    EditBrakePct: TEdit;
    LabelBrakeMin: TLabel;
    EditBrakeMin: TEdit;
    LabelKeepDays: TLabel;
    EditKeepDays: TEdit;
    LabelMaxFull: TLabel;
    EditMaxFull: TEdit;
    CheckPreview: TCheckBox;
    LabelPreviewNote: TLabel;
    TabEncryption: TTabSheet;
    CheckDismount: TCheckBox;
    LabelDismountNote: TLabel;
    LabelVeraCrypt: TLabel;
    TabLogFile: TTabSheet;
    LabelLogFile: TLabel;
    EditLogFile: TEdit;
    ButtonLogFile: TButton;
    LabelSettingsFile: TLabel;
    FolderDialog: TSelectDirectoryDialog;
    LogDialog: TSaveDialog;
    procedure ButtonSaveClick(Sender: TObject);
    procedure ButtonUndoClick(Sender: TObject);
    procedure ButtonAddClick(Sender: TObject);
    procedure ButtonEditClick(Sender: TObject);
    procedure ButtonRemoveClick(Sender: TObject);
    procedure ListSourcesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonExcludeFolderClick(Sender: TObject);
    procedure ButtonExcludeNameClick(Sender: TObject);
    procedure ButtonExcludeRemoveClick(Sender: TObject);
    procedure ListExcludeClick(Sender: TObject);
    procedure ButtonLogFileClick(Sender: TObject);
  private
    FSettings: TBackupSettings;   // as last saved, plus the starting folders being edited
    FSaved: TBackupSettings;      // as last saved, for Undo
    FSavedState: string;          // StateText when shown or saved, to spot unsaved edits
    FBusy: Boolean;
    FOnSave: TSettingsEvent;
    procedure ShowSources;
    procedure ReadTicks;
    procedure UpdateButtons;
    function StateText: string;
    function ReadNumber(Edit: TEdit; Min, Max: Integer; const What: string; out Value: Integer): Boolean;
    function Save: Boolean;
  public
    // shows Settings; unsaved edits are dropped
    procedure Load(const Settings: TBackupSettings);
    procedure SetBusy(Busy: Boolean);
    function Modified: Boolean;
    // unsaved edits: save them, drop them, or stay. True = go on.
    function AskToSave: Boolean;
    property OnSave: TSettingsEvent read FOnSave write FOnSave;   // Save was pressed and the values are good
  end;

implementation

uses
  SourceForm;

{$R *.lfm}

procedure TFrameSettings.Load(const Settings: TBackupSettings);
var
  I: Integer;
  Exe: string;
begin
  // fresh arrays: dynamic arrays in a record copy are shared, and a running copy may still hold the old ones
  FSaved := Settings;
  FSaved.Sources := Copy(Settings.Sources);
  FSaved.Exclude := Copy(Settings.Exclude);
  FSettings := FSaved;
  FSettings.Sources := Copy(FSaved.Sources);
  ShowSources;
  ListExclude.Items.Clear;
  for I := 0 to High(Settings.Exclude) do ListExclude.Items.Add(Settings.Exclude[I]);
  EditBrakePct.Text := IntToStr(Settings.BrakePercent);
  EditBrakeMin.Text := IntToStr(Settings.BrakeMinFiles);
  EditKeepDays.Text := IntToStr(Settings.KeepVersionDays);
  EditMaxFull.Text := IntToStr(Settings.MaxDriveFullPct);
  EditLogFile.Text := Settings.LogFile;
  CheckPreview.Checked := Settings.PreviewAlways;
  CheckDismount.Checked := Settings.DismountAfterCopy;
  Exe := FindVeraCrypt(Settings.VeraCryptExe);
  if Exe <> '' then LabelVeraCrypt.Caption := 'VeraCrypt found: ' + Exe
  else LabelVeraCrypt.Caption := 'VeraCrypt is not installed on this PC. Without it the app can''t dismount ' +
    'VeraCrypt drives - dismount them in VeraCrypt itself.';
  // the file on a line of its own, as a long path gets cut off at the window's edge; the hint has all of it
  if SettingsInAppData then
    LabelSettingsFile.Caption := 'The app''s own folder can''t be written to, so the settings are kept in:' +
      sLineBreak + SettingsFileName
  else LabelSettingsFile.Caption := 'The settings are kept in:' + sLineBreak + SettingsFileName;
  LabelSettingsFile.Hint := SettingsFileName;
  LabelSettingsFile.ShowHint := True;
  UpdateButtons;
  FSavedState := StateText;
end;

procedure TFrameSettings.SetBusy(Busy: Boolean);
var
  I: Integer;
begin
  FBusy := Busy;
  // not while copying: the run in progress keeps the settings it started with
  for I := 0 to PageSettings.PageCount - 1 do PageSettings.Pages[I].Enabled := not Busy;
  UpdateButtons;
end;

{ One row per source: [x] D:\MUSIC  to  D-mirror\MUSIC }
procedure TFrameSettings.ShowSources;
var
  I, Sel: Integer;
  Item: TListItem;
begin
  Sel := ListSources.ItemIndex;
  ListSources.Items.BeginUpdate;
  try
    ListSources.Items.Clear;
    for I := 0 to High(FSettings.Sources) do
    begin
      Item := ListSources.Items.Add;
      Item.Caption := FSettings.Sources[I].Path;
      Item.SubItems.Add('to');
      Item.SubItems.Add(MirrorFolder(FSettings.Sources[I]));
      Item.Checked := FSettings.Sources[I].Enabled;
    end;
  finally
    ListSources.Items.EndUpdate;
  end;
  if Sel >= ListSources.Items.Count then Sel := ListSources.Items.Count - 1;
  if Sel >= 0 then ListSources.ItemIndex := Sel;
  UpdateButtons;
end;

procedure TFrameSettings.ReadTicks;
var
  I: Integer;
begin
  for I := 0 to ListSources.Items.Count - 1 do
    if I <= High(FSettings.Sources) then FSettings.Sources[I].Enabled := ListSources.Items[I].Checked;
end;

procedure TFrameSettings.UpdateButtons;
begin
  ButtonEdit.Enabled := ListSources.ItemIndex >= 0;
  ButtonRemove.Enabled := ListSources.ItemIndex >= 0;
  ButtonExcludeRemove.Enabled := ListExclude.ItemIndex >= 0;
  ButtonSave.Enabled := not FBusy;
  ButtonUndo.Enabled := not FBusy;
end;

{ Everything Save would write, as text - differs from FSavedState when there are unsaved edits }
function TFrameSettings.StateText: string;
var
  I: Integer;
begin
  ReadTicks;
  Result := '';
  for I := 0 to High(FSettings.Sources) do
    Result := Result + IntToStr(Ord(FSettings.Sources[I].Enabled)) + FSettings.Sources[I].Path + '|' +
      FSettings.Sources[I].Name + #1;
  Result := Result + #2 + ListExclude.Items.Text + #2 + Trim(EditBrakePct.Text) + #1 + Trim(EditBrakeMin.Text) + #1 +
    Trim(EditKeepDays.Text) + #1 + Trim(EditMaxFull.Text) + #1 + Trim(EditLogFile.Text) + #1 +
    IntToStr(Ord(CheckPreview.Checked)) + IntToStr(Ord(CheckDismount.Checked));
end;

function TFrameSettings.Modified: Boolean;
begin
  Result := StateText <> FSavedState;
end;

function TFrameSettings.AskToSave: Boolean;
begin
  Result := True;
  if not Modified then Exit;
  case MessageDlg('Save the changes to the settings?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: Result := Save;
    mrNo: Load(FSaved);                          // drop the edits, so they don't come back later
  else
    Result := False;
  end;
end;

procedure TFrameSettings.ListSourcesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TFrameSettings.ListExcludeClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TFrameSettings.ButtonAddClick(Sender: TObject);
var
  Path, Problem: string;
  I, N: Integer;
begin
  if not FolderDialog.Execute then Exit;
  Path := NormalizeSourcePath(FolderDialog.FileName);
  Problem := SourceProblem(Path);
  for I := 0 to High(FSettings.Sources) do
    if SameText(NormalizeSourcePath(FSettings.Sources[I].Path), Path) then Problem := Path + ' is already in the list.';
  if Problem <> '' then
  begin
    MessageDlg(Problem, mtWarning, [mbOK], 0);
    Exit;
  end;
  ReadTicks;
  N := Length(FSettings.Sources);
  SetLength(FSettings.Sources, N + 1);
  FSettings.Sources[N].Path := Path;
  FSettings.Sources[N].Name := UniqueSourceName(FSettings.Sources, N, Path, DefaultSourceName(Path));
  FSettings.Sources[N].Enabled := True;
  ShowSources;
  ListSources.ItemIndex := N;
  UpdateButtons;
end;

procedure TFrameSettings.ButtonEditClick(Sender: TObject);
var
  I: Integer;
begin
  I := ListSources.ItemIndex;
  if I < 0 then Exit;
  ReadTicks;
  if TFormSource.Execute(Self, FSettings.Sources, I) then ShowSources;
end;

procedure TFrameSettings.ButtonRemoveClick(Sender: TObject);
var
  I: Integer;
begin
  I := ListSources.ItemIndex;
  if I < 0 then Exit;
  if MessageDlg('Remove ' + FSettings.Sources[I].Path + ' from the starting folders?' + sLineBreak + sLineBreak +
    'Drives already set up keep it on their own list - this only changes what Add starting folders offers.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  ReadTicks;
  Delete(FSettings.Sources, I, 1);
  ShowSources;
end;

procedure TFrameSettings.ButtonExcludeFolderClick(Sender: TObject);
begin
  if not FolderDialog.Execute then Exit;
  ListExclude.Items.Add(NormalizeSourcePath(FolderDialog.FileName));
  UpdateButtons;
end;

procedure TFrameSettings.ButtonExcludeNameClick(Sender: TObject);
var
  S: string;
begin
  S := '';
  if not InputQuery('Excluded folder', 'Folder name to skip everywhere (wildcards allowed, e.g. build or *.tmp):', S) then
    Exit;
  S := Trim(S);
  if S <> '' then ListExclude.Items.Add(S);
  UpdateButtons;
end;

procedure TFrameSettings.ButtonExcludeRemoveClick(Sender: TObject);
begin
  if ListExclude.ItemIndex >= 0 then ListExclude.Items.Delete(ListExclude.ItemIndex);
  UpdateButtons;
end;

procedure TFrameSettings.ButtonLogFileClick(Sender: TObject);
begin
  LogDialog.FileName := EditLogFile.Text;
  if LogDialog.Execute then EditLogFile.Text := LogDialog.FileName;
end;

function TFrameSettings.ReadNumber(Edit: TEdit; Min, Max: Integer; const What: string; out Value: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(Edit.Text), Value) and (Value >= Min) and (Value <= Max);
  if not Result then
  begin
    MessageDlg(What + ' must be a whole number from ' + IntToStr(Min) + ' to ' + IntToStr(Max) + '.',
      mtWarning, [mbOK], 0);
    PageSettings.ActivePage := TabSafety;
    Edit.SetFocus;
  end;
end;

procedure TFrameSettings.ButtonSaveClick(Sender: TObject);
begin
  Save;
end;

procedure TFrameSettings.ButtonUndoClick(Sender: TObject);
begin
  if not Modified then Exit;
  if MessageDlg('Undo the changes to the settings since they were last saved?', mtConfirmation, [mbYes, mbNo], 0) =
    mrYes then Load(FSaved);
end;

function TFrameSettings.Save: Boolean;
var
  S: TBackupSettings;
  I: Integer;
begin
  Result := False;
  if FBusy then Exit;
  S := FSettings;
  // same limits as LoadSettings
  if not ReadNumber(EditBrakePct, 1, 100, 'The safety check percentage', S.BrakePercent) then Exit;
  if not ReadNumber(EditBrakeMin, 1, 10000000, 'The safety check number of files', S.BrakeMinFiles) then Exit;
  if not ReadNumber(EditKeepDays, 1, 36500, 'The days to keep old versions', S.KeepVersionDays) then Exit;
  if not ReadNumber(EditMaxFull, 10, 100, 'The drive full percentage', S.MaxDriveFullPct) then Exit;
  if Trim(EditLogFile.Text) = '' then
  begin
    MessageDlg('Choose a log file.', mtWarning, [mbOK], 0);
    PageSettings.ActivePage := TabLogFile;
    Exit;
  end;
  S.LogFile := Trim(EditLogFile.Text);
  S.PreviewAlways := CheckPreview.Checked;
  S.DismountAfterCopy := CheckDismount.Checked;
  ReadTicks;
  S.Sources := Copy(FSettings.Sources);
  S.Exclude := nil;
  for I := 0 to ListExclude.Items.Count - 1 do
  begin
    SetLength(S.Exclude, Length(S.Exclude) + 1);
    S.Exclude[High(S.Exclude)] := ListExclude.Items[I];
  end;
  Load(S);
  if Assigned(FOnSave) then FOnSave(S);
  Result := True;
end;

end.
