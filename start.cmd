@echo off
set SCRIPT_DIR=%~dp0\scripts_light
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\light_start.ps1"