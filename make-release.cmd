@echo off
rem Makes a release: runs the engine tests, builds both editions, and packs the Lazarus edition (the published one)
rem with a short how-to, the changelog and the license into dist\OfflineBackup-<version>-win64.zip.
rem The version comes from AppVersion in common\OfflineEngine.pas. No settings file goes in, so every download
rem starts with the defaults. Nothing is uploaded anywhere.
rem (No ( ) blocks here, like the other scripts.)
setlocal
cd /d "%~dp0"
set VER=
for /f "tokens=2 delims='" %%v in ('findstr /c:"AppVersion = '" common\OfflineEngine.pas') do set VER=%%v
if "%VER%"=="" goto nover
echo === Offline Backup %VER%

call tests\run-tests.cmd
if errorlevel 1 goto failed
cd /d "%~dp0"
call delphi\build.cmd
if errorlevel 1 goto failed
cd /d "%~dp0"
call lazarus\build.cmd
if errorlevel 1 goto failed
cd /d "%~dp0"

set OUT=dist\OfflineBackup-%VER%-win64
if exist "%OUT%" rmdir /s /q "%OUT%"
if exist "%OUT%.zip" del "%OUT%.zip"
mkdir "%OUT%"
copy /y build\lazarus\OfflineBackup.exe "%OUT%\" >nul || goto failed
copy /y tools\release-readme.txt "%OUT%\README.txt" >nul || goto failed
copy /y CHANGELOG.md "%OUT%\CHANGELOG.txt" >nul || goto failed
copy /y LICENSE "%OUT%\LICENSE.txt" >nul || goto failed
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%OUT%.zip' -Force"
if errorlevel 1 goto failed
echo.
echo made %OUT%.zip
exit /b 0

:nover
echo could not read AppVersion from common\OfflineEngine.pas
exit /b 1

:failed
echo.
echo RELEASE NOT MADE - see above
exit /b 1
