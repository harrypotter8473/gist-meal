@echo off
rem GIST meal menu runner. Usage: run_meal.cmd breakfast|lunch|dinner [nopopup]
rem   nopopup: used by the logged-off (S4U) task, which has no screen; show_popup.cmd opens Notepad instead.
rem Scheduled by install.ps1 (Task Scheduler: {prefix}-Breakfast-Menu / -Lunch-Menu / -Dinner-Menu).
chcp 65001 >nul
cd /d "%~dp0"
set MEAL=%~1
set GIST_NO_POPUP=
if /i "%~2"=="nopopup" set GIST_NO_POPUP=1
if /i not "%MEAL%"=="breakfast" if /i not "%MEAL%"=="lunch" if /i not "%MEAL%"=="dinner" (
  echo Usage: run_meal.cmd breakfast^|lunch^|dinner
  exit /b 2
)

rem config.cmd is written by install.ps1 (CLAUDE_EXE, PYTHON_EXE, KAKAO). Fall back to PATH if it is missing.
set CLAUDE_EXE=claude
set PYTHON_EXE=python
set KAKAO=0
rem Full path: when NoDefaultCurrentDirectoryInExePath is set, cmd won't find scripts in the current folder.
if exist "%~dp0config.cmd" call "%~dp0config.cmd"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i
if not exist logs mkdir logs
set LOG=logs\%TODAY%_%MEAL%.log
set SCRIPTS=.claude\skills\gist-meal\scripts

echo [%TIME%] start %MEAL% >> "%LOG%"
rem Permissions are passed on the command line because project settings are ignored until the folder is trusted.
"%CLAUDE_EXE%" -p "/gist-meal %MEAL%" --model sonnet --permission-mode acceptEdits ^
  --allowedTools "Bash(python .claude/skills/gist-meal/scripts/fetch_menu.py*)" "Bash(python .claude/skills/gist-meal/scripts/show_menu.py*)" "WebFetch(domain:www.gist.ac.kr)" ^
  >> "%LOG%" 2>&1
echo [%TIME%] claude exit code %ERRORLEVEL% >> "%LOG%"

rem KakaoTalk is sent here (not inside the skill) so manual /gist-meal runs don't message the phone.
rem If Claude did not produce today's file, send/show links so the user still gets something.
if exist "output\%MEAL%_%TODAY%.txt" (
  if "%KAKAO%"=="1" "%PYTHON_EXE%" %SCRIPTS%\kakao_send.py send --meal %MEAL% >> "%LOG%" 2>&1
) else (
  echo [%TIME%] fallback >> "%LOG%"
  "%PYTHON_EXE%" %SCRIPTS%\show_menu.py --meal %MEAL% --fallback >> "%LOG%" 2>&1
  if "%KAKAO%"=="1" "%PYTHON_EXE%" %SCRIPTS%\kakao_send.py send --meal %MEAL% --fallback >> "%LOG%" 2>&1
)
echo [%TIME%] done >> "%LOG%"
