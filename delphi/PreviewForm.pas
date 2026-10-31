unit PreviewForm;

{ Preview window of the Delphi VCL edition: after the dry run and before anything on the drive changes, shows what
  the copy will add, update and delete, and asks Copy or Cancel. Modelled on ViceVersa's "Preview: Synchronization".
  The Lazarus edition has the same form in ..\lazarus\PreviewForm.pas. }

interface

uses
  Windows, SysUtils, Classes, UITypes, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  OfflineEngine;

type
  TFormPreview = class(TForm)
    LabelDrive: TLabel;
    LabelBanner: TLabel;
    LabelWarning: TLabel;
    ListSummary: TListView;
    LabelFiles: TLabel;
    ListFiles: TListView;
    CheckAlways: TCheckBox;
    ButtonCopy: TButton;
    ButtonCancel: TButton;
    procedure ListSummarySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListFilesData(Sender: TObject; Item: TListItem);
  private
    FItems: TPreviewItems;
    FShown: array of Integer;     // indexes into FItems for the rows of ListFiles
    procedure ShowKind(Row: Integer);
  public
    // True = Copy. Always: the "show before every copy" tick box, in and out
    class function Execute(AOwner: TComponent; const P: TCopyPreview; var Always: Boolean): Boolean;
  end;

implementation

{$R *.dfm}

const
  KindShort: array[TPreviewKind] of string = ('add', 'update', 'move', 'delete', 'add folder', 'delete folder',
    'take off');

class function TFormPreview.Execute(AOwner: TComponent; const P: TCopyPreview; var Always: Boolean): Boolean;
var
  F: TFormPreview;
  K: TPreviewKind;
  Count: array[TPreviewKind] of Integer;
  Bytes: array[TPreviewKind] of Int64;
  I: Integer;
  Item: TListItem;
begin
  F := TFormPreview.Create(AOwner);
  try
    F.FItems := P.Items;
    F.LabelDrive.Caption := P.Drive + '  -  what this copy will change on the drive';
    if Length(P.Items) = 0 then
      F.LabelBanner.Caption := 'No files or folders need to be copied or deleted.'
    else
      F.LabelBanner.Caption := 'Nothing on the drive has been changed yet. Click a line to see its files.';
    if P.Warning <> '' then
      F.LabelWarning.Caption := 'Safety check: an unusually large share of the files in ' + P.Warning +
        ' would be changed or deleted. That can mean something went wrong on the source (ransomware, a deleted ' +
        'folder, a bad restore). If you go ahead, old versions are kept in _versions.'
    else
      F.LabelWarning.Visible := False;

    for K := Low(TPreviewKind) to High(TPreviewKind) do
    begin
      Count[K] := 0;
      Bytes[K] := 0;
    end;
    for I := 0 to High(P.Items) do
    begin
      Inc(Count[P.Items[I].Kind]);
      if P.Items[I].Size > 0 then Inc(Bytes[P.Items[I].Kind], P.Items[I].Size);
    end;
    // one row per kind (the "take off" row only when there is one), then "All changes"
    for K := Low(TPreviewKind) to High(TPreviewKind) do
    begin
      if (K = pkFolderRemove) and (Count[K] = 0) then Continue;
      Item := F.ListSummary.Items.Add;
      Item.Caption := PreviewKindText(K);
      Item.SubItems.Add(FormatFloat('#,##0', Count[K]));
      if K in [pkDirAdd, pkDirDelete, pkFolderRemove] then Item.SubItems.Add('-')
      else Item.SubItems.Add(FormatSize(Bytes[K]));
      Item.Data := Pointer(Ord(K) + 1);
    end;
    Item := F.ListSummary.Items.Add;
    Item.Caption := 'All changes';
    Item.SubItems.Add(FormatFloat('#,##0', Length(P.Items)));
    Item.SubItems.Add('');
    Item.Data := nil;
    F.ListSummary.ItemIndex := F.ListSummary.Items.Count - 1;
    F.ShowKind(F.ListSummary.Items.Count - 1);

    F.CheckAlways.Checked := Always;
    Result := F.ShowModal = mrOk;
    Always := F.CheckAlways.Checked;
  finally
    F.Free;
  end;
end;

{ Fills the file list with the changes of the summary row Row (its Data is kind + 1, nil for all) }
procedure TFormPreview.ShowKind(Row: Integer);
var
  I, N, K: Integer;
begin
  if (Row < 0) or (Row >= ListSummary.Items.Count) then Exit;
  K := Integer(NativeInt(ListSummary.Items[Row].Data)) - 1;
  SetLength(FShown, Length(FItems));
  N := 0;
  for I := 0 to High(FItems) do
    if (K < 0) or (Ord(FItems[I].Kind) = K) then
    begin
      FShown[N] := I;
      Inc(N);
    end;
  SetLength(FShown, N);
  LabelFiles.Caption := ListSummary.Items[Row].Caption + ':';
  ListFiles.Items.Count := N;
  ListFiles.Invalidate;
end;

procedure TFormPreview.ListSummarySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then ShowKind(Item.Index);
end;

procedure TFormPreview.ListFilesData(Sender: TObject; Item: TListItem);
var
  It: TPreviewItem;
begin
  if Item.Index > High(FShown) then Exit;
  It := FItems[FShown[Item.Index]];
  Item.SubItems.Clear;
  Item.Caption := KindShort[It.Kind];
  Item.SubItems.Add(It.Folder);
  if It.Kind = pkMove then Item.SubItems.Add(It.From + '  ->  ' + It.Rel) else Item.SubItems.Add(It.Rel);
  if It.Size < 0 then Item.SubItems.Add('') else Item.SubItems.Add(FormatSize(It.Size));
end;

end.
