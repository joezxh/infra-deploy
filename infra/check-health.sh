#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 服务健康检查脚本
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HEALTHY=0
UNHEALTHY=0

check_service() {
    local name=$1
    local cmd=$2

    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC}   $name"
        HEALTHY=$((HEALTHY + 1))
    else
        echo -e "${RED}[FAIL]${NC} $name"
        UNHEALTHY=$((UNHEALTHY + 1))
    fi
}

echo ""
echo "=============================================="
echo "  基础设施服务健康检查"
echo "=============================================="
echo ""

# 检查 Docker 容器状态
echo "容器状态:"
echo "----------------------------------------------"
docker compose -f docker-compose.single.yml ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || \
docker ps --filter "name=mediation-" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || \
echo "  (单机模式容器)"

echo ""

# MySQL 健康检查
echo "数据库服务:"
echo "----------------------------------------------"
check_service "MySQL" "docker exec mediation-mysql-single mysqladmin ping -uroot -p'${MYSQL_ROOT_PASSWORD:-mediation123}' 2>/dev/null"
check_service "PostgreSQL (pgvector)" "docker exec mediation-postgres-single pg_isready -U '${PG_USER:-mediation}' 2>/dev/null"
check_service "Redis" "docker exec mediation-redis-single redis-cli ping 2>/dev/null"

echo ""

# Nacos 健康检查
echo "配置中心:"
echo "----------------------------------------------"
check_service "Nacos" "curl -sf http://localhost:${NACOS_PORT:-8848}/nacos/v1/console/health/readiness"

echo ""

# 图数据库健康检查
echo "图数据库:"
echo "----------------------------------------------"
check_service "Neo4j" "docker exec mediation-neo4j-single cypher-shell -u '${NEO4J_USER:-neo4j}' -p '${NEO4J_PASSWORD:-mediation123}' 'RETURN 1' 2>/dev/null"

echo ""

# 对象存储健康检查
echo "对象存储:"
echo "----------------------------------------------"
check_service "MinIO" "curl -sf http://localhost:${MINIO_API_PORT:-9000}/minio/health/live"

echo ""

# 汇总
echo "=============================================="
echo "  检查结果汇总"
echo "=============================================="
echo ""
echo -e "健康服务: ${GREEN}$HEALTHY${NC}"
echo -e "异常服务: ${RED}$UNHEALTHY${NC}"
echo ""

if [ $UNHEALTHY -eq 0 ]; then
    echo -e "${GREEN}所有服务运行正常!${NC}"
    exit 0
else
    echo -e "${YELLOW}部分服务可能需要关注${NC}"
    echo ""
    echo "查看日志: docker compose -f docker-compose.single.yml logs -f [service-name]"
    exit 1
fi
