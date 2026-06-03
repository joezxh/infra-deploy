@echo off
REM ============================================================
REM 矛盾纠纷调解平台 - 应用服务停止脚本 (Windows)
REM 用法: stop.bat [version] [mode]
REM ============================================================

setlocal

set "INFRA_VERSION=%1"
if "%INFRA_VERSION%"=="" set "INFRA_VERSION=mysql-neo4j"

set "APP_MODE=%2"
if "%APP_MODE%"=="" set "APP_MODE=single"

set "SCRIPT_DIR=%~dp0"
set "APP_DIR=%SCRIPT_DIR%.."
set "VERSION_DIR=%APP_DIR%\versions\%INFRA_VERSION%\%APP_MODE%"

echo ============================================================
echo 矛盾纠纷调解平台 - 应用服务停止
echo ============================================================
echo.

cd /d "%VERSION_DIR%"

docker compose down

echo.
echo ============================================================
echo 应用服务已停止
echo ============================================================

endlocal
