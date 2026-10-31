@echo off
rem Builds the Delphi VCL edition (Win64 release) into ..\build\delphi\OfflineBackup.exe
setlocal
cd /d "%~dp0"
set BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0
set OUT=%~dp0..\build\delphi
if not exist "%OUT%\units" mkdir "%OUT%\units"
"%BDS%\bin\brcc32.exe" -fo OfflineBackup.res OfflineBackup.rc || exit /b 1
"%BDS%\bin\dcc64.exe" -Q -B -$D- -$L- -NSSystem;Winapi;Vcl;Vcl.Imaging;System.Win -U..\common -E"%OUT%" -NU"%OUT%\units" OfflineBackup.dpr || exit /b 1
echo built %OUT%\OfflineBackup.exe
