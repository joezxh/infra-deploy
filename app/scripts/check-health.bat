@echo off
REM ============================================================
REM 矛盾纠纷调解平台 - 服务健康检查脚本 (Windows)
REM 用法: check-health.bat [version] [mode]
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
echo 矛盾纠纷调解平台 - 健康检查
echo ============================================================
echo.
echo 版本: %INFRA_VERSION%
echo 模式: %APP_MODE%
echo.

REM 检查容器状态
echo 检查应用服务...
echo ----------------------------------------

for %%s in (gateway uaa system case mediation ai harness auxiliary video dispatch content) do (
    docker inspect --format="%%{State.Status}" mediation-%%s >nul 2>&1
    if errorlevel 1 (
        echo [X] mediation-%%s: 未找到
    ) else (
        for /f "delims=" %%i in ('docker inspect --format="%%{State.Status}" mediation-%%s') do set "STATUS=%%i"
        if "!STATUS!"=="running" (
            echo [OK] mediation-%%s: 运行中
        ) else (
            echo [X] mediation-%%s: !STATUS!
        )
    )
)

echo.
echo ----------------------------------------

REM 显示完整容器状态
echo Docker 容器状态:
cd /d "%VERSION_DIR%" 2>nul
docker compose ps

echo.
echo ============================================================
echo 健康检查完成
echo ============================================================

endlocal
