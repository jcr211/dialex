@echo off
setlocal
set "DIALEX_ROOT=%USERPROFILE%\.codex\dialex"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
  set "_DIALEX_PS=pwsh"
) else (
  set "_DIALEX_PS=powershell"
)
"%_DIALEX_PS%" -NoProfile -ExecutionPolicy Bypass -File "%DIALEX_ROOT%\codex-audio.ps1" %*
exit /b %ERRORLEVEL%
