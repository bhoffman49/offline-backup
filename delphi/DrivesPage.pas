unit DrivesPage;

{ Drives area of the Delphi VCL main window: set up a new OFFLINE drive (write its drive map), say what it is for and
  which folders it backs up, and see what has been copied to it. The Lazarus edition has the same page in
  ..\lazarus\DrivesPage.pas. }

interface

uses
  Windows, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  OfflineEngine;

type
  TVerifyEvent = procedure(const Drive: TOfflineDrive) of object;

  TFrameDrives = class(TFrame)
    PanelActions: TPanel;
    ButtonApply: TButton;
    ButtonUndo: TButton;
    ButtonVerify: TButton;
    ButtonPrepare: TButton;
    PanelTop: TPanel;
    LabelDrive: TLabel;
    ComboDrives: TComboBox;
    LabelState: TLabel;
    PageDrive: TPageControl;
    TabFolders: TTabSheet;
    PanelDescription: TPanel;
    PanelFolderButtons: TPanel;
    LabelDescription: TLabel;
    EditDescription: TEdit;
    LabelFolders: TLabel;
    ListFolders: TListView;
    ButtonAddFolder: TButton;
    ButtonEditFolder: TButton;
    ButtonRemoveFolder: TButton;
    ButtonStarting: TButton;
    LabelFolderNote: TLabel;
    TabHistory: TTabSheet;
    LabelHistory: TLabel;
    ListHistory: TListView;
    FolderDialog: TFileOpenDialog;
    procedure ComboDrivesChange(Sender: TObject);
    procedure ButtonApplyClick(Sender: TObject);
    procedure ButtonUndoClick(Sender: TObject);
    procedure ButtonAddFolderClick(Sender: TObject);
    procedure ButtonEditFolderClick(Sender: TObject);
    procedure ButtonRemoveFolderClick(Sender: TObject);
    procedure ButtonStartingClick(Sender: TObject);
    procedure ButtonVerifyClick(Sender: TObject);
    procedure ListFoldersSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
  private
    FDrives: TOfflineDriveArray;
    FSettings: TBackupSettings;
    FInfo: TDriveInfo;
    FList: TBackupSourceArray;    // the folders being edited
    FRemoved: TPathList;          // drive folders taken off the list (moved to _versions at the next copy)
    FSetUp: Boolean;
    FSavedState: string;          // StateText when shown or saved, to spot unsaved edits
    FLastIndex: Integer;
    FBusy: Boolean;               // a copy, verify or check is running: look, but don't change anything
    FOnVerify: TVerifyEvent;
    FOnChanged: TNotifyEvent;
    procedure ShowDrive;
    procedure ShowFolders;
    procedure ReadTicks;
    procedure UpdateButtons;
    procedure AddFolder(const Path: string);
    function StateText: string;
    function Apply: Boolean;
    function DriveTag: string;
  public
    constructor Create(AOwner: TComponent); override;
    // the drives plugged in now; the drive shown stays (with any unsaved edits) if it is still there
    procedure SetDrives(const Drives: TOfflineDriveArray; const Settings: TBackupSettings);
    procedure SetBusy(Busy: Boolean);
    function Modified: Boolean;
    // unsaved edits: save them, drop them, or stay. True = go on.
    function AskToSave: Boolean;
    property OnVerify: TVerifyEvent read FOnVerify write FOnVerify;      // Verify drive was confirmed
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;   // a drive map was written
  end;

implementation

uses
  SourceForm;

{$R *.dfm}

constructor TFrameDrives.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLastIndex := -1;
end;

procedure TFrameDrives.SetDrives(const Drives: TOfflineDriveArray; const Settings: TBackupSettings);
var
  I, Select: Integer;
  Keep: Boolean;
begin
  FSettings := Settings;
  Select := -1;
  if (FLastIndex >= 0) and (FLastIndex <= High(FDrives)) then
    for I := 0 to High(Drives) do
      if (Drives[I].Root = FDrives[FLastIndex].Root) and (Drives[I].VolLabel = FDrives[FLastIndex].VolLabel) then
        Select := I;
  Keep := (Select >= 0) and Modified;
  if Select < 0 then
    for I := High(Drives) downto 0 do      // a new drive first, as that is usually why the page is opened
      if not Drives[I].SetUp then Select := I;
  if (Select < 0) and (Length(Drives) > 0) then Select := 0;
  FDrives := Copy(Drives);
  ComboDrives.Items.BeginUpdate;
  try
    ComboDrives.Items.Clear;
    for I := 0 to High(FDrives) do
      ComboDrives.Items.Add(FDrives[I].VolLabel + ' (' + Copy(FDrives[I].Root, 1, 2) + ')');
  finally
    ComboDrives.Items.EndUpdate;
  end;
  ComboDrives.ItemIndex := Select;
  FLastIndex := Select;
  if not Keep then ShowDrive;
  UpdateButtons;
