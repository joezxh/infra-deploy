#!/bin/bash

# 兼容旧版 Docker 客户端
export DOCKER_API_VERSION=1.44

# 检测 docker compose 命令 (兼容 V1 和 V2)
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

echo "PostgreSQL + NebulaGraph 单机版启动"
cd "$SCRIPT_DIR"
$DOCKER_COMPOSE up -d
echo "服务已启动，访问 NebulaGraph: localhost:9669"
