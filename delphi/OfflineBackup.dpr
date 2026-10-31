program OfflineBackup;

{ Offline Backup - Delphi VCL edition. Copies G: to OFFLINE-x drives; lives in the system tray. }

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  MainForm in 'MainForm.pas' {FormMain},
  SettingsForm in 'SettingsForm.pas' {FormSettings},
  SourceForm in 'SourceForm.pas' {FormSource},
  DriveForm in 'DriveForm.pas' {FormDrive},
  PreviewForm in 'PreviewForm.pas' {FormPreview},
  CheckForm in 'CheckForm.pas' {FormCheck},
  OfflineEngine in '..\common\OfflineEngine.pas',
  DriveWatcher in '..\common\DriveWatcher.pas';

{$R *.res}   // icon + manifest, built from OfflineBackup.rc by build.cmd

var
  Mutex: THandle;

begin
  // one copy at a time - two would fight over the same drive (shared with the Lazarus edition)
  Mutex := CreateMutexW(nil, True, 'OfflineBackupApp.SingleInstance');
  if GetLastError = ERROR_ALREADY_EXISTS then Exit;
  Application.Initialize;
  Application.Title := 'Offline Backup';
  Application.MainFormOnTaskbar := True;
  Application.ShowMainForm := FindCmdLineSwitch('show');   // otherwise starts in the tray
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
  CloseHandle(Mutex);
end.