end;

procedure TFrameDrives.SetBusy(Busy: Boolean);
begin
  FBusy := Busy;
  UpdateButtons;
end;

function TFrameDrives.DriveTag: string;
begin
  Result := ComboDrives.Items[FLastIndex];
end;

procedure TFrameDrives.ShowDrive;
var
  I: Integer;
  Item: TListItem;
begin
  ListHistory.Items.Clear;
  if ComboDrives.ItemIndex < 0 then
  begin
    LabelState.Caption := 'No OFFLINE-x drive plugged in. Plug one in to set it up or see what it backs up.';
    EditDescription.Text := '';
    FSetUp := False;
    FList := nil;
    FRemoved := nil;
    ShowFolders;
    FSavedState := StateText;
    Exit;
  end;
  FSetUp := ReadDriveInfo(FDrives[ComboDrives.ItemIndex].Root, FInfo);
  EditDescription.Text := FInfo.Description;
  if FSetUp then
  begin
    if FInfo.HasList then LabelState.Caption := 'Set up ' + FInfo.Created + '.  Drive id ' + FInfo.Id
    else LabelState.Caption := 'Set up ' + FInfo.Created + ', but no folders chosen yet - add them and Save. Nothing is copied before that.';
    ButtonApply.Caption := 'Save';
    FList := Copy(FInfo.Sources);
  end
  else
  begin
    LabelState.Caption := 'New drive - add the folders it should back up, then set it up. Nothing is copied before that.';
    ButtonApply.Caption := 'Set up this drive';
    FList := nil;
  end;
  FRemoved := Copy(FInfo.Removed);
  ShowFolders;

  ListHistory.Items.BeginUpdate;
  try
    for I := High(FInfo.Runs) downto 0 do      // newest first
    begin
      Item := ListHistory.Items.Add;
      Item.Caption := FInfo.Runs[I].When;
      Item.SubItems.Add(FInfo.Runs[I].Result);
      Item.SubItems.Add(FormatSize(FInfo.Runs[I].Bytes));
      Item.SubItems.Add(FInfo.Runs[I].Folders);
      Item.SubItems.Add(FInfo.Runs[I].PC);
    end;
  finally
    ListHistory.Items.EndUpdate;
  end;
  FSavedState := StateText;
end;

{ One row per folder: [x] D:\MUSIC  to  D-mirror\MUSIC }
procedure TFrameDrives.ShowFolders;
var
  I, Sel: Integer;
  Item: TListItem;
begin
  Sel := ListFolders.ItemIndex;
  ListFolders.Items.BeginUpdate;
  try
    ListFolders.Items.Clear;
    for I := 0 to High(FList) do
    begin
      Item := ListFolders.Items.Add;
      Item.Caption := FList[I].Path;
      Item.SubItems.Add('to');
      Item.SubItems.Add(MirrorFolder(FList[I]));
      Item.Checked := FList[I].Enabled;
    end;
  finally
    ListFolders.Items.EndUpdate;
  end;
  if Sel >= ListFolders.Items.Count then Sel := ListFolders.Items.Count - 1;
  if Sel >= 0 then ListFolders.ItemIndex := Sel;
  if Length(FRemoved) > 0 then
    LabelFolderNote.Caption := IntToStr(Length(FRemoved)) + ' folder(s) taken off the list - moved to _versions at the next copy.'
  else
    LabelFolderNote.Caption := 'Unticked folders are not updated but stay on the drive. Remove takes a folder off the drive.';
  UpdateButtons;
end;

procedure TFrameDrives.ReadTicks;
var
  I: Integer;
begin
  for I := 0 to ListFolders.Items.Count - 1 do
    if I <= High(FList) then FList[I].Enabled := ListFolders.Items[I].Checked;
end;

procedure TFrameDrives.UpdateButtons;
var
  Edit: Boolean;
begin
  // not while copying: the run in progress uses the drive maps it read at the start
  Edit := not FBusy and (ComboDrives.ItemIndex >= 0);
  EditDescription.ReadOnly := not Edit;
  ListFolders.Enabled := Edit;
  ButtonAddFolder.Enabled := Edit;
  ButtonStarting.Enabled := Edit;
  ButtonEditFolder.Enabled := Edit and (ListFolders.ItemIndex >= 0);
  ButtonRemoveFolder.Enabled := Edit and (ListFolders.ItemIndex >= 0);
  ButtonApply.Enabled := Edit;
  ButtonUndo.Enabled := Edit;
  ButtonVerify.Enabled := Edit and FSetUp and FInfo.HasList;
  ComboDrives.Enabled := Length(FDrives) > 0;
