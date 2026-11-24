@echo off
rem Builds the Delphi VCL edition (Win64 release) into ..\build\delphi\OfflineBackup.exe
setlocal
cd /d "%~dp0"
set BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0
set OUT=%~dp0..\build\delphi
if not exist "%OUT%\units" mkdir "%OUT%\units"
if not exist "%OUT%\stub" mkdir "%OUT%\stub"
rem the checksum program the Checksums area writes (..\stub); OfflineBackup.rc puts it in the exe as CHECKSTUB
"%BDS%\bin\dcc64.exe" -Q -B -$O+ -$D- -$L- -NSSystem;Winapi -U..\common -E"%OUT%\stub" -NU"%OUT%\stub" ..\stub\CheckStub.dpr || exit /b 1
"%BDS%\bin\brcc32.exe" -fo OfflineBackup.res OfflineBackup.rc || exit /b 1
"%BDS%\bin\dcc64.exe" -Q -B -$D- -$L- -NSSystem;Winapi;Vcl;Vcl.Imaging;System.Win -U..\common -E"%OUT%" -NU"%OUT%\units" OfflineBackup.dpr || exit /b 1
echo built %OUT%\OfflineBackup.exe
