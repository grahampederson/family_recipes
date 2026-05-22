@echo off
setlocal

:: Move to the folder this script lives in so Docker finds the right Dockerfile
cd /d "%~dp0"

echo Working directory: %CD%
echo Files here:
dir /b

:: Output folder
set OUTPUT=%~dp0recipes
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

echo.
echo Building meal planner image...
docker build -f "%~dp0Dockerfile" -t meal-planner "%~dp0"

if %ERRORLEVEL% neq 0 (
  echo.
  echo Build failed. See errors above.
  pause
  exit /b 1
)

echo.
echo Running meal planner...
echo Recipes will be saved to: %OUTPUT%
echo.

docker run --rm ^
  --add-host=host-gateway:host-gateway ^
  -v "%OUTPUT%:/output" ^
  -e OLLAMA_HOST=host-gateway ^
  -e OLLAMA_MODEL=llama3.1 ^
  meal-planner

echo.
echo Done! Check the 'recipes' folder next to this script.
pause