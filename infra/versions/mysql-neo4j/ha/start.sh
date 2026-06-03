#!/bin/bash
# ============================================================
# MySQL + Neo4j 高可用集群启动
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载环境变量
ENV_FILE="${SCRIPT_DIR}/../../.env"
ENV_SAMPLE="${SCRIPT_DIR}/../../.env.sample"

if [ -f "$ENV_FILE" ]; then
    echo "加载环境变量: $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
elif [ -f "$ENV_SAMPLE" ]; then
    echo "警告: .env 文件不存在，使用 .env.sample 默认值"
    echo "建议: cp .env.sample .env 并修改配置"
    set -a
    source "$ENV_SAMPLE"
    set +a
fi

# 兼容旧版 Docker 客户端
export DOCKER_API_VERSION=1.44

# 检测 docker compose 命令 (兼容 V1 和 V2)
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "错误: 未找到 docker compose 或 docker-compose 命令"
    exit 1
fi

echo ""
echo "=============================================="
echo "  MySQL + Neo4j 高可用集群部署"
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

# 等待启动
echo "等待服务启动..."
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
echo "  MySQL HAProxy:   localhost:33060"
echo "  Redis:          localhost:6379"
echo "  Redis Sentinel: localhost:26379"
echo "  Nacos 集群:     localhost:8848, 8858, 8868"
echo "  Neo4j HAProxy:  localhost:7689 (Bolt), 7476 (HTTP)"
echo "  MinIO:          http://localhost:9000"
echo "  HAProxy Admin:  localhost:8404"
echo ""
echo "停止服务: $DOCKER_COMPOSE down"
echo "查看日志: $DOCKER_COMPOSE logs -f"
echo ""
