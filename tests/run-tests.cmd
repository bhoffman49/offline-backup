@echo off
rem Builds EngineTest and the checksum program (..\stub) with Delphi (dcc64) and Free Pascal, then runs each test in
rem a fresh temp folder (each test also runs its own compiler's checksum program).
rem Nothing outside %TEMP% and ..\build is written. Exit code 0 = everything built and passed.
rem (No ( ) blocks here: the "(x86)" in the Delphi path breaks them.)
setlocal
cd /d "%~dp0"
set BUILD=%~dp0..\build\tests
set DCC=C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe
set FPC=F:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe
set RC=0

if not exist "%DCC%" goto nodelphi
if not exist "%BUILD%\delphi\stub" mkdir "%BUILD%\delphi\stub"
echo === Delphi build
"%DCC%" -Q -B -$O+ -NSSystem;Winapi -U..\common -E"%BUILD%\delphi\stub" -NU"%BUILD%\delphi\stub" ..\stub\CheckStub.dpr
if errorlevel 1 exit /b 1
"%DCC%" -Q -B -NSSystem;Winapi -U..\common -E"%BUILD%\delphi" -NU"%BUILD%\delphi" EngineTest.dpr
if errorlevel 1 exit /b 1
call :run "%BUILD%\delphi\EngineTest.exe" delphi "%BUILD%\delphi\stub\CheckStub.exe"
goto fpc
:nodelphi
echo Delphi not found - skipped

:fpc
if not exist "%FPC%" goto nofpc
if not exist "%BUILD%\fpc\stub" mkdir "%BUILD%\fpc\stub"
echo === Free Pascal build
"%FPC%" -B -O3 -vw- -Fu..\common -FE"%BUILD%\fpc\stub" -FU"%BUILD%\fpc\stub" ..\stub\CheckStub.dpr
if errorlevel 1 exit /b 1
"%FPC%" -B -O3 -vw- -Fu..\common -FE"%BUILD%\fpc" -FU"%BUILD%\fpc" EngineTest.dpr
if errorlevel 1 exit /b 1
call :run "%BUILD%\fpc\EngineTest.exe" fpc "%BUILD%\fpc\stub\CheckStub.exe"
exit /b %RC%
:nofpc
echo Free Pascal not found - skipped
exit /b %RC%

:run
set WORK=%TEMP%\OfflineBackupEngineTest-%2-%RANDOM%
mkdir "%WORK%"
echo === %2 test in %WORK%
%1 "%WORK%" %3
if errorlevel 1 set RC=1
if %RC%==0 rmdir /s /q "%WORK%"
exit /b 0
