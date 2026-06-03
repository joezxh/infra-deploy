#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 服务健康检查脚本
# 用法: ./check-health.sh [version] [mode]
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

# 服务列表
SERVICES=(
    "gateway:8080:Gateway API"
    "uaa:8081:UAA 认证"
    "system:8082:System 系统"
    "case:8084:Case 案件"
    "mediation:8085:Mediation 调解"
    "ai:8086:AI 智能"
    "harness:8091:Harness Agent"
    "auxiliary:8089:Auxiliary 辅助"
    "video:8090:Video 视频"
    "dispatch:8093:Dispatch 派发"
    "content:8094:Content 内容"
)

# 检查服务健康
check_service() {
    local service=$1
    local port=$2
    local name=$3
    
    # 首先检查容器状态
    container_status=$(docker inspect --format='{{.State.Status}}' mediation-$service 2>/dev/null || echo "not_found")
    
    if [ "$container_status" != "running" ]; then
        echo -e "${RED}✗ $name: 容器未运行 ($container_status)${NC}"
        return 1
    fi
    
    # 然后检查健康端点
    local health_url="http://127.0.0.1:$port/actuator/health"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$health_url" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ $name: 健康 ($port)${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo -e "${YELLOW}⚠ $name: 未就绪 ($port)${NC}"
    return 1
}

# 检查基础设施
check_infrastructure() {
    echo -e "${BLUE}检查基础设施服务...${NC}"
    echo "----------------------------------------"
    
    check_service "nacos" "8848" "Nacos"
    
    # 根据版本检查数据库
    if [[ "$INFRA_VERSION" == *"mysql"* ]]; then
        check_port 3306 "MySQL"
    elif [[ "$INFRA_VERSION" == *"nebula"* ]] && [[ "$INFRA_VERSION" == *"pg"* ]]; then
        check_port 5432 "PostgreSQL"
    fi
    
    check_port 6379 "Redis"
    
    if [[ "$INFRA_VERSION" == *"neo4j"* ]]; then
        check_port 7687 "Neo4j"
        check_port 7474 "Neo4j HTTP"
    elif [[ "$INFRA_VERSION" == *"nebula"* ]]; then
        check_port 9669 "NebulaGraph"
    fi
    
    echo ""
}

# 检查端口
check_port() {
    local port=$1
    local name=$2
    
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "${GREEN}✓ $name: 监听中 ($port)${NC}"
    else
        echo -e "${RED}✗ $name: 未监听 ($port)${NC}"
    fi
}

# 检查所有服务
check_all_services() {
    echo -e "${BLUE}检查应用服务...${NC}"
    echo "----------------------------------------"
    
    local total=0
    local healthy=0
    
    for service_info in "${SERVICES[@]}"; do
        IFS=':' read -r service port name <<< "$service_info"
        total=$((total + 1))
        
        if check_service "$service" "$port" "$name"; then
            healthy=$((healthy + 1))
        fi
    done
    
    echo ""
    echo "----------------------------------------"
    echo -e "${BLUE}健康检查结果: $healthy/$total 服务正常${NC}"
    
    if [ $healthy -eq $total ]; then
        echo -e "${GREEN}所有服务运行正常!${NC}"
        return 0
    else
        echo -e "${YELLOW}部分服务未就绪，请等待后重试${NC}"
        return 1
    fi
}

# 检查 Web 前端
check_web() {
    echo ""
    echo -e "${BLUE}检查 Web 前端...${NC}"
    echo "----------------------------------------"
    
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/80" 2>/dev/null; then
        if curl -sf http://127.0.0.1/ > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Web 控制台: 正常 (80)${NC}"
        else
            echo -e "${YELLOW}⚠ Web 控制台: Nginx 运行但返回错误${NC}"
        fi
    else
        echo -e "${RED}✗ Web 控制台: 未监听 (80)${NC}"
    fi
}

# 显示 Docker 容器状态
show_containers() {
    echo ""
    echo -e "${BLUE}Docker 容器状态:${NC}"
    echo "----------------------------------------"
    
    cd "$VERSION_DIR" 2>/dev/null || exit 1
    $DOCKER_COMPOSE ps
}

# 主流程
main() {
    local INFRA_VERSION=${1:-mysql-neo4j}
    local APP_MODE=${2:-single}
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local APP_DIR="$(dirname "$SCRIPT_DIR")"
    local VERSION_DIR="$APP_DIR/versions/$INFRA_VERSION/$APP_MODE"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}矛盾纠纷调解平台 - 健康检查${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "版本: $INFRA_VERSION"
    echo "模式: $APP_MODE"
    echo ""
    
    check_infrastructure
    check_all_services
    check_web
    show_containers
}

main "$@"
