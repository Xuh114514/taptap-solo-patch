@echo off
chcp 65001 >nul
title 切到单机
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch.ps1" -Mode solo
if errorlevel 1 pause
