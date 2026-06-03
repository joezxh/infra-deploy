#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 应用服务停止脚本
# 用法: ./stop.sh [version] [mode]
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 加载 Docker 兼容性函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../infra/docker-compat.sh" 2>/dev/null || {
    export DOCKER_API_VERSION=1.44
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        DOCKER_COMPOSE="docker compose"
    fi
}

# 默认配置
INFRA_VERSION=${1:-mysql-neo4j}
APP_MODE=${2:-single}
APP_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_DIR="$APP_DIR/versions/$INFRA_VERSION/$APP_MODE"

# 停止服务
stop_services() {
    echo -e "${BLUE}停止应用服务...${NC}"
    echo "版本: $INFRA_VERSION"
    echo "模式: $APP_MODE"
    echo ""
    
    cd "$VERSION_DIR"
    $DOCKER_COMPOSE down
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}应用服务已停止${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 清理网络 (可选)
cleanup_network() {
    read -p "是否清理应用网络? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $DOCKER_COMPOSE network rm mediation-app-network 2>/dev/null || true
        echo -e "${GREEN}✓ 应用网络已清理${NC}"
    fi
}

# 清理卷 (可选)
cleanup_volumes() {
    read -p "是否清理应用数据卷? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $DOCKER_COMPOSE volume rm mediation-video-data mediation-web-logs 2>/dev/null || true
        echo -e "${GREEN}✓ 应用数据卷已清理${NC}"
    fi
}

main() {
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}矛盾纠纷调解平台 - 应用服务停止${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    
    cd "$VERSION_DIR"
    
    if $DOCKER_COMPOSE ps | grep -q "Up"; then
        stop_services
        cleanup_network
    else
        echo -e "${YELLOW}没有正在运行的服务${NC}"
    fi
}

main "$@"
