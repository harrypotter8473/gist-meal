@echo off
rem Opens today's menu in Notepad once the logged-off task has written it. Usage: show_popup.cmd breakfast|lunch|dinner
rem Runs as an interactive task (only while the user is logged on). Waits up to 15 minutes; does not call Claude.
chcp 65001 >nul
cd /d "%~dp0"
set MEAL=%~1
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i
set FILE=output\%MEAL%_%TODAY%.txt

for /l %%n in (1,1,90) do (
  if exist "%FILE%" goto show
  timeout /t 10 /nobreak >nul
)
rem Nothing after 15 minutes: show the board links instead.
set PYTHON_EXE=python
if exist "%~dp0config.cmd" call "%~dp0config.cmd"
"%PYTHON_EXE%" .claude\skills\gist-meal\scripts\show_menu.py --meal %MEAL% --fallback
exit /b 0

:show
rem Give the writer a moment to finish the file.
timeout /t 3 /nobreak >nul
start "" notepad.exe "%~dp0%FILE%"
