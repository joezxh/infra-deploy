#!/bin/bash
echo "PostgreSQL + Neo4j 高可用集群启动"
cd "$(dirname "$0")"
docker compose up -d
echo "服务已启动"
