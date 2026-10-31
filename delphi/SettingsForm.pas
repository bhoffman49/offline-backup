unit SettingsForm;

{ Settings window of the Delphi VCL edition: which folders are backed up, which folders are never copied,
  the safety limits and the log file. Works on a copy of the settings; the caller saves them.
  The Lazarus edition has the same form in ..\lazarus\SettingsForm.pas. }

interface

uses
  Windows, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  OfflineEngine;

type
  TFormSettings = class(TForm)
    LabelSources: TLabel;
    ListSources: TListView;
    ButtonAdd: TButton;
    ButtonEdit: TButton;
    ButtonRemove: TButton;
    LabelExclude: TLabel;
    ListExclude: TListBox;
    ButtonExcludeFolder: TButton;
    ButtonExcludeName: TButton;
    ButtonExcludeRemove: TButton;
    GroupLimits: TGroupBox;
    LabelBrakePct: TLabel;
    EditBrakePct: TEdit;
    LabelBrakeMin: TLabel;
    EditBrakeMin: TEdit;
    LabelKeepDays: TLabel;
    EditKeepDays: TEdit;
    LabelMaxFull: TLabel;
    EditMaxFull: TEdit;
    CheckPreview: TCheckBox;
    LabelLogFile: TLabel;
    EditLogFile: TEdit;
    ButtonLogFile: TButton;
    ButtonOK: TButton;
    ButtonCancel: TButton;
    FolderDialog: TFileOpenDialog;
    LogDialog: TSaveDialog;
    procedure ButtonAddClick(Sender: TObject);
    procedure ButtonEditClick(Sender: TObject);
    procedure ButtonRemoveClick(Sender: TObject);
    procedure ListSourcesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonExcludeFolderClick(Sender: TObject);
    procedure ButtonExcludeNameClick(Sender: TObject);
    procedure ButtonExcludeRemoveClick(Sender: TObject);
    procedure ListExcludeClick(Sender: TObject);
    procedure ButtonLogFileClick(Sender: TObject);
    procedure ButtonOKClick(Sender: TObject);
  private
    FSettings: TBackupSettings;
    procedure ShowSources;
    procedure ReadTicks;
    procedure UpdateButtons;
    function ReadNumber(Edit: TEdit; Min, Max: Integer; const What: string; out Value: Integer): Boolean;
  public
    // shows the window for a copy of Settings; on OK, Settings gets the new values
    class function Execute(AOwner: TComponent; var Settings: TBackupSettings): Boolean;
  end;

implementation

uses
  SourceForm;

{$R *.dfm}

class function TFormSettings.Execute(AOwner: TComponent; var Settings: TBackupSettings): Boolean;
var
  F: TFormSettings;
  I: Integer;
begin
  F := TFormSettings.Create(AOwner);
  try
    // fresh arrays: dynamic arrays in a record copy are shared, and a running copy may still hold the old ones
    F.FSettings := Settings;
    F.FSettings.Sources := Copy(Settings.Sources);
    F.FSettings.Exclude := Copy(Settings.Exclude);
    F.Caption := 'Offline Backup - Settings  (' + SettingsFileName + ')';
    F.ShowSources;
    for I := 0 to High(F.FSettings.Exclude) do F.ListExclude.Items.Add(F.FSettings.Exclude[I]);
    F.EditBrakePct.Text := IntToStr(Settings.BrakePercent);
    F.EditBrakeMin.Text := IntToStr(Settings.BrakeMinFiles);
    F.EditKeepDays.Text := IntToStr(Settings.KeepVersionDays);
    F.EditMaxFull.Text := IntToStr(Settings.MaxDriveFullPct);
    F.EditLogFile.Text := Settings.LogFile;
    F.CheckPreview.Checked := Settings.PreviewAlways;
    F.UpdateButtons;
    Result := F.ShowModal = mrOk;
    if Result then Settings := F.FSettings;
  finally
    F.Free;
  end;
end;

{ One row per source: [x] D:\MUSIC  to  D-mirror\MUSIC }
procedure TFormSettings.ShowSources;
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

procedure TFormSettings.ReadTicks;
var
  I: Integer;
