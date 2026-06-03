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

echo "MySQL + NebulaGraph 高可用集群启动"
cd "$(dirname "$0")"
$DOCKER_COMPOSE up -d
echo "服务已启动，访问 NebulaGraph: localhost:9669, 9670"
