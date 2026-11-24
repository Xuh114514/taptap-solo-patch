@echo off
chcp 65001 >nul
title 切回官服
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch.ps1" -Mode official
if errorlevel 1 pause
