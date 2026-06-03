#!/bin/bash
echo "PostgreSQL + NebulaGraph 单机版启动"
cd "$(dirname "$0")"
docker compose up -d
echo "服务已启动，访问 NebulaGraph: localhost:9669"
