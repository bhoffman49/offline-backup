unit SideBar;

{ The main window's left column: one large icon button per area (Backup, Drives, MD5 check, Settings,
  Checksum Applet), drawn here so the
  Delphi VCL and Lazarus LCL editions look the same. The icons are RCDATA resources named SIDE_<NAME>, each a
  multi-size .ico from tools\make-sidebar-icons.py; the size nearest the screen's scaling is used. }

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms;

type
  TSideItem = record
    Caption: string;                  // '|' starts a second line: 'Checksum|Applet'
    Icon: HICON;                      // 0 if the resource is missing
    IconSize: Integer;
    Enabled: Boolean;                 // False = shown faded, for an area that is still to come
  end;

  // Allow := False keeps the area shown now (it has unsaved changes the user wants to keep)
  TSideChangingEvent = procedure(Sender: TObject; NewIndex: Integer; var Allow: Boolean) of object;

  TSideBar = class(TCustomControl)
  private
    FItems: array of TSideItem;
    FItemIndex: Integer;
    FOnChange: TNotifyEvent;
    FOnChanging: TSideChangingEvent;
    function Scale(N: Integer): Integer;
    function ItemHeight(I: Integer): Integer;
    function ItemTop(I: Integer): Integer;
    function ItemAt(Y: Integer): Integer;
    procedure SetItemIndex(Value: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // IconName: the resource is SIDE_<IconName>; a '|' in Caption puts the rest on a second line
    procedure AddItem(const Caption, IconName: string; Enabled: Boolean = True);
    function PreferredWidth: Integer;
    // setting it calls OnChange too, so the area shown always follows the sidebar
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChanging: TSideChangingEvent read FOnChanging write FOnChanging;
  end;

implementation

const
  ICON_SIZE = 32;                     // at 96 dpi
  ITEM_HEIGHT = 70;
  ITEM_WIDTH = 92;
  LINE_HEIGHT = 16;                   // each extra caption line makes its item this much taller

{ Loads the entry of a multi-size .ico resource that is nearest Size (the larger one on a tie); Actual is its size.
  Windows makes the icon (not TIcon): the LCL's icon reader garbles these 32-bit icons. }
function LoadSideIcon(const Name: string; Size: Integer; out Actual: Integer): HICON;
var
  Res: TResourceStream;
  Data: array of Byte;
  Count, I, Best, W: Integer;
  Dir: array of packed record
    Width, Height, Colors, Reserved: Byte;
    Planes, BitCount: Word;
    BytesInRes, Offset: Cardinal;
  end;
  Header: packed record
    Reserved, IconType, Count: Word;
  end;
begin
  Result := 0;
  Actual := 0;
  if FindResource(HInstance, PChar('SIDE_' + UpperCase(Name)), RT_RCDATA) = 0 then Exit;
  Res := TResourceStream.Create(HInstance, 'SIDE_' + UpperCase(Name), RT_RCDATA);
  try
    Res.ReadBuffer(Header, SizeOf(Header));
    Count := Header.Count;
    SetLength(Dir, Count);
    if Count > 0 then Res.ReadBuffer(Dir[0], Count * SizeOf(Dir[0]));
    Best := -1;
    for I := 0 to Count - 1 do
    begin
      W := Dir[I].Width;
      if W = 0 then W := 256;
      if (Best < 0) or (Abs(W - Size) < Abs(Dir[Best].Width - Size)) or
        ((Abs(W - Size) = Abs(Dir[Best].Width - Size)) and (W > Dir[Best].Width)) then Best := I;
    end;
    if Best < 0 then Exit;
    Actual := Dir[Best].Width;
    if Actual = 0 then Actual := 256;
    SetLength(Data, Dir[Best].BytesInRes);
    Res.Position := Dir[Best].Offset;
    Res.ReadBuffer(Data[0], Length(Data));
    Result := CreateIconFromResourceEx(@Data[0], Length(Data), True, $00030000, Actual, Actual, 0);
  finally
    Res.Free;
  end;
end;

constructor TSideBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItemIndex := -1;
  TabStop := True;
  DoubleBuffered := True;
  Color := clWindow;
end;

destructor TSideBar.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if FItems[I].Icon <> 0 then DestroyIcon(FItems[I].Icon);
  inherited Destroy;
end;

function TSideBar.Scale(N: Integer): Integer;
begin
  {$IFDEF FPC}
  Result := MulDiv(N, Screen.PixelsPerInch, 96);
  {$ELSE}
  Result := MulDiv(N, CurrentPPI, 96);
  {$ENDIF}
end;

function CaptionLines(const Caption: string): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Length(Caption) do
    if Caption[I] = '|' then Inc(Result);
end;

function TSideBar.ItemHeight(I: Integer): Integer;
begin
  Result := Scale(ITEM_HEIGHT + (CaptionLines(FItems[I].Caption) - 1) * LINE_HEIGHT);
end;

function TSideBar.ItemTop(I: Integer): Integer;
var
  J: Integer;
begin
  Result := Scale(6);
  for J := 0 to I - 1 do Inc(Result, ItemHeight(J));
end;

function TSideBar.PreferredWidth: Integer;
begin
  Result := Scale(ITEM_WIDTH);
end;

procedure TSideBar.AddItem(const Caption, IconName: string; Enabled: Boolean);
var
  N: Integer;
begin
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N].Caption := Caption;
  FItems[N].Icon := LoadSideIcon(IconName, Scale(ICON_SIZE), FItems[N].IconSize);
  FItems[N].Enabled := Enabled;
  Invalidate;
end;

function TSideBar.ItemAt(Y: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FItems) do
    if (Y >= ItemTop(I)) and (Y < ItemTop(I) + ItemHeight(I)) then Exit(I);
end;

procedure TSideBar.SetItemIndex(Value: Integer);
var
  Allow: Boolean;
begin
  if (Value < 0) or (Value > High(FItems)) or not FItems[Value].Enabled then Exit;
  Allow := True;
  if (Value <> FItemIndex) and Assigned(FOnChanging) then FOnChanging(Self, Value, Allow);
  if not Allow then Exit;
  FItemIndex := Value;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TSideBar.Paint;
var
  I, Top, X, Y, P: Integer;
  R: TRect;
  Rest, Line: string;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  // a line on the right, between the sidebar and the area
  Canvas.Pen.Color := clBtnShadow;
  Canvas.MoveTo(ClientWidth - 1, 0);
  Canvas.LineTo(ClientWidth - 1, ClientHeight);
  Canvas.Font.Assign(Font);
  for I := 0 to High(FItems) do
  begin
    Top := ItemTop(I);
    R := Rect(Scale(4), Top, ClientWidth - Scale(5), Top + ItemHeight(I) - Scale(4));
    if I = FItemIndex then
    begin
      Canvas.Brush.Color := clHighlight;
      Canvas.FillRect(R);
      Canvas.Font.Color := clHighlightText;
      if Focused then Canvas.DrawFocusRect(R);
    end
    else
    begin
      Canvas.Brush.Color := Color;
      if FItems[I].Enabled then Canvas.Font.Color := clWindowText else Canvas.Font.Color := clGrayText;
    end;
    if FItems[I].Icon <> 0 then
    begin
      X := (ClientWidth - FItems[I].IconSize) div 2;
      if I = FItemIndex then
      begin
        // a light tile behind the icon, so the teal icon stands out on the highlight colour
        Canvas.Brush.Color := clWindow;
        Canvas.FillRect(Rect(X - Scale(4), Top + Scale(6), X + FItems[I].IconSize + Scale(4),
          Top + Scale(14) + FItems[I].IconSize));
        Canvas.Brush.Color := clHighlight;
      end;
      DrawIconEx(Canvas.Handle, X, Top + Scale(10), FItems[I].Icon, FItems[I].IconSize, FItems[I].IconSize, 0, 0,
        DI_NORMAL);
    end;
    Canvas.Brush.Style := bsClear;
    // one line, or more where the caption has a '|'
    Rest := FItems[I].Caption;
    Y := Top + Scale(16) + Scale(ICON_SIZE);
    repeat
      P := Pos('|', Rest);
      if P > 0 then
      begin
        Line := Copy(Rest, 1, P - 1);
        Delete(Rest, 1, P);
      end
      else
      begin
        Line := Rest;
        Rest := '';
      end;
      Canvas.TextOut((ClientWidth - Canvas.TextWidth(Line)) div 2, Y, Line);
      Inc(Y, Scale(LINE_HEIGHT));
    until (P = 0);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TSideBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  if Button = mbLeft then ItemIndex := ItemAt(Y);
end;

procedure TSideBar.KeyDown(var Key: Word; Shift: TShiftState);
var
  I: Integer;
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_DOWN then
  begin
    for I := FItemIndex + 1 to High(FItems) do
      if FItems[I].Enabled then begin ItemIndex := I; Break; end;
    Key := 0;
  end
  else if Key = VK_UP then
  begin
    for I := FItemIndex - 1 downto 0 do
      if FItems[I].Enabled then begin ItemIndex := I; Break; end;
    Key := 0;
  end;
end;

procedure TSideBar.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TSideBar.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

end.
