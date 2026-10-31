@echo off
cd /d "%~dp0iSnipe-Control"
where pythonw.exe >nul 2>nul
if errorlevel 1 (
  echo Python 3.10 or later is required to run iSnipe Control.
  pause
  exit /b 1
)
start "" pythonw.exe "%~dp0iSnipe-Control\server.py"
