unit CheckPage;

{ MD5 check area of the Lazarus/LCL main window: pick an .md5 file to check, then see how many of its files match, are
  bad, missing or unreadable, and the files of each. The check itself runs in the main window, which shows its
  progress under Backup. The Delphi edition has the same page in ..\delphi\CheckPage.pas. }

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  OfflineEngine;

type
  TCheckFileEvent = procedure(const Md5File: string) of object;

  TFrameCheck = class(TFrame)
    PanelActions: TPanel;
    ButtonOpen: TButton;
    ButtonAgain: TButton;
    PageCheck: TPageControl;
    TabSummary: TTabSheet;
    LabelFile: TLabel;
    LabelResult: TLabel;
    ListSummary: TListView;
    LabelPick: TLabel;
    TabFiles: TTabSheet;
    LabelFiles: TLabel;
    ListFiles: TListView;
    Md5Dialog: TOpenDialog;
    PanelRecord: TPanel;
    CheckRecord: TCheckBox;
    LabelRecordNote: TLabel;
    procedure ButtonOpenClick(Sender: TObject);
    procedure CheckRecordClick(Sender: TObject);
    procedure ButtonAgainClick(Sender: TObject);
    procedure ListSummarySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListSummaryDblClick(Sender: TObject);
    procedure ListFilesData(Sender: TObject; Item: TListItem);
  private
    FItems: TCheckItems;
    FShown: array of Integer;     // indexes into FItems for the rows of ListFiles
    FMd5File: string;             // the file checked last, for Check again
    FBusy: Boolean;
    FDrives: TOfflineDriveArray;  // OFFLINE drives plugged in, for where Open MD5 file starts
    FOnCheck: TCheckFileEvent;
    FOnRecordChange: TNotifyEvent;
    FSetting: Boolean;            // SetRecordChecksums is setting the tick: not a change by the user
    function Md5Folder: string;
    procedure ShowStatus(Row: Integer);
    procedure UpdateButtons;
  public
    procedure ShowResult(const Md5File: string; const Items: TCheckItems; R: TCopyResult);
    procedure SetBusy(Busy: Boolean);
    procedure SetDrives(const Drives: TOfflineDriveArray);
    // the 'record checksums after each copy' setting, shown on this page
    procedure SetRecordChecksums(Value: Boolean);
    function RecordChecksums: Boolean;
    // asks for an .md5 file and checks it
    procedure OpenFile;
    property OnCheck: TCheckFileEvent read FOnCheck write FOnCheck;      // check this file now
    property OnRecordChange: TNotifyEvent read FOnRecordChange write FOnRecordChange;   // the tick was changed
  end;

implementation

{$R *.lfm}

const
  RowNames: array[TCheckStatus] of string = ('Match', 'BAD - do not match their MD5', 'Missing', 'Could not be read');

procedure TFrameCheck.ShowResult(const Md5File: string; const Items: TCheckItems; R: TCopyResult);
var
  St: TCheckStatus;
  Count: array[TCheckStatus] of Integer;
  Bytes: array[TCheckStatus] of Int64;
  I: Integer;
  Item: TListItem;
begin
  FItems := Items;
  FMd5File := Md5File;
  // the name first: a long folder is cut off at the window's edge, and the hint has all of it
  LabelFile.Caption := ExtractFileName(Md5File) + '   in ' + ExtractFileDir(Md5File);
  LabelFile.Hint := Md5File;
  LabelFile.ShowHint := True;
  for St := Low(TCheckStatus) to High(TCheckStatus) do
  begin
    Count[St] := 0;
    Bytes[St] := 0;
  end;
  for I := 0 to High(Items) do
  begin
    Inc(Count[Items[I].Status]);
    if Items[I].Size > 0 then Inc(Bytes[Items[I].Status], Items[I].Size);
  end;
  LabelResult.Font.Color := clWindowText;
  if R = crCancelled then
    LabelResult.Caption := 'Cancelled - these are the files checked so far.'
  else if R = crOk then
    LabelResult.Caption := 'All ' + FormatFloat('#,##0', Length(Items)) + ' files match.'
  else
  begin
    LabelResult.Caption := 'Some files do not match, are missing or could not be read - see the Files tab.';
    LabelResult.Font.Color := clRed;
  end;
  ListSummary.Items.BeginUpdate;
  try
    ListSummary.Items.Clear;
    for St := Low(TCheckStatus) to High(TCheckStatus) do
    begin
      Item := ListSummary.Items.Add;
      Item.Caption := RowNames[St];
      Item.SubItems.Add(FormatFloat('#,##0', Count[St]));
      if St = csMissing then Item.SubItems.Add('-') else Item.SubItems.Add(FormatSize(Bytes[St]));
      Item.Data := Pointer(Ord(St) + 1);
    end;
    Item := ListSummary.Items.Add;
    Item.Caption := 'All files';
    Item.SubItems.Add(FormatFloat('#,##0', Length(Items)));
    Item.SubItems.Add('');
    Item.Data := nil;
  finally
    ListSummary.Items.EndUpdate;
  end;
  LabelPick.Visible := True;
  // the Files tab opens on the problems if there are any, else on everything
  I := ListSummary.Items.Count - 1;
  if Count[csBad] > 0 then I := Ord(csBad)
  else if Count[csMissing] > 0 then I := Ord(csMissing)
  else if Count[csUnreadable] > 0 then I := Ord(csUnreadable);
  ListSummary.ItemIndex := I;
  ShowStatus(I);
  PageCheck.ActivePage := TabSummary;
  UpdateButtons;
