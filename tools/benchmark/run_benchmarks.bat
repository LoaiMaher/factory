@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "GAME=%~dp0..\..\build\windows\Frontier.exe"
if not exist "%GAME%" (
	echo Windows build not found: "%GAME%"
	exit /b 1
)
set "PRESETS=high"
if /I "%~1"=="all" set "PRESETS=low medium high ultra"
for %%P in (%PRESETS%) do (
	for %%R in (flythrough walk factory) do (
		echo Running %%R at %%P...
		"%GAME%" -- --benchmark=%%R --preset=%%P --bench-seconds=60 --bench-warmup=5
		if errorlevel 1 exit /b !errorlevel!
	)
)
set "RESULTS=%APPDATA%\Godot\app_userdata\Factory\benchmarks"
if exist "%RESULTS%" explorer "%RESULTS%"
endlocal
