#!/bin/bash
echo "MySQL + NebulaGraph 高可用集群启动"
cd "$(dirname "$0")"
docker compose up -d
echo "服务已启动，访问 NebulaGraph: localhost:9669, 9670"
