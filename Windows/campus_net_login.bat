@echo off
:: Batch wrapper for PowerShell script
:: Usage: campus_net_login.bat

powershell.exe -ExecutionPolicy Bypass -File "%~dp0campus_net_login.ps1"
pause
