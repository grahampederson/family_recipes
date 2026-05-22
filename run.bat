@echo off
setlocal

:: Output folder — recipes will appear here on your Windows machine
set OUTPUT=%~dp0recipes

:: Create it if it doesn't exist
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

echo Building meal planner image...
docker build -t meal-planner .

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