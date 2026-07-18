@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RemoteControl.ps1" -Cellular
if errorlevel 1 (
  echo.
  echo Cellular mode could not start. Leave this window open and share the error shown above.
  pause
)

