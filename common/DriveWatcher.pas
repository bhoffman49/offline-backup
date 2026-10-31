unit DriveWatcher;

{ Tells the app when drives come and go (WM_DEVICECHANGE).
  Uses its own hidden top-level window so it works the same under Delphi VCL and Lazarus LCL
  (LCL does not reliably pass WM_DEVICECHANGE to forms, and message-only windows miss the broadcast).
  Device messages arrive in bursts and a new volume's label is not always readable straight away,
  so OnChange fires once, a second after the last message. Create it on the main thread. }

{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}

interface

uses
  Windows, Messages, SysUtils, Classes;

type
  TDriveWatcher = class
  private
    FWnd: HWND;
    FOnChange: TNotifyEvent;
  public
    constructor Create;
    destructor Destroy; override;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

const
  WatchClass = 'OfflineBackupDriveWatcher';
  SettleTimer = 1;
  SettleMs = 1000;

var
  Watcher: TDriveWatcher;        // only one per app

function WatcherWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
begin
  if Msg = WM_DEVICECHANGE then
  begin
    SetTimer(Wnd, SettleTimer, SettleMs, nil);   // restarts the timer if already running
    Result := 1;                                  // TRUE: never refuse a removal request
    Exit;
  end;
  if (Msg = WM_TIMER) and (WParam = SettleTimer) then
  begin
    KillTimer(Wnd, SettleTimer);
    if Assigned(Watcher) and Assigned(Watcher.FOnChange) then Watcher.FOnChange(Watcher);
    Result := 0;
    Exit;
  end;
  Result := DefWindowProcW(Wnd, Msg, WParam, LParam);
end;

constructor TDriveWatcher.Create;
var
  WC: TWndClassW;
begin
  inherited Create;
  if Assigned(Watcher) then raise Exception.Create('only one TDriveWatcher allowed');
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @WatcherWndProc;
  WC.hInstance := HInstance;
  WC.lpszClassName := WatchClass;
  Windows.RegisterClassW(WC);
  FWnd := CreateWindowExW(WS_EX_TOOLWINDOW, WatchClass, 'Offline Backup drive watcher', WS_POPUP,
    0, 0, 0, 0, 0, 0, HInstance, nil);
  if FWnd = 0 then RaiseLastOSError;
  Watcher := Self;
end;

destructor TDriveWatcher.Destroy;
begin
  Watcher := nil;
  if FWnd <> 0 then DestroyWindow(FWnd);
  inherited;
end;

end.
