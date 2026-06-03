#!/bin/bash
# ============================================================
# MySQL + Neo4j 单机版启动
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 兼容旧版 Docker 客户端
export DOCKER_API_VERSION=1.44

# 检测 docker compose 命令 (兼容 V1 和 V2)
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "错误: 未找到 docker compose 或 docker-compose 命令"
    echo "请安装 Docker Compose V2 插件或 docker-compose"
    exit 1
fi

echo ""
echo "=============================================="
echo "  MySQL + Neo4j 单机版部署"
echo "=============================================="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "错误: Docker 未安装"
    exit 1
fi

echo "使用 Docker Compose 命令: $DOCKER_COMPOSE"
echo "Docker API Version: $DOCKER_API_VERSION"
echo ""

# 启动服务
echo "启动服务..."
$DOCKER_COMPOSE up -d

# 等待 MySQL 启动
echo "等待 MySQL 启动..."
for i in {1..60}; do
    if docker exec mediation-mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD:-mediation123}" -e "SELECT 1" &>/dev/null; then
        echo "MySQL 已就绪"
        break
    fi
    echo "等待 MySQL... ($i/60)"
    sleep 2
done

# 执行初始化脚本
echo "执行数据库初始化脚本..."
docker exec mediation-mysql sh -c "mysql -u root -p'${MYSQL_ROOT_PASSWORD:-mediation123}' < /docker-entrypoint-initdb.d/nacos-schema.sql 2>/dev/null || true"
docker exec mediation-mysql sh -c "mysql -u root -p'${MYSQL_ROOT_PASSWORD:-mediation123}' < /docker-entrypoint-initdb.d/init.sql 2>/dev/null || true"

# 执行其他 SQL 文件
for sql in mediation_ai mediation_audit mediation_content mediation_device mediation_notify mediation_stats mediation_video ai_agent_config ai_agent_template ai_agent_alter; do
    docker exec mediation-mysql sh -c "mysql -u root -p'${MYSQL_ROOT_PASSWORD:-mediation123}' mediation_db < /docker-entrypoint-initdb.d/${sql}.sql 2>/dev/null || true"
done

# 等待服务启动完成
echo "等待所有服务启动..."
sleep 10

# 显示状态
echo ""
echo "服务状态:"
$DOCKER_COMPOSE ps

echo ""
echo "=============================================="
echo "  部署完成!"
echo "=============================================="
echo ""
echo "服务访问:"
echo "  MySQL:        localhost:3308"
echo "  Redis:        localhost:6380"
echo "  Nacos:        http://localhost:8848/nacos"
echo "  Neo4j:        http://localhost:7476"
echo "  MinIO Console: http://localhost:9001"
echo ""
echo "停止服务: $DOCKER_COMPOSE down"
echo "查看日志: $DOCKER_COMPOSE logs -f"
echo ""
