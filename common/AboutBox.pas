unit AboutBox;

{ The About window, opened from "About Offline Backup..." in the main window's title-bar (system) menu. Built in code
  here so the Delphi VCL and Lazarus LCL editions show the same window. }

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls, ExtCtrls;

const
  // the command id of the About item in the system menu (below $F000, low 4 bits clear, as Windows asks)
  SC_ABOUTBOX = $0110;

// adds a separator and "About Offline Backup..." to the window's system menu; call it each time the window handle is made
procedure AddAboutToSystemMenu(Wnd: HWND);
procedure ShowAboutBox(AOwner: TComponent);

implementation

uses
  ShellAPI, OfflineEngine;

const
  DEVELOPER = 'Brian Hoffman';
  WEBSITE = 'www.level103.com';
  WEBSITE_URL = 'https://www.level103.com';
  SOURCE = 'github.com/bhoffman49/offline-backup';
  SOURCE_URL = 'https://github.com/bhoffman49/offline-backup';

type
  TAboutForm = class(TForm)
  private
    FIcon: HICON;
    FIconBox: TPaintBox;
    function Scale(N: Integer): Integer;
    function TextWidthOf(L: TLabel): Integer;
    function AddLabel(const Text: string; Top, Size: Integer; Bold: Boolean): TLabel;
    function AddLink(const Prefix, Text, Url: string; Top: Integer): TLabel;
    procedure IconPaint(Sender: TObject);
    procedure LinkClick(Sender: TObject);
  public
    constructor CreateAbout(AOwner: TComponent);
    destructor Destroy; override;
  end;

procedure AddAboutToSystemMenu(Wnd: HWND);
var
  Menu: HMENU;
begin
  Menu := GetSystemMenu(Wnd, False);
  if Menu = 0 then Exit;
  AppendMenuW(Menu, MF_SEPARATOR, 0, nil);
  AppendMenuW(Menu, MF_STRING, SC_ABOUTBOX, 'About Offline Backup...');
end;

procedure ShowAboutBox(AOwner: TComponent);
var
  F: TAboutForm;
begin
  F := TAboutForm.CreateAbout(AOwner);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

function TAboutForm.Scale(N: Integer): Integer;
begin
  {$IFDEF FPC}
  Result := MulDiv(N, Screen.PixelsPerInch, 96);
  {$ELSE}
  Result := MulDiv(N, CurrentPPI, 96);
  {$ENDIF}
end;

// LCL sizes a label only once the window is shown, so its Width is not known yet: measure the text instead
function TAboutForm.TextWidthOf(L: TLabel): Integer;
{$IFDEF FPC}
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(L.Font);
    Result := B.Canvas.TextWidth(L.Caption);
  finally
    B.Free;
  end;
end;
{$ELSE}
begin
  Result := L.Width;
end;
{$ENDIF}

function TAboutForm.AddLabel(const Text: string; Top, Size: Integer; Bold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := Text;
  Result.Font.Size := Size;
  if Bold then Result.Font.Style := [fsBold];
  Result.Left := Scale(140);
  Result.Top := Scale(Top);
end;

// "Prefix" in the normal colour, then a link label just after it
function TAboutForm.AddLink(const Prefix, Text, Url: string; Top: Integer): TLabel;
var
  P: TLabel;
begin
  P := AddLabel(Prefix, Top, 10, False);
  Result := AddLabel(Text, Top, 10, False);
  Result.Left := P.Left + TextWidthOf(P) + Scale(4);
  Result.Font.Color := clHotLight;
  Result.Font.Style := [fsUnderline];
  Result.Cursor := crHandPoint;
  Result.Hint := Url;
  Result.ShowHint := True;
  Result.OnClick := LinkClick;
end;

constructor TAboutForm.CreateAbout(AOwner: TComponent);
var
  Last: TLabel;
  Close: TButton;
  W, I: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'About Offline Backup';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Color := clWindow;

  FIconBox := TPaintBox.Create(Self);
  FIconBox.Parent := Self;
  FIconBox.SetBounds(Scale(20), Scale(20), Scale(96), Scale(96));
  FIconBox.OnPaint := IconPaint;
  // the exe's own icon; Windows picks the nearest size it holds
  FIcon := LoadImage(HInstance, 'MAINICON', IMAGE_ICON, Scale(96), Scale(96), 0);

  AddLabel('Offline Backup ' + AppVersion, 18, 20, True);
  AddLabel('Developer: ' + DEVELOPER, 62, 11, False);
  AddLink('Website:', WEBSITE, WEBSITE_URL, 88);
  AddLink('Source code:', SOURCE, SOURCE_URL, 110);
  Last := AddLabel('Free software under the MIT License.', 140, 9, False);
  Last.Font.Color := clGrayText;

  W := Scale(140);
  for I := 0 to ControlCount - 1 do
    if (Controls[I] is TLabel) and (Controls[I].Left + TextWidthOf(TLabel(Controls[I])) > W) then
      W := Controls[I].Left + TextWidthOf(TLabel(Controls[I]));
  ClientWidth := W + Scale(24);

  Close := TButton.Create(Self);
  Close.Parent := Self;
  Close.Caption := 'Close';
  Close.SetBounds((ClientWidth - Scale(90)) div 2, Last.Top + Scale(36), Scale(90), Scale(28));
  Close.ModalResult := mrCancel;
  Close.Cancel := True;
  Close.Default := True;
  ClientHeight := Close.Top + Close.Height + Scale(14);
  ActiveControl := Close;
end;

destructor TAboutForm.Destroy;
begin
  if FIcon <> 0 then DestroyIcon(FIcon);
  inherited;
end;

procedure TAboutForm.IconPaint(Sender: TObject);
begin
  if FIcon <> 0 then
    DrawIconEx(FIconBox.Canvas.Handle, 0, 0, FIcon, FIconBox.Width, FIconBox.Height, 0, 0, DI_NORMAL);
end;

procedure TAboutForm.LinkClick(Sender: TObject);
begin
  ShellExecuteW(Handle, 'open', PWideChar(UnicodeString((Sender as TLabel).Hint)), nil, nil, SW_SHOWNORMAL);
end;

end.
