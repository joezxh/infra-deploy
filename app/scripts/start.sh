#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 应用服务启动脚本
# 用法: ./start.sh [version] [mode]
# 示例:
#   ./start.sh mysql-neo4j single
#   ./start.sh pg-nebula ha
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 加载 Docker 兼容性函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../infra/docker-compat.sh" 2>/dev/null || {
    # 如果加载失败，内联兼容性代码
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

# 检查版本目录
check_version() {
    if [ ! -d "$VERSION_DIR" ]; then
        echo -e "${RED}错误: 版本目录不存在: $VERSION_DIR${NC}"
        echo "可用版本:"
        ls -la "$APP_DIR/versions/" 2>/dev/null || echo "  无"
        exit 1
    fi
}

# 检查基础设施
check_infrastructure() {
    echo -e "${BLUE}检查基础设施服务...${NC}"
    
    # 检查 Docker 网络
    if $DOCKER_COMPOSE network ls | grep -q "mediation-infra-network"; then
        echo -e "${GREEN}✓ 基础设施网络已创建${NC}"
    else
        echo -e "${YELLOW}⚠ 基础设施网络不存在，请先启动基础设施服务${NC}"
        echo "提示: cd ../../infra/versions/$INFRA_VERSION/$APP_MODE && $DOCKER_COMPOSE up -d"
    fi
    
    # 检查必要的端口
    check_port() {
        local port=$1
        local name=$2
        if nc -z 127.0.0.1 $port 2>/dev/null || timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            echo -e "${GREEN}✓ $name ($port) 可用${NC}"
        else
            echo -e "${YELLOW}⚠ $name ($port) 不可用${NC}"
        fi
    }
    
    check_port 8848 "Nacos"
    check_port 3306 "MySQL"
    check_port 5432 "PostgreSQL"
    check_port 6379 "Redis"
}

# 准备环境变量
prepare_env() {
    echo -e "${BLUE}准备环境配置...${NC}"
    
    # 检查 .env 文件
    if [ ! -f "$VERSION_DIR/.env" ]; then
        if [ -f "$APP_DIR/versions/.env.example" ]; then
            echo -e "${YELLOW}复制 .env.example 到 .env${NC}"
            cp "$APP_DIR/versions/.env.example" "$VERSION_DIR/.env"
            echo -e "${YELLOW}请编辑 $VERSION_DIR/.env 文件配置您的环境${NC}"
        fi
    fi
    
    # 设置默认环境变量
    export NACOS_SERVER_ADDR=${NACOS_SERVER_ADDR:-127.0.0.1:8848}
    export INFRA_VERSION=$INFRA_VERSION
    export APP_MODE=$APP_MODE
}

# 创建网络
setup_network() {
    echo -e "${BLUE}配置 Docker 网络...${NC}"
    
    if ! $DOCKER_COMPOSE network ls | grep -q "mediation-app-network"; then
        $DOCKER_COMPOSE network create mediation-app-network 2>/dev/null || true
        echo -e "${GREEN}✓ 创建应用网络: mediation-app-network${NC}"
    else
        echo -e "${GREEN}✓ 应用网络已存在${NC}"
    fi
}

# 创建日志目录
setup_logs() {
    echo -e "${BLUE}创建日志目录...${NC}"
    mkdir -p "$VERSION_DIR/logs"
    for service in gateway uaa system case mediation ai harness auxiliary video dispatch content; do
        mkdir -p "$VERSION_DIR/logs/$service"
    done
    echo -e "${GREEN}✓ 日志目录已创建${NC}"
}

# 启动服务
start_services() {
    echo -e "${BLUE}启动应用服务...${NC}"
    echo "版本: $INFRA_VERSION"
    echo "模式: $APP_MODE"
    echo "目录: $VERSION_DIR"
    echo ""
    
    cd "$VERSION_DIR"
    
    # 加载 .env 文件
    if [ -f ".env" ]; then
        set -a
        source .env
        set +a
    fi
    
    # 启动服务
    $DOCKER_COMPOSE up -d
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}应用服务启动完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 显示服务状态
show_status() {
    echo ""
    echo -e "${BLUE}服务状态:${NC}"
    cd "$VERSION_DIR"
    $DOCKER_COMPOSE ps 2>/dev/null || echo "无法获取服务状态"
}

# 显示访问信息
show_access_info() {
    echo ""
    echo -e "${BLUE}访问信息:${NC}"
    echo "----------------------------------------"
    echo "Gateway:    http://127.0.0.1:8080"
    echo "UAA:        http://127.0.0.1:8081"
    echo "System:     http://127.0.0.1:8082"
    echo "Case:       http://127.0.0.1:8084"
    echo "Mediation:  http://127.0.0.1:8085"
    echo "AI:         http://127.0.0.1:8086"
    echo "Auxiliary:  http://127.0.0.1:8089"
    echo "Video:      http://127.0.0.1:8090"
    echo "Harness:   http://127.0.0.1:8091"
    echo "Dispatch:   http://127.0.0.1:8093"
    echo "Content:    http://127.0.0.1:8094"
    echo "Web:        http://127.0.0.1:80"
    echo "----------------------------------------"
    echo ""
    echo -e "${YELLOW}提示: 使用 ./check-health.sh 检查服务健康状态${NC}"
}

# 主流程
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}矛盾纠纷调解平台 - 应用服务启动${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_version
    check_infrastructure
    prepare_env
    setup_network
    setup_logs
    start_services
    show_status
    show_access_info
}

main "$@"
