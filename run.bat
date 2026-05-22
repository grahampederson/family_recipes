@echo off
setlocal

:: %~dp0 ends in a backslash which breaks quoted paths — strip it
set SCRIPTDIR=%~dp0
set SCRIPTDIR=%SCRIPTDIR:~0,-1%

cd /d "%SCRIPTDIR%"

echo Working directory: %CD%
echo Files here:
dir /b

:: Output folder
set OUTPUT=%SCRIPTDIR%\recipes
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

echo.
echo Building meal planner image...
docker build -f "%SCRIPTDIR%\Dockerfile" -t meal-planner "%SCRIPTDIR%"

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