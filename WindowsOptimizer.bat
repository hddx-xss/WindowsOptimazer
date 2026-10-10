@echo off
:: ============================================================================
:: WINDOWS OPTIMIZER - PROFESSIONAL PERFORMANCE & CLEANLINESS SUITE
:: ============================================================================
:: Launcher & Administrator Privileges Broker
:: Compatible with Windows 10 & Windows 11 (64-bit / 32-bit)
:: ============================================================================

setlocal EnableDelayedExpansion
title Windows Optimizer v2.5.0 - Professional Performance Suite

:: Configure console codepage for clean formatting
chcp 65001 >nul 2>&1

:: Set Script Directory
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%WindowsOptimizer.ps1"

:: Verify that the PowerShell engine file exists
if not exist "%PS_SCRIPT%" (
    echo [ERROR] Could not find the core engine script:
    echo         "%PS_SCRIPT%"
    echo.
    echo Please make sure WindowsOptimizer.bat and WindowsOptimizer.ps1
    echo are located in the same directory.
    echo.
    pause
    exit /b 1
)

:: ----------------------------------------------------------------------------
:: ELEVATION / ADMINISTRATOR CHECK
:: ----------------------------------------------------------------------------
net session >nul 2>&1
if %ERRORLEVEL% equ 0 (
    goto :RunElevated
)

:: If arguments were supplied on the command line, run directly without interactive elevation prompt
if not "%~1"=="" (
    goto :RunStandard
)

:: If not elevated and launched interactively, present clean choice
cls
echo ================================================================================
echo    WINDOWS OPTIMIZER v2.5.0 - Elevation Check
echo ================================================================================
echo.
echo  [NOTE] This tool operates best with Administrator privileges.
echo         Without elevation, Windows services, system temp files, and
echo         certain hardware diagnostics cannot be modified.
echo.
echo  Choose an option:
echo    [1] Relaunch as Administrator (Recommended - Prompts UAC)
echo    [2] Continue as Standard User (Analysis ^& User Temp Cleanup only)
echo    [3] Exit
echo.
set /p "ELEV_CHOICE=  Enter selection [1-3] (Default: 1): "

if "%ELEV_CHOICE%"=="" set "ELEV_CHOICE=1"
if "%ELEV_CHOICE%"=="1" goto :ElevateUAC
if "%ELEV_CHOICE%"=="2" goto :RunStandard
if "%ELEV_CHOICE%"=="3" exit /b 0

:ElevateUAC
echo.
echo  [*] Requesting Administrator elevation via UAC...
powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
if %ERRORLEVEL% equ 0 (
    exit /b 0
) else (
    echo.
    echo  [!] Elevation was denied or cancelled. Continuing in Standard User mode...
    timeout /t 2 >nul
    goto :RunStandard
)

:RunElevated
:: ----------------------------------------------------------------------------
:: RUN ELEVATED POWERSHELL ENGINE
:: ----------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto :EndScript

:RunStandard
:: ----------------------------------------------------------------------------
:: RUN STANDARD (USER-MODE) POWERSHELL ENGINE
:: ----------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
goto :EndScript

:EndScript
if %EXIT_CODE% neq 0 (
    echo.
    echo [!] Windows Optimizer exited with status code: %EXIT_CODE%
    pause
)
exit /b %EXIT_CODE%
