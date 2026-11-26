unit ReadingPanel;

{ The files being read right now, under the drive list on the Backup page (0.12): a line saying what is going on,
  then for each file - the biggest first, as many as fit - its name and a bar of how far it is. An MD5 check, Verify
  drive and recording checksums read several files at once (TCopyProgress.Reading). Drawn in code so the Delphi VCL
  and Lazarus LCL editions show the same thing. }

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, OfflineEngine;

type
  TReadingPanel = class(TCustomControl)
  private
    FTitle: UnicodeString;
    FFiles: TReadingFiles;
    FAbove: TControl;
    function Scale(N: Integer): Integer;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Shows itself (just above Above - an alBottom control below it, like the splitter of the progress pane) while
      P is an MD5 check, a Verify or recording checksums, with P's files; hides otherwise }
    procedure ShowProgress(const P: TCopyProgress);
    // shows Title and Files (the Checksum Applet page, which lays the panel over its file list itself)
    procedure ShowFiles(const Title: UnicodeString; const Files: TReadingFiles);
    property Above: TControl read FAbove write FAbove;
  end;

implementation

const
  ROW_HEIGHT = 20;               // at 96 dpi
  TITLE_HEIGHT = 24;
  ROWS = 4;                      // the height it asks for; it shows as many as fit
  BAR_WIDTH = 124;

constructor TReadingPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := clWindow;
  Height := Scale(TITLE_HEIGHT + ROWS * ROW_HEIGHT + 10);
  Visible := False;
end;

function TReadingPanel.Scale(N: Integer): Integer;
begin
  Result := MulDiv(N, Screen.PixelsPerInch, 96);
end;

procedure TReadingPanel.ShowProgress(const P: TCopyProgress);
var
  Title: UnicodeString;
begin
  if P.Checking then Title := 'Comparing file checksums in ' + P.Folder + '.'
  else if P.Hashing then Title := 'Reading the copied files again for their checksums.'
  else if P.Verifying then Title := 'Comparing the files on the drive with their checksums.'
  else
  begin
    Visible := False;
    Exit;
  end;
  ShowFiles(Title, P.Reading);
end;

procedure TReadingPanel.ShowFiles(const Title: UnicodeString; const Files: TReadingFiles);
begin
  FTitle := Title;
  FFiles := Files;
  if not Visible then
  begin
    // alBottom controls stack by their Top: put it just above the one it belongs over
    if FAbove <> nil then Top := FAbove.Top - 1;
    Visible := True;
  end;
  Invalidate;
end;

procedure TReadingPanel.Paint;
var
  I, Y, RowH, BarW, Pct: Integer;
  R, B: TRect;
  S: UnicodeString;
begin
  Canvas.Brush.Color := clWindow;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clBtnShadow;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(Scale(6), 0, ClientWidth - Scale(6), ClientHeight - Scale(2));
  Canvas.Brush.Style := bsSolid;
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := clWindowText;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  R := Rect(Scale(18), Scale(4), ClientWidth - Scale(18), Scale(4 + TITLE_HEIGHT));
  DrawTextW(Canvas.Handle, PWideChar(FTitle), Length(FTitle), R, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  RowH := Scale(ROW_HEIGHT);
  BarW := Scale(BAR_WIDTH);
  Y := Scale(4 + TITLE_HEIGHT);
  for I := 0 to High(FFiles) do
  begin
    if Y + RowH > ClientHeight - Scale(4) then Break;
    // the name, cut in the middle if it is too long (the file name itself stays)
    S := FFiles[I].Name;
    Canvas.Brush.Style := bsClear;           // the bar's colours must not show behind the next name
    SetBkMode(Canvas.Handle, TRANSPARENT);
    R := Rect(Scale(18), Y, ClientWidth - Scale(18) - BarW - Scale(16), Y + RowH);
    DrawTextW(Canvas.Handle, PWideChar(S), Length(S), R, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_PATH_ELLIPSIS);
    // the bar: grey, filled green as far as the file has been read
    B := Rect(ClientWidth - Scale(18) - BarW, Y + Scale(3), ClientWidth - Scale(18), Y + RowH - Scale(3));
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := $00E6E6E6;
    Canvas.Pen.Color := $00BCBCBC;
    Canvas.Rectangle(B.Left, B.Top, B.Right, B.Bottom);
    if FFiles[I].Size > 0 then Pct := Round(100.0 * FFiles[I].Done / FFiles[I].Size) else Pct := 100;
    if Pct > 100 then Pct := 100;
    if Pct > 0 then
    begin
      Canvas.Brush.Color := $00208020;
      Canvas.FillRect(Rect(B.Left + 1, B.Top + 1, B.Left + 1 + (B.Right - B.Left - 2) * Pct div 100, B.Bottom - 1));
    end;
    Inc(Y, RowH);
  end;
end;

end.
