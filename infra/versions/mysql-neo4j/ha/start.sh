#!/bin/bash
# ============================================================
# MySQL + Neo4j 高可用集群启动
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# 启动服务
echo "启动服务..."
docker compose up -d

# 等待启动
echo "等待服务启动..."
sleep 10

# 显示状态
echo ""
echo "服务状态:"
docker compose ps

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
echo "停止服务: docker compose down"
echo "查看日志: docker compose logs -f"
echo ""