end;

procedure TFrameDrives.ListFoldersSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

{ Everything Save would write, as text - differs from FSavedState when there are unsaved edits }
function TFrameDrives.StateText: string;
var
  I: Integer;
begin
  ReadTicks;
  Result := Trim(EditDescription.Text) + #1;
  for I := 0 to High(FList) do
    Result := Result + IntToStr(Ord(FList[I].Enabled)) + FList[I].Path + '|' + FList[I].Name + #1;
  for I := 0 to High(FRemoved) do Result := Result + FRemoved[I] + #2;
end;

function TFrameDrives.Modified: Boolean;
begin
  Result := (FLastIndex >= 0) and (StateText <> FSavedState);
end;

procedure TFrameDrives.AddFolder(const Path: string);
var
  N, I: Integer;
begin
  N := Length(FList);
  SetLength(FList, N + 1);
  FList[N].Path := Path;
  FList[N].Name := UniqueSourceName(FList, N, Path, DefaultSourceName(Path));
  FList[N].Enabled := True;
  // added back before the next copy: its copy on the drive stays
  for I := High(FRemoved) downto 0 do
    if SameText(FRemoved[I], MirrorFolder(FList[N])) then Delete(FRemoved, I, 1);
end;

procedure TFrameDrives.ButtonAddFolderClick(Sender: TObject);
var
  Path, Problem: string;
  I: Integer;
begin
  if not FolderDialog.Execute then Exit;
  Path := NormalizeSourcePath(FolderDialog.FileName);
  Problem := SourceProblem(Path);
  for I := 0 to High(FList) do
    if SameText(NormalizeSourcePath(FList[I].Path), Path) then Problem := Path + ' is already on this drive''s list.';
  if Problem <> '' then
  begin
    MessageDlg(Problem, mtWarning, [mbOK], 0);
    Exit;
  end;
  ReadTicks;
  AddFolder(Path);
  ShowFolders;
  ListFolders.ItemIndex := High(FList);
  UpdateButtons;
end;

procedure TFrameDrives.ButtonStartingClick(Sender: TObject);
var
  I, J, Added: Integer;
  Have: Boolean;
begin
  ReadTicks;
  Added := 0;
  for I := 0 to High(FSettings.Sources) do
    if FSettings.Sources[I].Enabled then
    begin
      Have := False;
      for J := 0 to High(FList) do
        if SameText(NormalizeSourcePath(FList[J].Path), NormalizeSourcePath(FSettings.Sources[I].Path)) then Have := True;
      if Have then Continue;
      AddFolder(NormalizeSourcePath(FSettings.Sources[I].Path));
      FList[High(FList)].Name := UniqueSourceName(FList, High(FList), FSettings.Sources[I].Path, FSettings.Sources[I].Name);
      Inc(Added);
    end;
  if Added = 0 then
    MessageDlg('All the starting folders ticked in Settings are already on the list.', mtInformation, [mbOK], 0);
  ShowFolders;
end;

procedure TFrameDrives.ButtonEditFolderClick(Sender: TObject);
var
  I: Integer;
  Old: string;
begin
  I := ListFolders.ItemIndex;
  if (I < 0) or not ButtonEditFolder.Enabled then Exit;
  ReadTicks;
  Old := MirrorFolder(FList[I]);
  if not TFormSource.Execute(Self, FList, I) then Exit;
  // a new folder or name means a new copy on the drive; the old one goes the way of a removed folder
  if FSetUp and not SameText(Old, MirrorFolder(FList[I])) then
  begin
    SetLength(FRemoved, Length(FRemoved) + 1);
    FRemoved[High(FRemoved)] := Old;
  end;
  ShowFolders;
end;

procedure TFrameDrives.ButtonRemoveFolderClick(Sender: TObject);
var
  I: Integer;
