@echo off
setlocal
set "GODOT_EXE=%~dp0.tools\godot\Godot_v4.6-stable_win64.exe"
if exist "%GODOT_EXE%" goto run
for %%G in (godot.exe godot4.exe) do (
  for /f "delims=" %%P in ('where %%G 2^>nul') do set "GODOT_EXE=%%P"
)
if exist "%GODOT_EXE%" goto run
echo Godot 4.6 or later is required.
echo Download the standard edition from https://godotengine.org/download/windows/
echo Open Godot, import this folder's project.godot, and press F5.
pause
exit /b 1
:run
start "" "%GODOT_EXE%" --path "%~dp0." %*
