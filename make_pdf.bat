@echo off
setlocal

set SCRIPTDIR=%~dp0
set SCRIPTDIR=%SCRIPTDIR:~0,-1%

cd /d "%SCRIPTDIR%"

set OUTPUT=%SCRIPTDIR%\recipes

echo Building meal planner image (if not already built)...
docker build -f "%SCRIPTDIR%\Dockerfile" -t meal-planner "%SCRIPTDIR%"

if %ERRORLEVEL% neq 0 (
  echo Build failed. See errors above.
  pause
  exit /b 1
)

echo.
echo Generating PDF from recipes in: %OUTPUT%
echo.

:: Pass DATE=YYYY-MM-DD to target a specific week, e.g:
::   set DATE=2026-05-21
:: Otherwise it picks the most recent week automatically.

docker run --rm ^
  -v "%OUTPUT%:/output" ^
  -e OUTPUT_DIR=/output ^
  %DATE_ARG% ^
  --entrypoint python3 ^
  meal-planner make_pdf.py

if %ERRORLEVEL% neq 0 (
  echo PDF generation failed. See errors above.
  pause
  exit /b 1
)

echo.
echo Done! Look for a file ending in _meal_plan.pdf in:
echo   %OUTPUT%
pause