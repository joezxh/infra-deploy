@echo off
REM ============================================================
REM 矛盾纠纷调解平台 - 应用服务启动脚本 (Windows)
REM 用法: start.bat [version] [mode]
REM 示例:
REM   start.bat mysql-neo4j single
REM   start.bat pg-nebula ha
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
echo 矛盾纠纷调解平台 - 应用服务启动
echo ============================================================
echo.

REM 检查版本目录
if not exist "%VERSION_DIR%" (
    echo [错误] 版本目录不存在: %VERSION_DIR%
    echo 可用版本:
    dir /B "%APP_DIR%\versions" 2>nul
    exit /b 1
)

REM 准备环境
echo [1/5] 准备环境配置...
if not exist "%VERSION_DIR%\.env" (
    if exist "%APP_DIR%\versions\.env.example" (
        copy "%APP_DIR%\versions\.env.example" "%VERSION_DIR%\.env"
        echo [注意] 请编辑 %VERSION_DIR%\.env 文件配置您的环境
    )
)

REM 创建网络
echo [2/5] 配置 Docker 网络...
docker network ls | findstr /C:"mediation-app-network" >nul
if errorlevel 1 (
    docker network create mediation-app-network
    echo [OK] 创建应用网络
) else (
    echo [OK] 应用网络已存在
)

REM 创建日志目录
echo [3/5] 创建日志目录...
if not exist "%VERSION_DIR%\logs" mkdir "%VERSION_DIR%\logs"
for %%s in (gateway uaa system case mediation ai harness auxiliary video dispatch content) do (
    if not exist "%VERSION_DIR%\logs\%%s" mkdir "%VERSION_DIR%\logs\%%s"
)
echo [OK] 日志目录已创建

REM 启动服务
echo [4/5] 启动应用服务...
echo 版本: %INFRA_VERSION%
echo 模式: %APP_MODE%
echo.

cd /d "%VERSION_DIR%"
docker compose up -d

echo.
echo ============================================================
echo 应用服务启动完成!
echo ============================================================
echo.

REM 显示状态
echo [5/5] 服务状态:
docker compose ps

echo.
echo 访问信息:
echo ----------------------------------------
echo Gateway:    http://127.0.0.1:8080
echo UAA:        http://127.0.0.1:8081
echo System:     http://127.0.0.1:8082
echo Case:       http://127.0.0.1:8084
echo Mediation:  http://127.0.0.1:8085
echo AI:         http://127.0.0.1:8086
echo Auxiliary:  http://127.0.0.1:8089
echo Video:      http://127.0.0.1:8090
echo Harness:   http://127.0.0.1:8091
echo Dispatch:   http://127.0.0.1:8093
echo Content:    http://127.0.0.1:8094
echo Web:        http://127.0.0.1:80
echo ----------------------------------------
echo.
echo 提示: 使用 check-health.bat 检查服务健康状态

endlocal
