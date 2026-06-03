#!/bin/bash
# ============================================================
# Docker 兼容性函数库
# 解决旧版 Docker 客户端兼容性问题
# ============================================================

# 兼容旧版 Docker 客户端 (设置 API 版本)
export DOCKER_API_VERSION=1.44

# 检测并设置 docker compose 命令 (兼容 V1 和 V2)
setup_docker_compose() {
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        echo "错误: 未找到 docker compose 或 docker-compose 命令"
        echo "请安装 Docker Compose V2 插件或 docker-compose"
        exit 1
    fi
    export DOCKER_COMPOSE
}

# 检查 Docker 环境
check_docker_env() {
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo "错误: Docker 未安装"
        exit 1
    fi
    
    # 设置 docker compose 命令
    setup_docker_compose
    
    echo "Docker API Version: $DOCKER_API_VERSION"
    echo "Docker Compose 命令: $DOCKER_COMPOSE"
    echo ""
}

# 初始化 Docker 环境 (在脚本开头调用)
init_docker_compat() {
    setup_docker_compose
}
