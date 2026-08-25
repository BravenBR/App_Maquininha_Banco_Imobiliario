@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0compilar_host_android.ps1"
if errorlevel 1 (
  echo.
  echo A compilacao falhou. Veja a mensagem acima.
  pause
  exit /b 1
)
echo.
pause