begin
  I := ListFolders.ItemIndex;
  if I < 0 then Exit;
  ReadTicks;
  if FSetUp and (MessageDlg('Take ' + FList[I].Path + ' off this drive''s list?' + sLineBreak + sLineBreak +
    'At the next copy its copy on the drive (' + MirrorFolder(FList[I]) + ') is moved to _versions, and cleared out ' +
    'after ' + IntToStr(FSettings.KeepVersionDays) + ' days (sooner if the drive gets full).' + sLineBreak + sLineBreak +
    'To keep it on the drive but stop updating it, untick it instead.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  if FSetUp then
  begin
    SetLength(FRemoved, Length(FRemoved) + 1);
    FRemoved[High(FRemoved)] := MirrorFolder(FList[I]);
  end;
  Delete(FList, I, 1);
  ShowFolders;
end;

procedure TFrameDrives.ButtonVerifyClick(Sender: TObject);
begin
  if not AskToSave then Exit;
  if MessageDlg('Verify ' + DriveTag + '?' + sLineBreak + sLineBreak +
    'Every file in the drive''s folders is read back from the drive and checked against the CRC32 recorded when ' +
    'it was copied. Files copied before checksums were kept get one now, and are checked from then on. ' +
    'A large drive takes a while; you can cancel it.' + sLineBreak + sLineBreak +
    'Nothing is changed except the checksum lists - and the date of any bad file, so the next copy replaces it.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  if Assigned(FOnVerify) then FOnVerify(FDrives[ComboDrives.ItemIndex]);
end;

procedure TFrameDrives.ComboDrivesChange(Sender: TObject);
var
  I: Integer;
begin
  if ComboDrives.ItemIndex = FLastIndex then Exit;
  I := ComboDrives.ItemIndex;
  ComboDrives.ItemIndex := FLastIndex;           // unsaved edits belong to the drive shown so far
  if not AskToSave then Exit;
  ComboDrives.ItemIndex := I;
  FLastIndex := I;
  ShowDrive;
end;

function TFrameDrives.AskToSave: Boolean;
begin
  Result := True;
  if not Modified then Exit;
  if not FSetUp then
    case MessageDlg(DriveTag + ' is not set up yet. Set it up now?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes: Result := Apply;
      mrNo: ShowDrive;                           // drop the edits, so they don't come back later
    else
      Result := False;
    end
  else
    case MessageDlg('Save the changes for ' + DriveTag + '?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes: Result := Apply;
      mrNo: ShowDrive;
    else
      Result := False;
    end;
end;

procedure TFrameDrives.ButtonApplyClick(Sender: TObject);
begin
  Apply;
end;

procedure TFrameDrives.ButtonUndoClick(Sender: TObject);
begin
  if not Modified then Exit;
  if MessageDlg('Undo the changes for ' + DriveTag + ' since it was last saved?', mtConfirmation, [mbYes, mbNo], 0) =
    mrYes then ShowDrive;
end;

function TFrameDrives.Apply: Boolean;
var
  D: TOfflineDrive;
  Plugged: TOfflineDriveArray;
  I: Integer;
  Still: Boolean;
begin
  Result := False;
  if ComboDrives.ItemIndex < 0 then Exit;
  D := FDrives[ComboDrives.ItemIndex];
  ReadTicks;
  if Trim(EditDescription.Text) = '' then
  begin
    MessageDlg('Type a few words about what this drive is for, e.g. "Music and pictures".', mtInformation, [mbOK], 0);
    PageDrive.ActivePage := TabFolders;
    EditDescription.SetFocus;
    Exit;
  end;
  if Length(FList) = 0 then
  begin
    MessageDlg('Add at least one folder for this drive to back up.', mtInformation, [mbOK], 0);
    PageDrive.ActivePage := TabFolders;
    Exit;
  end;
  // the drive must still be there with the same label
  Plugged := FindOfflineDrives;
  Still := False;
  for I := 0 to High(Plugged) do
    if (Plugged[I].Root = D.Root) and (Plugged[I].VolLabel = D.VolLabel) then Still := True;
  if not Still then
  begin
    MessageDlg(DriveTag + ' is not plugged in any more.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if not FSetUp then
  begin
    if MessageDlg('Set up ' + DriveTag + '?' + sLineBreak + sLineBreak +
      'This writes ' + DriveMapName + ' to the drive: which drive it is, what it is for, the folders it backs up, ' +
      'and later its history. Nothing else on the drive is changed. After that, Start copy includes this drive.',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    FInfo := NewDriveInfo(D.VolLabel, EditDescription.Text);
  end
  else
    FInfo.Description := Trim(EditDescription.Text);
  FInfo.HasList := True;
  FInfo.Sources := Copy(FList);
  FInfo.Removed := Copy(FRemoved);
  if not WriteDriveInfo(D.Root, FInfo) then
  begin
    MessageDlg('Could not write ' + DriveMapName + ' to ' + DriveTag + '.', mtError, [mbOK], 0);
    Exit;
  end;
  ShowDrive;
  Result := True;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

end.
