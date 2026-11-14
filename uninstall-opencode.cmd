@echo off
setlocal EnableExtensions
title Uninstall opencode from the connected device
color 0E

echo.
echo  ############################################################
echo  #                                                          #
echo  #   WARNING: THIS WILL DELETE THE OPENCODE FROM THE         #
echo  #            CONNECTED DEVICE                               #
echo  #                                                          #
echo  ############################################################
echo.
echo  It removes, from the phone/tablet that adb is connected to:
echo.
echo    - the Termux command  :  opencode  (the launcher)
echo    - the Magisk boot service, so nothing comes back at boot
echo    - the Alpine rootfs, which holds:
echo         the 210 MB opencode binary
echo         the config, INCLUDING THE API KEY
echo.
echo  It does NOT touch: your photos and files on /sdcard, the
echo  Termux app itself, Magisk, or anything on this PC.
echo.
echo  Nothing is deleted until the phone confirms it can unmount, and
echo  if the rootfs is still mounted nothing is deleted at all.
echo.

set "TMPD=%TEMP%\opencode-uninstall"
if not exist "%TMPD%" mkdir "%TMPD%" >nul 2>nul

rem ---- locate adb -------------------------------------------------
set "ADB="
where adb >nul 2>nul && set "ADB=adb"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "C:\platform-tools\adb.exe" set "ADB=C:\platform-tools\adb.exe"
if not defined ADB if exist "C:\adb\adb.exe" set "ADB=C:\adb\adb.exe"
if not defined ADB if exist "C:\Program Files\platform-tools\adb.exe" set "ADB=C:\Program Files\platform-tools\adb.exe"
if not defined ADB (
  echo  ERROR: adb not found.
  echo  Install Android platform-tools, or edit this file and set ADB to
  echo  the full path of adb.exe.
  goto end
)
echo  adb: %ADB%
"%ADB%" start-server >nul 2>nul

rem ---- pick the device --------------------------------------------
"%ADB%" devices > "%TMPD%\devices.txt" 2>nul
set "SERIAL="
set "MULTI="
for /f "skip=1 tokens=1,2" %%A in (%TMPD%\devices.txt) do (
  if /i "%%B"=="device" (
    if defined SERIAL (set "MULTI=1") else set "SERIAL=%%A"
  )
)
if defined MULTI (
  echo.
  echo  ERROR: more than one device is connected. Unplug the others,
  echo  or run the uninstaller by hand with:  adb -s SERIAL ...
  echo.
  "%ADB%" devices
  goto end
)
if not defined SERIAL (
  echo.
  echo  ERROR: no device connected.
  echo.
  echo  Plug the phone in, unlock it, accept "Allow USB debugging",
  echo  then double-click this file again.
  echo.
  "%ADB%" devices
  goto end
)
echo  device: %SERIAL%

rem ---- confirm: nothing happens until the person says yes -----------
rem goto instead of a ( ) block: %ANSWER% inside a block is expanded when the
rem block is parsed, i.e. before set /p has read anything, so every answer
rem looked like a cancel.
if /i "%~1"=="/y" goto confirmed
echo.
set "ANSWER="
set /p "ANSWER= Type Y and press Enter to delete opencode from %SERIAL%, or N to cancel: "
if /i "%ANSWER%"=="y"   goto confirmed
if /i "%ANSWER%"=="yes" goto confirmed
echo.
echo  Cancelled. Nothing was deleted; opencode is still on the device.
goto end

:confirmed
echo.

rem ---- run the on-device uninstaller -------------------------------
set "LOCAL=%~dp0files\uninstall-device.sh"
set "REMOTE="
if exist "%LOCAL%" (
  echo.
  echo  pushing uninstaller...
  "%ADB%" -s %SERIAL% push "%LOCAL%" /data/local/tmp/uninstall-device.sh >nul 2>nul
  if not errorlevel 1 set "REMOTE=/data/local/tmp/uninstall-device.sh"
)
if not defined REMOTE set "REMOTE=/data/adb/opencode/uninstall.sh"

echo  running uninstaller as root...
echo.
"%ADB%" -s %SERIAL% shell "if [ -x /debug_ramdisk/su ]; then /debug_ramdisk/su -t 0 -c 'ASSUME_YES=1 sh %REMOTE%'; else su -t 0 -c 'ASSUME_YES=1 sh %REMOTE%'; fi"
echo.

rem ---- verify ------------------------------------------------------
"%ADB%" -s %SERIAL% shell "if [ -x /debug_ramdisk/su ]; then /debug_ramdisk/su -t 0 -c 'if [ -e /data/data/com.termux/files/usr/bin/opencode ] || [ -d /data/adb/opencode/alpine ]; then echo STILL_INSTALLED; else echo REMOVED; fi'; else su -t 0 -c 'if [ -e /data/data/com.termux/files/usr/bin/opencode ] || [ -d /data/adb/opencode/alpine ]; then echo STILL_INSTALLED; else echo REMOVED; fi'; fi" > "%TMPD%\state.txt" 2>nul
set "STATE="
set /p STATE=<"%TMPD%\state.txt"

if /i "%STATE%"=="REMOVED" (
  echo  ============================================================
  echo   RESULT: opencode is gone from %SERIAL%.
  echo  ============================================================
  echo   Optional clean-up on the phone: revoke Termux's root grant
  echo   in Magisk, and remove the extra keyboard row if you added it.
) else (
  echo  ============================================================
  echo   RESULT: opencode is STILL on %SERIAL%.
  echo  ============================================================
  echo   "still mounted"      - reboot the phone, then run this again.
  echo   "run as root"        - unlock the phone and accept Magisk.
  echo   "no such file"       - the uninstaller is not on the phone;
  echo                          keep this file next to its files\ folder.
)

:end
echo.
echo  -- finished, press enter to close --
pause >nul
endlocal
