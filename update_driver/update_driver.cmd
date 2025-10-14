@echo off
REM This script starts the Application Manager
set SCRIPT_DIR=%~dp0
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%update_driver.ps1"