@echo off
:: Root launcher pointing to WindowsOptimizer\WindowsOptimizer1.bat
set "TARGET_BAT=%~dp0WindowsOptimizer\WindowsOptimizer.bat"
if exist "%TARGET_BAT%" (
    call "%TARGET_BAT%" %*
) else (
    echo [ERROR] Could not find %TARGET_BAT%
    pause
)
