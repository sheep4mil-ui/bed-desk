@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RemoteControl.ps1"
if errorlevel 1 (
  echo.
  echo Bed Desk could not start. Leave this window open and share the error shown above.
  pause
)

