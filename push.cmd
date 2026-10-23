@echo off
chcp 65001 >nul
setlocal
where pwsh >nul 2>nul
if "%ERRORLEVEL%"=="0" (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\push.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\push.ps1" %*
)
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%
