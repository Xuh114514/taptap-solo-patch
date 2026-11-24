@echo off
chcp 65001 >nul
title 开放空间 单机 / 官服 一键切换
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch.ps1"
if errorlevel 1 pause
