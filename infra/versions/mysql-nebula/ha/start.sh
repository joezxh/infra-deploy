#!/bin/bash
# ============================================================
# 矛盾调解平台 - 启动脚本
# ============================================================
# 使用方法:
#   ./start.sh                      # 启动所有服务
#   ./start.sh --services mysql,redis,nacos  # 启动指定服务
#   ./start.sh --exclude mysql      # 排除指定服务启动
#   ./start.sh --stop mysql         # 停止指定服务
#   ./start.sh --restart mysql,nacos # 重启指定服务
#   ./start.sh --help               # 显示帮助信息
# ============================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================
# Docker 兼容性设置
# ============================================================

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

# ============================================================
# 环境变量加载
# ============================================================

ENV_FILE="${SCRIPT_DIR}/../../.env"
ENV_SAMPLE="${SCRIPT_DIR}/../../.env.sample"

load_env() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        echo "加载环境变量: $env_file"
        set -a
        source "$env_file"
        set +a
        return 0
    fi
    return 1
}

if ! load_env "$ENV_FILE"; then
    if load_env "$ENV_SAMPLE"; then
        echo "警告: .env 文件不存在，使用 .env.sample 默认值"
        echo "建议: cp .env.sample .env 并修改配置"
    fi
fi

# ============================================================
# 显示帮助信息
# ============================================================

show_help() {
    echo ""
    echo "矛盾调解平台 - 启动脚本"
    echo ""
    echo "使用方法:"
    echo "  ./start.sh                          启动所有服务"
    echo "  ./start.sh --services SERVICE_LIST  启动指定服务 (逗号分隔)"
    echo "  ./start.sh --exclude SERVICE_LIST   排除指定服务启动 (逗号分隔)"
    echo "  ./start.sh --stop SERVICE_LIST      停止指定服务 (逗号分隔)"
    echo "  ./start.sh --stopall                停止所有服务并移除容器"
    echo "  ./start.sh --restart SERVICE_LIST   重启指定服务 (逗号分隔)"
    echo "  ./start.sh --status                 显示服务状态"
    echo "  ./start.sh --logs [SERVICE]         查看服务日志"
    echo "  ./start.sh --help                   显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  ./start.sh --services mysql,redis,nacos"
    echo "  ./start.sh --exclude nebula-metad,nebula-storaged,nebula-graphd"
    echo "  ./start.sh --stop mysql"
    echo "  ./start.sh --stopall"
    echo "  ./start.sh --restart mysql,nacos"
    echo ""
    echo "可用服务名称:"
    echo "  MySQL 版本:     mysql, redis, nacos, minio, nginx"
    echo "                  nebula-metad, nebula-storaged, nebula-graphd (NebulaGraph)"
    echo "                  neo4j (Neo4j)"
    echo "  PostgreSQL 版本: postgres, redis, nacos, minio, nginx"
    echo "                   nebula-metad, nebula-storaged, nebula-graphd (NebulaGraph)"
    echo "                   neo4j (Neo4j)"
    echo ""
}

# ============================================================
# 显示服务状态
# ============================================================

show_status() {
    echo ""
    echo "=============================================="
    echo "  服务状态"
    echo "=============================================="
    echo ""
    $DOCKER_COMPOSE ps
    echo ""
}

# ============================================================
# 查看服务日志
# ============================================================

show_logs() {
    local service="$1"
    if [ -n "$service" ]; then
        echo "查看 $service 服务日志..."
        $DOCKER_COMPOSE logs -f "$service"
    else
        echo "查看所有服务日志..."
        $DOCKER_COMPOSE logs -f
    fi
}

# ============================================================
# 启动服务
# ============================================================

start_services() {
    local services="$1"
    local exclude="$2"
    
    echo ""
    echo "=============================================="
    echo "  矛盾调解平台服务启动"
    echo "=============================================="
    echo ""
    
    if [ -n "$services" ]; then
        # 启动指定服务
        echo "启动指定服务: $services"
        # 将逗号替换为空格
        services="${services//,/ }"
        $DOCKER_COMPOSE up -d $services
    elif [ -n "$exclude" ]; then
        # 启动除指定服务外的所有服务
        echo "排除服务: $exclude"
        # 获取所有服务列表
        all_services=$($DOCKER_COMPOSE config --services)
        # 将排除列表转换为数组
        IFS=',' read -ra exclude_array <<< "$exclude"
        # 过滤服务
        start_list=""
        for service in $all_services; do
            skip=false
            for ex in "${exclude_array[@]}"; do
                if [ "$service" = "$ex" ]; then
                    skip=true
                    break
                fi
            done
            if [ "$skip" = false ]; then
                start_list="$start_list $service"
            fi
        done
        echo "启动服务: $start_list"
        $DOCKER_COMPOSE up -d $start_list
    else
        # 启动所有服务
        echo "启动所有服务..."
        $DOCKER_COMPOSE up -d
    fi
    
    echo ""
    echo "服务启动完成!"
    echo ""
}

# ============================================================
# 停止服务
# ============================================================

stop_services() {
    local services="$1"
    
    echo ""
    echo "=============================================="
    echo "  停止服务"
    echo "=============================================="
    echo ""
    
    if [ -n "$services" ]; then
        echo "停止指定服务: $services"
        # 将逗号替换为空格
        services="${services//,/ }"
        $DOCKER_COMPOSE stop $services
    else
        echo "停止所有服务..."
        $DOCKER_COMPOSE down
    fi
    
    echo ""
    echo "服务已停止!"
    echo ""
}

# ============================================================
# 重启服务
# ============================================================

restart_services() {
    local services="$1"
    
    echo ""
    echo "=============================================="
    echo "  重启服务"
    echo "=============================================="
    echo ""
    
    if [ -n "$services" ]; then
        echo "重启指定服务: $services"
        # 将逗号替换为空格
        services="${services//,/ }"
        $DOCKER_COMPOSE restart $services
    else
        echo "重启所有服务..."
        $DOCKER_COMPOSE restart
    fi
    
    echo ""
    echo "服务重启完成!"
    echo ""
}

# ============================================================
# 主程序
# ============================================================

# 解析命令行参数
ACTION="start"
SERVICES=""
EXCLUDE=""
SERVICE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --services|-s)
            ACTION="start"
            SERVICES="$2"
            shift 2
            ;;
        --exclude|-e)
            ACTION="start"
            EXCLUDE="$2"
            shift 2
            ;;
        --stop)
            ACTION="stop"
            SERVICES="$2"
            shift 2
            ;;
        --stopall)
            ACTION="stopall"
            shift
            ;;
        --restart|-r)
            ACTION="restart"
            SERVICES="$2"
            shift 2
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --logs|-l)
            ACTION="logs"
            SERVICE_NAME="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "错误: Docker 未安装"
    exit 1
fi

echo "使用 Docker Compose 命令: $DOCKER_COMPOSE"
echo "Docker API Version: $DOCKER_API_VERSION"
echo ""

# 执行相应操作
case "$ACTION" in
    start)
        start_services "$SERVICES" "$EXCLUDE"
        show_status
        ;;
    stop)
        stop_services "$SERVICES"
        ;;
    stopall)
        echo ""
        echo "=============================================="
        echo "  停止所有服务并移除容器"
        echo "=============================================="
        echo ""
        $DOCKER_COMPOSE down
        echo ""
        echo "所有服务已停止并移除容器!"
        echo ""
        ;;
    restart)
        restart_services "$SERVICES"
        show_status
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$SERVICE_NAME"
        ;;
    *)
        echo "未知操作: $ACTION"
        show_help
        exit 1
        ;;
esac