begin
  for I := 0 to ListSources.Items.Count - 1 do
    if I <= High(FSettings.Sources) then FSettings.Sources[I].Enabled := ListSources.Items[I].Checked;
end;

procedure TFormSettings.UpdateButtons;
begin
  ButtonEdit.Enabled := ListSources.ItemIndex >= 0;
  ButtonRemove.Enabled := ListSources.ItemIndex >= 0;
  ButtonExcludeRemove.Enabled := ListExclude.ItemIndex >= 0;
end;

procedure TFormSettings.ListSourcesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TFormSettings.ListExcludeClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TFormSettings.ButtonAddClick(Sender: TObject);
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

procedure TFormSettings.ButtonEditClick(Sender: TObject);
var
  I: Integer;
begin
  I := ListSources.ItemIndex;
  if I < 0 then Exit;
  ReadTicks;
  if TFormSource.Execute(Self, FSettings.Sources, I) then ShowSources;
end;

procedure TFormSettings.ButtonRemoveClick(Sender: TObject);
var
  I: Integer;
begin
  I := ListSources.ItemIndex;
  if I < 0 then Exit;
  if MessageDlg('Remove ' + FSettings.Sources[I].Path + ' from the list?' + sLineBreak + sLineBreak +
    'Its copy on the OFFLINE drives (' + MirrorFolder(FSettings.Sources[I]) + ') is not deleted. ' +
    'To skip it for a while, untick it instead.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  ReadTicks;
  Delete(FSettings.Sources, I, 1);
  ShowSources;
end;

procedure TFormSettings.ButtonExcludeFolderClick(Sender: TObject);
begin
  if not FolderDialog.Execute then Exit;
  ListExclude.Items.Add(NormalizeSourcePath(FolderDialog.FileName));
  UpdateButtons;
end;

procedure TFormSettings.ButtonExcludeNameClick(Sender: TObject);
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

procedure TFormSettings.ButtonExcludeRemoveClick(Sender: TObject);
begin
  if ListExclude.ItemIndex >= 0 then ListExclude.Items.Delete(ListExclude.ItemIndex);
  UpdateButtons;
end;

procedure TFormSettings.ButtonLogFileClick(Sender: TObject);
begin
  LogDialog.FileName := EditLogFile.Text;
  if LogDialog.Execute then EditLogFile.Text := LogDialog.FileName;
end;

function TFormSettings.ReadNumber(Edit: TEdit; Min, Max: Integer; const What: string; out Value: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(Edit.Text), Value) and (Value >= Min) and (Value <= Max);
  if not Result then
  begin
    MessageDlg(What + ' must be a whole number from ' + IntToStr(Min) + ' to ' + IntToStr(Max) + '.',
      mtWarning, [mbOK], 0);
    Edit.SetFocus;
  end;
end;

procedure TFormSettings.ButtonOKClick(Sender: TObject);
var
  I: Integer;
begin
  // same limits as LoadSettings
  if not ReadNumber(EditBrakePct, 1, 100, 'The safety check percentage', FSettings.BrakePercent) then Exit;
  if not ReadNumber(EditBrakeMin, 1, 10000000, 'The safety check number of files', FSettings.BrakeMinFiles) then Exit;
  if not ReadNumber(EditKeepDays, 1, 36500, 'The days to keep old versions', FSettings.KeepVersionDays) then Exit;
  if not ReadNumber(EditMaxFull, 10, 100, 'The drive full percentage', FSettings.MaxDriveFullPct) then Exit;
  if Trim(EditLogFile.Text) = '' then
  begin
    MessageDlg('Choose a log file.', mtWarning, [mbOK], 0);
    Exit;
  end;
  FSettings.LogFile := Trim(EditLogFile.Text);
  FSettings.PreviewAlways := CheckPreview.Checked;
  ReadTicks;
  FSettings.Exclude := nil;
  for I := 0 to ListExclude.Items.Count - 1 do
  begin
    SetLength(FSettings.Exclude, Length(FSettings.Exclude) + 1);
    FSettings.Exclude[High(FSettings.Exclude)] := ListExclude.Items[I];
  end;
  ModalResult := mrOk;
end;

end.
