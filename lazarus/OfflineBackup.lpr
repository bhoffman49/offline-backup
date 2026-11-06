program OfflineBackup;

{ Offline Backup - Lazarus/LCL edition. Copies G: to OFFLINE-x drives; lives in the system tray. }

{$mode delphi}{$H+}

uses
  Interfaces, Forms, Windows, SysUtils,
  MainForm, SettingsPage, SourceForm, DrivesPage, PreviewForm, CheckPage, OfflineEngine, DriveWatcher;

{$R *.res}

var
  Mutex: THandle;

begin
  // one copy at a time - two would fight over the same drive
  Mutex := CreateMutexW(nil, True, 'OfflineBackupApp.SingleInstance');
  if GetLastError = ERROR_ALREADY_EXISTS then Exit;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'Offline Backup';
  // opens its window, so nobody wonders whether it started; /tray starts it in the tray only (e.g. at log-on)
  Application.ShowMainForm := not FindCmdLineSwitch('tray');
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
  CloseHandle(Mutex);
end.
