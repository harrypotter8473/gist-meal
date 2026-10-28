@echo off
rem Double-click to remove scheduled tasks and saved Kakao credentials.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
