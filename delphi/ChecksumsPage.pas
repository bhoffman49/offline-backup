unit ChecksumsPage;

{ Checksums area of the Delphi VCL main window: pick a folder, choose an algorithm and a list format, and Make
  checksums writes a list of every file's checksum into that folder - and, if ticked, a small checksum program next
  to it that checks the files on any PC. The work is done by Checksums (common), on its own thread; this page shows
  its progress. The Lazarus edition has the same page in ..\lazarus\ChecksumsPage.pas. }

interface

uses
  Windows, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, CommCtrl,
  ShellAPI, OfflineEngine, Hashes, Digests, Checksums;

type
  TCheckListEvent = procedure(const ListFile: string) of object;

  TFrameChecksums = class(TFrame)
    PanelActions: TPanel;
    ButtonFolder: TButton;
    ButtonMake: TButton;
    ButtonCancel: TButton;
    ButtonCheckList: TButton;
    ButtonShow: TButton;
    PanelMain: TPanel;
    LabelIntro: TLabel;
    LabelFolderCaption: TLabel;
    LabelFolder: TLabel;
    CheckSub: TCheckBox;
    LabelCount: TLabel;
    ListFiles: TListView;
    ButtonLeaveOut: TButton;
    LabelAlgo: TLabel;
    ComboAlgo: TComboBox;
    LabelFormat: TLabel;
    ComboFormat: TComboBox;
    CheckProgram: TCheckBox;
    LabelName: TLabel;
    EditName: TEdit;
    ButtonIcon: TButton;
    ButtonDefaultIcon: TButton;
    PaintIcon: TPaintBox;
    LabelOutput: TLabel;
    ProgressBar: TProgressBar;
    LabelStatus: TLabel;
    FolderDialog: TFileOpenDialog;
    IconDialog: TOpenDialog;
    Timer: TTimer;
    procedure ButtonFolderClick(Sender: TObject);
    procedure ButtonMakeClick(Sender: TObject);
    procedure ButtonCancelClick(Sender: TObject);
    procedure ButtonCheckListClick(Sender: TObject);
    procedure ButtonShowClick(Sender: TObject);
    procedure CheckSubClick(Sender: TObject);
    procedure ListFilesData(Sender: TObject; Item: TListItem);
    procedure ListFilesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListFilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonLeaveOutClick(Sender: TObject);
    procedure ComboAlgoChange(Sender: TObject);
    procedure ComboFormatChange(Sender: TObject);
    procedure CheckProgramClick(Sender: TObject);
    procedure EditNameChange(Sender: TObject);
    procedure ButtonIconClick(Sender: TObject);
    procedure ButtonDefaultIconClick(Sender: TObject);
    procedure PaintIconPaint(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
  private
    FFolder: string;
    FFiles: TMakeFiles;
    FFormats: array of TDigestFormat;    // the formats ComboFormat offers, in its order
    FIconFile: string;                   // '' = the built-in icon
    FIcon: HICON;
    FJob: TChecksumJob;
    FThread: TChecksumThread;
    FListPath: string;                   // the list made last, for Check the list
    FBusy: Boolean;                      // a copy, verify or check runs in the main window
    FOnCheck: TCheckListEvent;
    FOnRunningChange: TNotifyEvent;
    procedure Rescan;
    procedure FillFormats;
    function Options: TMakeOptions;
    procedure UpdateOutput;
    procedure UpdateButtons;
    procedure LoadIcon;
    procedure Finish;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetBusy(Busy: Boolean);
    function Running: Boolean;           // checksums are being made now
    procedure Cancel;
    property OnCheck: TCheckListEvent read FOnCheck write FOnCheck;          // check this list now (MD5 check page)
    property OnRunningChange: TNotifyEvent read FOnRunningChange write FOnRunningChange;
  end;

implementation

{$R *.dfm}

const
  FormatTexts: array[TDigestFormat] of string = ('md5sum (Linux and other GNU tools)',
    'sha1sum (Linux and other GNU tools)', 'SFV', 'FileCheckMD5', 'hash *name - like ExactFile and Offline Backup');

constructor TFrameChecksums.Create(AOwner: TComponent);
var
  A: THashAlgo;
begin
  inherited Create(AOwner);
  for A := Low(THashAlgo) to High(THashAlgo) do ComboAlgo.Items.Add(HashNames[A]);
  ComboAlgo.ItemIndex := Ord(haMD5);
  EditName.Text := DefaultBaseName;
  FillFormats;
  LoadIcon;
  UpdateOutput;
  UpdateButtons;
end;

destructor TFrameChecksums.Destroy;
begin
  Cancel;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
  end;
  FJob.Free;
  if FIcon <> 0 then DestroyIcon(FIcon);
  inherited Destroy;
end;

function TFrameChecksums.Running: Boolean;
begin
  Result := FThread <> nil;
end;

procedure TFrameChecksums.Cancel;
begin
  if FJob <> nil then FJob.Cancel;
end;

procedure TFrameChecksums.SetBusy(Busy: Boolean);
begin
  FBusy := Busy;
  UpdateButtons;
end;

procedure TFrameChecksums.UpdateButtons;
var
  Idle: Boolean;
begin
  Idle := not Running;
  ButtonFolder.Enabled := Idle;
  ButtonMake.Enabled := Idle and not FBusy and (Length(FFiles) > 0) and (NormalizeBaseName(EditName.Text) <> '');
  ButtonCancel.Enabled := Running;
  ButtonCheckList.Enabled := Idle and not FBusy and (FListPath <> '') and FileExists(FListPath);
  ButtonShow.Enabled := FFolder <> '';
  CheckSub.Enabled := Idle and (FFolder <> '');
  ButtonLeaveOut.Enabled := Idle and (ListFiles.SelCount > 0);
  ComboAlgo.Enabled := Idle;
  ComboFormat.Enabled := Idle;
  CheckProgram.Enabled := Idle;
  EditName.Enabled := Idle;
  ButtonIcon.Enabled := Idle and CheckProgram.Checked;
  ButtonDefaultIcon.Enabled := Idle and CheckProgram.Checked and (FIconFile <> '');
end;

{ Lists the folder's files again (after a new folder, the subfolders tick or a new name) }
procedure TFrameChecksums.Rescan;
var
  Total: Int64;
  I: Integer;
begin
  if FFolder = '' then Exit;
  Screen.Cursor := crHourGlass;
  try
    FFiles := ScanFolder(FFolder, CheckSub.Checked, NormalizeBaseName(EditName.Text));
  finally
    Screen.Cursor := crDefault;
  end;
  Total := 0;
  for I := 0 to High(FFiles) do Inc(Total, FFiles[I].Size);
  if Length(FFiles) = 0 then LabelCount.Caption := 'No files in this folder'
  else if Length(FFiles) = 1 then LabelCount.Caption := '1 file, ' + FormatSize(Total)
  else LabelCount.Caption := FormatFloat('#,##0', Length(FFiles)) + ' files, ' + FormatSize(Total);
  ListFiles.Items.Count := Length(FFiles);
  ListFiles.Invalidate;
  UpdateOutput;
  UpdateButtons;
end;

procedure TFrameChecksums.ButtonFolderClick(Sender: TObject);
begin
  if Running then Exit;
  if FFolder <> '' then FolderDialog.DefaultFolder := FFolder;
  if not FolderDialog.Execute then Exit;
  FFolder := ExcludeTrailingPathDelimiter(FolderDialog.FileName);
  if Length(FFolder) = 2 then FFolder := FFolder + '\';      // a drive's root: E:\
  LabelFolder.Caption := FFolder;
  LabelFolder.Hint := FFolder;
  FListPath := '';
  LabelStatus.Caption := '';
  ProgressBar.Position := 0;
  Rescan;
end;

procedure TFrameChecksums.CheckSubClick(Sender: TObject);
begin
  Rescan;
end;

procedure TFrameChecksums.ListFilesData(Sender: TObject; Item: TListItem);
begin
  if Item.Index > High(FFiles) then Exit;
  Item.SubItems.Clear;
  Item.Caption := FFiles[Item.Index].RelName;
  Item.SubItems.Add(FormatSize(FFiles[Item.Index].Size));
end;

{ Leaves the selected files out of the list (the files themselves are not touched) }
procedure TFrameChecksums.ButtonLeaveOutClick(Sender: TObject);
var
  I, N: Integer;
  Keep: array of Boolean;
begin
  if Running or (Length(FFiles) = 0) then Exit;
  SetLength(Keep, Length(FFiles));
  for I := 0 to High(Keep) do Keep[I] := True;
  I := ListView_GetNextItem(ListFiles.Handle, -1, LVNI_SELECTED);
  while I >= 0 do
  begin
    if I <= High(Keep) then Keep[I] := False;
    I := ListView_GetNextItem(ListFiles.Handle, I, LVNI_SELECTED);
  end;
  N := 0;
  for I := 0 to High(FFiles) do
    if Keep[I] then
    begin
      FFiles[N] := FFiles[I];
      Inc(N);
    end;
  SetLength(FFiles, N);
  ListFiles.ClearSelection;
  ListFiles.Items.Count := N;
  ListFiles.Invalidate;
  LabelCount.Caption := FormatFloat('#,##0', N) + ' file(s) - some left out';
  UpdateButtons;
end;

procedure TFrameChecksums.ListFilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  ButtonLeaveOut.Enabled := not Running and (ListFiles.SelCount > 0);
end;

procedure TFrameChecksums.ListFilesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_DELETE then
  begin
    ButtonLeaveOutClick(Sender);
    Key := 0;
  end
  else
    UpdateButtons;
end;

{ The formats that can hold the chosen algorithm's checksums; the one chosen before stays if it still can }
procedure TFrameChecksums.FillFormats;
var
  F, Old: TDigestFormat;
  A: THashAlgo;
  I: Integer;
begin
  A := THashAlgo(ComboAlgo.ItemIndex);
  Old := dfFSum;
  if ComboFormat.ItemIndex >= 0 then Old := FFormats[ComboFormat.ItemIndex];
  ComboFormat.Items.Clear;
  FFormats := nil;
  for F := Low(TDigestFormat) to High(TDigestFormat) do
    if FormatSupports(F, A) then
    begin
      SetLength(FFormats, Length(FFormats) + 1);
      FFormats[High(FFormats)] := F;
      ComboFormat.Items.Add(FormatTexts[F]);
    end;
  // the one chosen before if it fits, else hash *name (fsum): it fits every algorithm, and it is the last one
  ComboFormat.ItemIndex := High(FFormats);
  for I := 0 to High(FFormats) do
    if FFormats[I] = Old then ComboFormat.ItemIndex := I;
end;

function TFrameChecksums.Options: TMakeOptions;
begin
  Result := Default(TMakeOptions);
  Result.Folder := FFolder;
  Result.BaseName := NormalizeBaseName(EditName.Text);
  Result.MakeProgram := CheckProgram.Checked;
  Result.IconFile := FIconFile;
  Result.Algo := THashAlgo(ComboAlgo.ItemIndex);
  if ComboFormat.ItemIndex >= 0 then Result.Format := FFormats[ComboFormat.ItemIndex] else Result.Format := dfFSum;
end;

{ What Make checksums will write, and whether it replaces something }
procedure TFrameChecksums.UpdateOutput;
var
  O: TMakeOptions;
  S: string;
  Replaces: Boolean;
begin
  O := Options;
  if O.BaseName = '' then
  begin
    LabelOutput.Caption := 'That name cannot be used for a file.';
    LabelOutput.Font.Color := clRed;
    Exit;
  end;
  LabelOutput.Font.Color := clWindowText;
  S := 'Writes ' + ListFileName(O);
  if O.MakeProgram then S := S + ' and ' + ProgramFileName(O);
  if FFolder = '' then S := S + ' into the folder you choose.'
  else
  begin
    // the folder's name only: the whole path is on the Folder line above, and a long one would be cut off here
    if ExtractFileName(ExcludeTrailingPathDelimiter(FFolder)) <> '' then
      S := S + ' into ' + ExtractFileName(ExcludeTrailingPathDelimiter(FFolder))
    else
      S := S + ' into ' + FFolder;          // a drive's root, such as E:\
    Replaces := FileExists(IncludeTrailingPathDelimiter(FFolder) + ListFileName(O)) or
      (O.MakeProgram and FileExists(IncludeTrailingPathDelimiter(FFolder) + ProgramFileName(O)));
    if Replaces then S := S + ' (replacing what is there now)';
    S := S + '.';
  end;
  LabelOutput.Caption := S;
end;

procedure TFrameChecksums.ComboAlgoChange(Sender: TObject);
begin
  FillFormats;
  UpdateOutput;
end;

procedure TFrameChecksums.ComboFormatChange(Sender: TObject);
begin
  UpdateOutput;
end;

procedure TFrameChecksums.CheckProgramClick(Sender: TObject);
begin
  UpdateOutput;
  UpdateButtons;
end;

procedure TFrameChecksums.EditNameChange(Sender: TObject);
begin
  UpdateOutput;
  UpdateButtons;
end;

procedure TFrameChecksums.LoadIcon;
var
  Ico: TBytes;
begin
  if FIcon <> 0 then DestroyIcon(FIcon);
  FIcon := 0;
  if FIconFile <> '' then Ico := ReadIconFile(FIconFile) else Ico := DefaultProgramIcon;
  FIcon := IconHandle(Ico, PaintIcon.Width);
  PaintIcon.Invalidate;
end;

procedure TFrameChecksums.PaintIconPaint(Sender: TObject);
begin
  if FIcon <> 0 then
    DrawIconEx(PaintIcon.Canvas.Handle, 0, 0, FIcon, PaintIcon.Width, PaintIcon.Height, 0, 0, DI_NORMAL);
end;

procedure TFrameChecksums.ButtonIconClick(Sender: TObject);
begin
  if not IconDialog.Execute then Exit;
  if ReadIconFile(IconDialog.FileName) = nil then
  begin
    MessageDlg(IconDialog.FileName + ' is not an icon file (.ico) this can use.', mtWarning, [mbOK], 0);
    Exit;
  end;
  FIconFile := IconDialog.FileName;
  PaintIcon.Hint := FIconFile;
  LoadIcon;
  UpdateButtons;
end;

procedure TFrameChecksums.ButtonDefaultIconClick(Sender: TObject);
begin
  FIconFile := '';
  PaintIcon.Hint := 'The built-in icon';
  LoadIcon;
  UpdateButtons;
end;

procedure TFrameChecksums.ButtonMakeClick(Sender: TObject);
var
  O: TMakeOptions;
  Root, Names: string;
  I, N: Integer;
begin
  if Running or FBusy then Exit;
  O := Options;
  if (O.BaseName = '') or (Length(FFiles) = 0) then Exit;
  // the name may have changed since the folder was read: its earlier list and program are not listed
  N := 0;
  for I := 0 to High(FFiles) do
    if not IsMakerOutput(FFiles[I].RelName, O.BaseName) then
    begin
      FFiles[N] := FFiles[I];
      Inc(N);
    end;
  if N < Length(FFiles) then
  begin
    SetLength(FFiles, N);
    ListFiles.Items.Count := N;
    ListFiles.Invalidate;
  end;
  if N = 0 then Exit;
  if not DirectoryExists(FFolder) then
  begin
    MessageDlg(FFolder + ' is not there any more.', mtWarning, [mbOK], 0);
    Exit;
  end;
  Root := IncludeTrailingPathDelimiter(FFolder);
  Names := '';
  if FileExists(Root + ListFileName(O)) then Names := ListFileName(O);
  if O.MakeProgram and FileExists(Root + ProgramFileName(O)) then
  begin
    if Names <> '' then Names := Names + ' and ';
    Names := Names + ProgramFileName(O);
  end;
  if (Names <> '') and (MessageDlg(FFolder + ' already has ' + Names + '. Replace it?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes) then Exit;
  FListPath := '';
  ProgressBar.Position := 0;
  LabelStatus.Font.Color := clWindowText;
  LabelStatus.Caption := 'Reading the files ...';
  FJob := TChecksumJob.Create(O, FFiles);
  FThread := TChecksumThread.Create(FJob);
  Timer.Enabled := True;
  UpdateButtons;
  if Assigned(FOnRunningChange) then FOnRunningChange(Self);
end;

procedure TFrameChecksums.ButtonCancelClick(Sender: TObject);
begin
  Cancel;
  LabelStatus.Caption := 'Cancelling ...';
end;

procedure TFrameChecksums.TimerTimer(Sender: TObject);
var
  I: Integer;
begin
  if FJob = nil then
  begin
    Timer.Enabled := False;
    Exit;
  end;
  if FJob.BytesTotal > 0 then ProgressBar.Position := Round(FJob.BytesDone / FJob.BytesTotal * 1000);
  I := FJob.FileIndex;
  if not FJob.Cancelled and (I >= 0) and (I <= High(FJob.Files)) then
    LabelStatus.Caption := Format('Reading file %s of %s (%s of %s):  %s', [FormatFloat('#,##0', I + 1),
      FormatFloat('#,##0', Length(FJob.Files)), FormatSize(FJob.BytesDone), FormatSize(FJob.BytesTotal),
      FJob.Files[I].RelName]);
  if FThread.Finished then Finish;
end;

{ The job ended: say how, and get ready for the next }
procedure TFrameChecksums.Finish;
var
  S: string;
  Secs: Double;
begin
  Timer.Enabled := False;
  FThread.WaitFor;
  FreeAndNil(FThread);
  case FJob.Outcome of
    mkDone:
      begin
        ProgressBar.Position := 1000;
        FListPath := FJob.ListPath;
        S := 'Done: ' + ExtractFileName(FJob.ListPath);
        if FJob.ExePath <> '' then S := S + ' and ' + ExtractFileName(FJob.ExePath);
        Secs := (FJob.Finished - FJob.Started) * 86400;
        S := S + ' written - ' + FormatFloat('#,##0', Length(FJob.Files)) + ' files, ' + FormatSize(FJob.BytesTotal) +
          ' in ' + FormatDuration(Round(Secs)) + '.';
        if FJob.ExePath <> '' then
          S := S + ' Copy the folder anywhere with them in it, and ' + ExtractFileName(FJob.ExePath) +
            ' checks its files.';
        LabelStatus.Font.Color := clGreen;
      end;
    mkCancelled:
      begin
        S := 'Cancelled - nothing was written.';
        LabelStatus.Font.Color := clWindowText;
      end;
  else
    begin
      S := FJob.ErrorText;
      LabelStatus.Font.Color := clRed;
    end;
  end;
  LabelStatus.Caption := S;
  FreeAndNil(FJob);
  UpdateOutput;
  UpdateButtons;
  if Assigned(FOnRunningChange) then FOnRunningChange(Self);
end;

procedure TFrameChecksums.ButtonCheckListClick(Sender: TObject);
begin
  if (FListPath <> '') and Assigned(FOnCheck) then FOnCheck(FListPath);
end;

procedure TFrameChecksums.ButtonShowClick(Sender: TObject);
begin
  if FListPath <> '' then
    ShellExecuteW(0, 'open', 'explorer.exe', PWideChar(UnicodeString('/select,"' + FListPath + '"')), nil,
      SW_SHOWNORMAL)
  else if FFolder <> '' then
    ShellExecuteW(0, 'open', PWideChar(UnicodeString(FFolder)), nil, nil, SW_SHOWNORMAL);
end;

end.
