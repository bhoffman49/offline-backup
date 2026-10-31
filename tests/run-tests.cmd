@echo off
rem Builds EngineTest with Delphi (dcc64) and Free Pascal, then runs each in a fresh temp folder.
rem Nothing outside %TEMP% and ..\build is written. Exit code 0 = everything built and passed.
rem (No ( ) blocks here: the "(x86)" in the Delphi path breaks them.)
setlocal
cd /d "%~dp0"
set BUILD=%~dp0..\build\tests
set DCC=C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe
set FPC=F:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe
set RC=0

if not exist "%DCC%" goto nodelphi
if not exist "%BUILD%\delphi" mkdir "%BUILD%\delphi"
echo === Delphi build
"%DCC%" -Q -B -NSSystem;Winapi -U..\common -E"%BUILD%\delphi" -NU"%BUILD%\delphi" EngineTest.dpr
if errorlevel 1 exit /b 1
call :run "%BUILD%\delphi\EngineTest.exe" delphi
goto fpc
:nodelphi
echo Delphi not found - skipped

:fpc
if not exist "%FPC%" goto nofpc
if not exist "%BUILD%\fpc" mkdir "%BUILD%\fpc"
echo === Free Pascal build
"%FPC%" -B -vw- -Fu..\common -FE"%BUILD%\fpc" -FU"%BUILD%\fpc" EngineTest.dpr
if errorlevel 1 exit /b 1
call :run "%BUILD%\fpc\EngineTest.exe" fpc
exit /b %RC%
:nofpc
echo Free Pascal not found - skipped
exit /b %RC%

:run
set WORK=%TEMP%\OfflineBackupEngineTest-%2-%RANDOM%
mkdir "%WORK%"
echo === %2 test in %WORK%
%1 "%WORK%"
if errorlevel 1 set RC=1
if %RC%==0 rmdir /s /q "%WORK%"
exit /b 0
