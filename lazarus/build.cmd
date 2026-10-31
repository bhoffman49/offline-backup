@echo off
rem Builds the Lazarus edition into ..\build\lazarus\OfflineBackup.exe
rem Set LAZBUILD if Lazarus is not in F:\lazarus.
setlocal
cd /d "%~dp0"
if "%LAZBUILD%"=="" set LAZBUILD=F:\lazarus\lazbuild.exe
"%LAZBUILD%" -B OfflineBackup.lpi || exit /b 1
echo built %~dp0..\build\lazarus\OfflineBackup.exe
