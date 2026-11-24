unit SourceForm;

{ Edit one backup source: the folder, the name it gets on the OFFLINE drive and - for a drive's own folder - whether
  its changed and deleted files are archived (ARCHIVE\MMDDYY). Delphi VCL edition;
  the Lazarus edition has the same form in ..\lazarus\SourceForm.pas. }

interface

uses
  Windows, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls,
  OfflineEngine;

type
  TFormSource = class(TForm)
    LabelPath: TLabel;
    EditPath: TEdit;
    ButtonBrowse: TButton;
    LabelName: TLabel;
    EditName: TEdit;
    LabelLands: TLabel;
    LabelNote: TLabel;
    CheckArchive: TCheckBox;
    ButtonOK: TButton;
    ButtonCancel: TButton;
    FolderDialog: TFileOpenDialog;
    procedure ButtonBrowseClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure ButtonOKClick(Sender: TObject);
  private
    FSources: TBackupSourceArray;
    FIndex: Integer;
    FHadArchive: Boolean;       // the folder was archived when the window opened
  public
    // edits Sources[Index] in place; False if cancelled. ShowArchive: also the archive tick (a drive's folder)
    class function Execute(AOwner: TComponent; var Sources: TBackupSourceArray; Index: Integer;
      ShowArchive: Boolean = False): Boolean;
  end;

// shared by the Add button: is this folder one that can be backed up? '' if so, else the reason
function SourceProblem(const Path: string): string;

implementation

{$R *.dfm}

function SourceProblem(const Path: string): string;
var
  Drives: TOfflineDriveArray;
  I: Integer;
begin
  Result := '';
  if SourceLetter(Path) = #0 then
    Exit('Choose a folder on a drive letter, like D:\MUSIC. Network folders are not supported.');
  Drives := FindOfflineDrives;
  for I := 0 to High(Drives) do
    if Drives[I].Letter = SourceLetter(Path) then
      Exit(Copy(Path, 1, 2) + ' is an OFFLINE drive - it can''t be backed up onto itself.');
end;

class function TFormSource.Execute(AOwner: TComponent; var Sources: TBackupSourceArray; Index: Integer;
  ShowArchive: Boolean): Boolean;
var
  F: TFormSource;
begin
  F := TFormSource.Create(AOwner);
  try
    F.FSources := Sources;
    F.FIndex := Index;
    F.EditPath.Text := Sources[Index].Path;
    F.EditName.Text := Sources[Index].Name;
    F.FHadArchive := not Sources[Index].NoArchive;
    F.CheckArchive.Checked := F.FHadArchive;
    if not ShowArchive then
    begin
      // Settings' starting folders: the switch belongs to each drive's own list
      F.CheckArchive.Visible := False;
      F.ClientHeight := F.ClientHeight - 34;
    end;
    Result := F.ShowModal = mrOk;
    if Result then
    begin
      Sources[Index].Path := NormalizeSourcePath(F.EditPath.Text);
      Sources[Index].Name := UniqueSourceName(Sources, Index, Sources[Index].Path, Trim(F.EditName.Text));
      if ShowArchive then Sources[Index].NoArchive := not F.CheckArchive.Checked;
    end;
  finally
    F.Free;
  end;
end;

procedure TFormSource.ButtonBrowseClick(Sender: TObject);
begin
  FolderDialog.DefaultFolder := NormalizeSourcePath(EditPath.Text);
  if not FolderDialog.Execute then Exit;
  // the name follows the folder unless it was changed by hand
  if (EditName.Text = '') or (EditName.Text = DefaultSourceName(EditPath.Text)) then
    EditName.Text := DefaultSourceName(FolderDialog.FileName);
  EditPath.Text := NormalizeSourcePath(FolderDialog.FileName);
end;

procedure TFormSource.EditChange(Sender: TObject);
var
  S: TBackupSource;
begin
  S.Path := NormalizeSourcePath(EditPath.Text);
  S.Name := UniqueSourceName(FSources, FIndex, S.Path, Trim(EditName.Text));
  if (SourceLetter(S.Path) = #0) or not ValidSourceName(S.Name) then LabelLands.Caption := 'Goes to: -'
  else LabelLands.Caption := 'Goes to: OFFLINE-x:\' + MirrorFolder(S);
end;

procedure TFormSource.ButtonOKClick(Sender: TObject);
var
  Path, Problem: string;
begin
  Path := NormalizeSourcePath(EditPath.Text);
  Problem := SourceProblem(Path);
  if Problem = '' then
    if not ValidSourceName(Trim(EditName.Text)) then
      Problem := 'The name on the drive can''t be empty or contain \ / : * ? " < > |, or end in a dot.';
  if Problem <> '' then
  begin
    MessageDlg(Problem, mtWarning, [mbOK], 0);
    Exit;
  end;
  if not DirectoryExists(Path) and (MessageDlg(Path + ' does not exist at the moment. Keep it anyway?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  if CheckArchive.Visible and FHadArchive and not CheckArchive.Checked and (MessageDlg('Without the archive, ' +
    'a copy replaces and deletes this folder''s files on the drive straight away. A file that was damaged or ' +
    'deleted on the PC then can''t be got back from this drive. Switch the archive off for this folder?',
    mtWarning, [mbYes, mbNo], 0) <> mrYes) then Exit;
  ModalResult := mrOk;
end;

end.
