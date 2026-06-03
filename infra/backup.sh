#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 数据备份脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载 Docker 兼容性函数
source "$SCRIPT_DIR/docker-compat.sh" 2>/dev/null || {
    export DOCKER_API_VERSION=1.44
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        DOCKER_COMPOSE="docker compose"
    fi
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认配置
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mediation_backup_${TIMESTAMP}"
MODE="${1:-single}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 创建备份目录
create_backup_dir() {
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"
    log_info "备份目录: $BACKUP_DIR/$BACKUP_NAME"
}

# 备份 MySQL
backup_mysql() {
    log_info "备份 MySQL..."

    CONTAINER_NAME="mediation-mysql-single"
    if [ "$MODE" = "cluster" ]; then
        CONTAINER_NAME="mediation-mysql-cluster-1"
    fi

    docker exec "$CONTAINER_NAME" mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-mediation123}" \
        --all-databases \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --master-data=2 \
        --flush-logs \
        > "$BACKUP_DIR/$BACKUP_NAME/mysql_all.sql"

    log_info "MySQL 备份完成: mysql_all.sql"
}

# 备份 PostgreSQL
backup_postgres() {
    log_info "备份 PostgreSQL (pgvector)..."

    CONTAINER_NAME="mediation-postgres-single"
    if [ "$MODE" = "cluster" ]; then
        CONTAINER_NAME="mediation-patroni-1"
    fi

    docker exec "$CONTAINER_NAME" pg_dump -U "${PG_USER:-mediation}" \
        -Fc \
        -b \
        -v \
        -f "/tmp/postgres_backup.dump" \
        mediation_vector

    docker cp "$CONTAINER_NAME:/tmp/postgres_backup.dump" "$BACKUP_DIR/$BACKUP_NAME/postgres_vector.dump"

    log_info "PostgreSQL 备份完成: postgres_vector.dump"
}

# 备份 Redis
backup_redis() {
    log_info "备份 Redis..."

    CONTAINER_NAME="mediation-redis-single"
    if [ "$MODE" = "cluster" ]; then
        CONTAINER_NAME="mediation-redis-cluster-master"
    fi

    docker exec "$CONTAINER_NAME" redis-cli SAVE
    docker cp "$CONTAINER_NAME:/data/dump.rdb" "$BACKUP_DIR/$BACKUP_NAME/redis_dump.rdb"

    log_info "Redis 备份完成: redis_dump.rdb"
}

# 备份 Neo4j
backup_neo4j() {
    log_info "备份 Neo4j..."

    CONTAINER_NAME="mediation-neo4j-single"
    if [ "$MODE" = "cluster" ]; then
        CONTAINER_NAME="mediation-neo4j-cluster"
    fi

    docker exec "$CONTAINER_NAME" bin/neo4j-admin database dump neo4j --to-path=/backups/neo4j_backup_$(date +%Y%m%d).dump 2>/dev/null || \
    docker cp "$CONTAINER_NAME:/data" "$BACKUP_DIR/$BACKUP_NAME/neo4j_data"

    log_info "Neo4j 备份完成"
}

# 备份 NebulaGraph
backup_nebula() {
    log_info "备份 NebulaGraph..."

    # 备份 NebulaGraph 元数据
    docker exec mediation-nebula-metad-1 nebula-cluster-admin show-meta-snapshot 2>/dev/null || true

    # 复制数据目录
    docker cp nebula-storaged-1:/usr/local/nebula/data "$BACKUP_DIR/$BACKUP_NAME/nebula_data" 2>/dev/null || true

    log_info "NebulaGraph 备份完成"
}

# 备份 MinIO
backup_minio() {
    log_info "备份 MinIO..."

    # 使用 mc 客户端备份所有 bucket
    docker run --rm --network mediation-infra-network \
        -e MINIO_ROOT_USER="${MINIO_USER:-mediation}" \
        -e MINIO_ROOT_PASSWORD="${MINIO_PASSWORD:-mediation123456}" \
        minio/mc:latest \
        mc alias set local http://minio:9000 "${MINIO_USER:-mediation}" "${MINIO_PASSWORD:-mediation123456}" 2>/dev/null || true

    docker run --rm --network mediation-infra-network \
        -e MINIO_ROOT_USER="${MINIO_USER:-mediation}" \
        -e MINIO_ROOT_PASSWORD="${MINIO_PASSWORD:-mediation123456}" \
        -v "$BACKUP_DIR/$BACKUP_NAME/minio_buckets:/backup" \
        minio/mc:latest \
        mc mirror local/mediation-files /backup/ 2>/dev/null || true

    log_info "MinIO 备份完成"
}

# 创建备份元数据
create_metadata() {
    cat > "$BACKUP_DIR/$BACKUP_NAME/backup_info.json" << EOF
{
    "backup_time": "$(date -Iseconds)",
    "backup_mode": "$MODE",
    "hostname": "$(hostname)",
    "docker_version": "$(docker --version 2>/dev/null | head -1)",
    "backup_contents": [
        "mysql_all.sql",
        "postgres_vector.dump",
        "redis_dump.rdb",
        "neo4j_data",
        "nebula_data",
        "minio_buckets"
    ]
}
EOF
    log_info "备份元数据创建完成"
}

# 压缩备份
compress_backup() {
    log_info "压缩备份文件..."

    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    rm -rf "$BACKUP_NAME"

    log_info "备份压缩完成: ${BACKUP_NAME}.tar.gz"
    log_info "备份文件大小: $(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)"
}

# 清理旧备份 (保留最近 7 天)
cleanup_old_backups() {
    log_info "清理超过 7 天的旧备份..."

    find "$BACKUP_DIR" -name "mediation_backup_*.tar.gz" -mtime +7 -delete

    log_info "旧备份清理完成"
}

# 主函数
main() {
    echo ""
    echo "=============================================="
    echo "  矛盾纠纷调解平台 - 数据备份"
    echo "=============================================="
    echo ""
    echo "模式: $MODE"
    echo "备份目录: $BACKUP_DIR"
    echo ""

    create_backup_dir

    backup_mysql
    backup_postgres
    backup_redis
    backup_neo4j
    backup_nebula
    backup_minio

    create_metadata
    compress_backup
    cleanup_old_backups

    echo ""
    echo "=============================================="
    log_info "备份完成!"
    echo "=============================================="
}

main "$@"
