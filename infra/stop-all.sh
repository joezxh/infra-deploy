#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 停止所有单机版服务
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo ""
echo "=============================================="
echo "  停止单机版基础设施"
echo "=============================================="
echo ""

# 停止所有版本
for compose_file in docker-compose.mysql.single.yml docker-compose.pg.single.yml; do
    if [ -f "$compose_file" ]; then
        log_info "停止 $compose_file ..."
        docker compose -f "$compose_file" down 2>/dev/null || true
    fi
done

# 停止开发版
if [ -f "docker-compose.dev.yml" ]; then
    log_info "停止 docker-compose.dev.yml ..."
    docker compose -f docker-compose.dev.yml down 2>/dev/null || true
fi

log_info "所有服务已停止"
echo ""