end;

procedure TFrameCheck.SetBusy(Busy: Boolean);
begin
  FBusy := Busy;
  UpdateButtons;
end;

procedure TFrameCheck.UpdateButtons;
begin
  // one thing at a time: not while a copy, verify or check is running
  ButtonOpen.Enabled := not FBusy;
  ButtonAgain.Enabled := not FBusy and (FMd5File <> '');
  CheckRecord.Enabled := not FBusy;      // a copy that is running keeps the setting it started with
end;

procedure TFrameCheck.SetRecordChecksums(Value: Boolean);
begin
  FSetting := True;
  try
    CheckRecord.Checked := Value;
  finally
    FSetting := False;
  end;
end;

function TFrameCheck.RecordChecksums: Boolean;
begin
  Result := CheckRecord.Checked;
end;

procedure TFrameCheck.CheckRecordClick(Sender: TObject);
begin
  if not FSetting and Assigned(FOnRecordChange) then FOnRecordChange(Self);
end;

procedure TFrameCheck.SetDrives(const Drives: TOfflineDriveArray);
begin
  FDrives := Copy(Drives);
end;

{ Where Open MD5 file starts: the first OFFLINE drive that has been set up - in its mirror folder, where the .md5 files
  are, if it has just one (C-mirror), else at its root. '' with no such drive, so the dialog opens where it did last. }
function TFrameCheck.Md5Folder: string;
var
  I, Found: Integer;
  SR: TSearchRec;
begin
  Result := '';
  for I := 0 to High(FDrives) do
    if FDrives[I].SetUp then
    begin
      Result := FDrives[I].Root;
      Break;
    end;
  if Result = '' then Exit;
  Found := 0;
  if FindFirst(Result + '*-mirror', faDirectory, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) <> 0 then
      begin
        Inc(Found);
        if Found = 1 then Result := Result + SR.Name
        else Result := ExtractFileDrive(Result) + '';
      end;
    until (Found > 1) or (FindNext(SR) <> 0);
    FindClose(SR);
  end;
end;

procedure TFrameCheck.OpenFile;
begin
  if FBusy then Exit;
  Md5Dialog.InitialDir := Md5Folder;
  if not Md5Dialog.Execute then Exit;
  if Assigned(FOnCheck) then FOnCheck(Md5Dialog.FileName);
end;

procedure TFrameCheck.ButtonOpenClick(Sender: TObject);
begin
  OpenFile;
end;

procedure TFrameCheck.ButtonAgainClick(Sender: TObject);
begin
  if FBusy or (FMd5File = '') then Exit;
  if Assigned(FOnCheck) then FOnCheck(FMd5File);
end;

{ Fills the file list with the files of summary row Row (its Data is status + 1, nil for all) }
procedure TFrameCheck.ShowStatus(Row: Integer);
var
  I, N, K: Integer;
begin
  if (Row < 0) or (Row >= ListSummary.Items.Count) then Exit;
  K := Integer(NativeInt(ListSummary.Items[Row].Data)) - 1;
  SetLength(FShown, Length(FItems));
  N := 0;
  for I := 0 to High(FItems) do
    if (K < 0) or (Ord(FItems[I].Status) = K) then
    begin
      FShown[N] := I;
      Inc(N);
    end;
  SetLength(FShown, N);
  LabelFiles.Caption := ListSummary.Items[Row].Caption + ':';
  ListFiles.Items.Count := N;
  ListFiles.Invalidate;
end;

procedure TFrameCheck.ListSummarySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then ShowStatus(Item.Index);
end;

procedure TFrameCheck.ListSummaryDblClick(Sender: TObject);
begin
  if ListSummary.ItemIndex >= 0 then PageCheck.ActivePage := TabFiles;
end;

procedure TFrameCheck.ListFilesData(Sender: TObject; Item: TListItem);
var
  It: TCheckItem;
begin
  if Item.Index > High(FShown) then Exit;
  It := FItems[FShown[Item.Index]];
  Item.SubItems.Clear;
  Item.Caption := CheckStatusText(It.Status);
  Item.SubItems.Add(It.Path);
  if It.Size < 0 then Item.SubItems.Add('') else Item.SubItems.Add(FormatSize(It.Size));
end;

end.
