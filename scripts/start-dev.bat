@echo off
REM ============================================================
REM 矛盾纠纷调解平台 - 快速启动脚本 (Windows)
REM ============================================================

echo.
echo ============================================================
echo   矛盾纠纷调解平台 - 开发环境启动
echo ============================================================
echo.

REM 检查 Docker 是否安装
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] Docker 未安装，请先安装 Docker Desktop
    echo 下载地址: https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

REM 检查 docker-compose 是否安装
docker-compose --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] docker-compose 未安装
    pause
    exit /b 1
)

echo [1/3] 启动基础服务 (MySQL, Redis, Nacos, Sentinel, MinIO)...
docker-compose -f docker-compose.dev.yml up -d

echo.
echo [2/3] 等待服务启动...
timeout /t 30 /nobreak >nul

echo.
echo [3/3] 检查服务健康状态...
docker-compose -f docker-compose.dev.yml ps

echo.
echo ============================================================
echo   服务启动完成！
echo ============================================================
echo.
echo 访问地址:
echo   - Nacos 控制台:  http://localhost:8848/nacos (nacos/nacos)
echo   - Sentinel:      http://localhost:8858
echo   - MinIO Console: http://localhost:9001 (mediation/mediation123456)
echo   - API Gateway:   http://localhost:8080
echo   - MySQL:         localhost:3306 (mediation/mediation123)
echo   - Redis:         localhost:6379
echo.
echo 启动后端服务前，请先执行初始化SQL:
echo   mysql -h localhost -u mediation -p mediation_db < scripts\db\init.sql
echo.
pause
