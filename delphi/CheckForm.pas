unit CheckForm;

{ Results of checking an .md5 file, in the Delphi VCL edition: how many files match, are bad, missing or unreadable,
  and the files of each. The Lazarus edition has the same form in ..\lazarus\CheckForm.pas. }

interface

uses
  Windows, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  OfflineEngine;

type
  TFormCheck = class(TForm)
    LabelFile: TLabel;
    LabelResult: TLabel;
    ListSummary: TListView;
    LabelFiles: TLabel;
    ListFiles: TListView;
    ButtonClose: TButton;
    procedure ListSummarySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListFilesData(Sender: TObject; Item: TListItem);
  private
    FItems: TCheckItems;
    FShown: array of Integer;     // indexes into FItems for the rows of ListFiles
    procedure ShowStatus(Row: Integer);
  public
    class procedure Execute(AOwner: TComponent; const Md5File: string; const Items: TCheckItems; R: TCopyResult);
  end;

implementation

{$R *.dfm}

const
  RowNames: array[TCheckStatus] of string = ('Match', 'BAD - do not match their MD5', 'Missing', 'Could not be read');

class procedure TFormCheck.Execute(AOwner: TComponent; const Md5File: string; const Items: TCheckItems; R: TCopyResult);
var
  F: TFormCheck;
  St: TCheckStatus;
  Count: array[TCheckStatus] of Integer;
  Bytes: array[TCheckStatus] of Int64;
  I: Integer;
  Item: TListItem;
begin
  F := TFormCheck.Create(AOwner);
  try
    F.FItems := Items;
    F.LabelFile.Caption := Md5File;
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
    if R = crCancelled then
      F.LabelResult.Caption := 'Cancelled - these are the files checked so far.'
    else if R = crOk then
      F.LabelResult.Caption := 'All ' + FormatFloat('#,##0', Length(Items)) + ' files match.'
    else
    begin
      F.LabelResult.Caption := 'Some files do not match, are missing or could not be read - see below.';
      F.LabelResult.Font.Color := clRed;
    end;
    for St := Low(TCheckStatus) to High(TCheckStatus) do
    begin
      Item := F.ListSummary.Items.Add;
      Item.Caption := RowNames[St];
      Item.SubItems.Add(FormatFloat('#,##0', Count[St]));
      if St = csMissing then Item.SubItems.Add('-') else Item.SubItems.Add(FormatSize(Bytes[St]));
      Item.Data := Pointer(Ord(St) + 1);
    end;
    Item := F.ListSummary.Items.Add;
    Item.Caption := 'All files';
    Item.SubItems.Add(FormatFloat('#,##0', Length(Items)));
    Item.SubItems.Add('');
    Item.Data := nil;
    // open on the problems if there are any, else on everything
    I := F.ListSummary.Items.Count - 1;
    if Count[csBad] > 0 then I := Ord(csBad)
    else if Count[csMissing] > 0 then I := Ord(csMissing)
    else if Count[csUnreadable] > 0 then I := Ord(csUnreadable);
    F.ListSummary.ItemIndex := I;
    F.ShowStatus(I);
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ Fills the file list with the files of summary row Row (its Data is status + 1, nil for all) }
procedure TFormCheck.ShowStatus(Row: Integer);
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

procedure TFormCheck.ListSummarySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then ShowStatus(Item.Index);
end;

procedure TFormCheck.ListFilesData(Sender: TObject; Item: TListItem);
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
