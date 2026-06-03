#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - MySQL 版本单机部署脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载 Docker 兼容性函数
source "$SCRIPT_DIR/docker-compat.sh" 2>/dev/null || {
    export DOCKER_API_VERSION=1.44
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        DOCKER_COMPOSE="docker compose"
    fi
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "  MySQL 版本单机部署"
echo "=============================================="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装"
    exit 1
fi

log_info "Docker API Version: $DOCKER_API_VERSION"
log_info "Docker Compose 命令: $DOCKER_COMPOSE"
echo ""

# 检查环境变量文件
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        log_warn ".env 文件不存在，使用默认配置"
    fi
fi

# 启动服务
log_info "启动 MySQL 版本基础设施..."
$DOCKER_COMPOSE -f docker-compose.mysql.single.yml up -d

# 等待服务启动
sleep 5

# 检查状态
echo ""
log_info "服务状态:"
$DOCKER_COMPOSE -f docker-compose.mysql.single.yml ps

echo ""
echo "=============================================="
log_info "MySQL 版本部署完成!"
echo "=============================================="
echo ""
echo "访问地址:"
echo "  MySQL:       localhost:3306"
echo "  Redis:       localhost:6379"
echo "  Nacos:       http://localhost:8848/nacos"
echo "  Neo4j:       http://localhost:7474"
echo "  NebulaGraph: localhost:9669"
echo "  MinIO:       http://localhost:9000"
echo ""
