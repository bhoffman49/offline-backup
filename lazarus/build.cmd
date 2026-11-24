@echo off
rem Builds the Lazarus edition into ..\build\lazarus\OfflineBackup.exe
rem Set LAZBUILD if Lazarus is not in F:\lazarus.
setlocal
cd /d "%~dp0"
if "%LAZBUILD%"=="" set LAZBUILD=F:\lazarus\lazbuild.exe
for %%L in ("%LAZBUILD%") do set LAZDIR=%%~dpL
set LAZFPC=%LAZDIR%fpc\3.2.2\bin\x86_64-win64\fpc.exe
set STUB=%~dp0..\build\lazarus\stub
if not exist "%STUB%" mkdir "%STUB%"
rem the checksum program the Checksums area writes (..\stub); the lpi puts it in the exe as CHECKSTUB
"%LAZFPC%" -B -O3 -vw- -Fu..\common -FE"%STUB%" -FU"%STUB%" ..\stub\CheckStub.dpr || exit /b 1
"%LAZBUILD%" -B OfflineBackup.lpi || exit /b 1
echo built %~dp0..\build\lazarus\OfflineBackup.exe
