#!/bin/bash
# ============================================================
# 矛盾纠纷调解平台 - 开发环境启动脚本 (Linux/macOS)
# ============================================================

set -e

echo ""
echo "============================================================"
echo "  矛盾纠纷调解平台 - 开发环境启动"
echo "============================================================"
echo ""

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "[错误] Docker 未安装，请先安装 Docker Desktop"
    exit 1
fi

# 检查 docker-compose 是否安装
if ! command -v docker-compose &> /dev/null; then
    echo "[错误] docker-compose 未安装"
    exit 1
fi

# ============================================================
# 配置 Docker 镜像加速器（国内源）
# ============================================================
configure_mirror() {
    local os_type=$(uname -s)
    local config_file=""

    if [ "$os_type" = "Linux" ]; then
        config_file="$HOME/.docker/daemon.json"
    elif [ "$os_type" = "Darwin" ]; then
        config_file="$HOME/.docker/daemon.json"
    else
        echo "[跳过] 非 Linux/macOS 系统，跳过镜像加速配置"
        return 0
    fi

    # 阿里云镜像加速器（需要替换为您的账号专属加速地址）
    # 获取方式: https://cr.console.aliyun.com/cn-hangzhou/instances/mirrors
    local aliyun_mirror="https://ung71beg.mirror.aliyuncs.com"

    # 创建配置目录
    mkdir -p "$(dirname "$config_file")"

    if [ -f "$config_file" ]; then
        # 检查是否已配置镜像加速器
        if grep -q "registry-mirrors" "$config_file"; then
            echo "[跳过] Docker 镜像加速器已配置，跳过"
        else
            echo "[配置] 添加 Docker 镜像加速器..."
            # 备份原配置
            cp "$config_file" "$config_file.bak.$(date +%s)"
            # 添加镜像加速器（保留原有配置）
            local temp_file=$(mktemp)
            cat "$config_file" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['registry-mirrors'] = ['$aliyun_mirror']
print(json.dumps(data, indent=2, ensure_ascii=False))
" > "$temp_file"
            mv "$temp_file" "$config_file"
            echo "[完成] 镜像加速器已添加，请重启 Docker Desktop 后重新运行此脚本"
            echo "[提示] 加速地址: $aliyun_mirror"
            exit 0
        fi
    else
        echo "[配置] 创建 Docker 镜像加速配置..."
        cat > "$config_file" << EOF
{
  "registry-mirrors": ["$aliyun_mirror"]
}
EOF
        echo "[完成] 镜像加速配置已创建，请重启 Docker Desktop 后重新运行此脚本"
        exit 0
    fi
}

# 尝试配置镜像加速器（非阻塞，失败不影响继续执行）
configure_mirror || true

echo "[1/4] 启动基础服务 (MySQL, Redis, Nacos, Sentinel, MinIO)..."
docker-compose -f docker-compose.dev.yml up -d

echo ""
echo "[2/4] 等待服务启动..."
sleep 30

echo ""
echo "[3/4] 检查服务健康状态..."
docker-compose -f docker-compose.dev.yml ps

echo ""
echo "[4/4] 验证镜像拉取情况..."
docker images | grep -E "mysql|redis|nacos|sentinel|minio|nginx" || true

echo ""
echo "============================================================"
echo "  服务启动完成！"
echo "============================================================"
echo ""
echo "访问地址:"
echo "  - Nacos 控制台:  http://localhost:8848/nacos (nacos/nacos)"
echo "  - Sentinel:      http://localhost:8858"
echo "  - MinIO Console: http://localhost:9001 (mediation/mediation123456)"
echo "  - API Gateway:   http://localhost:8080"
echo "  - MySQL:         localhost:3306 (mediation/mediation123)"
echo "  - Redis:         localhost:6379"
echo ""
echo "启动后端服务前，请先执行初始化SQL:"
echo "  mysql -h localhost -u mediation -p mediation_db < scripts/db/init.sql"
echo ""
