#!/usr/bin/env bash
# ============================================================
# 矛盾纠纷调解平台 - LiveKit 视频会议服务部署脚本 (Linux / WSL)
#
# 用法:
#   ./deploy.sh            生成 .env / 渲染 livekit.yaml / 起 Redis + LiveKit
#   ./deploy.sh restart    改完 .env（密钥、node-ip、Redis 地址）后强制重建
#   ./deploy.sh stop|down|status|verify|logs|genkeys|help
#
# 参考本机已部署实例 mwb-livekit（livekit-server v1.13.11）；
# 7880/7881/7882 已被其它容器占用时 start 会拒绝启动。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"
ENV_SAMPLE="$SCRIPT_DIR/.env.example"
TEMPLATE="$SCRIPT_DIR/livekit.yaml.template"
CONFIG="$SCRIPT_DIR/livekit.yaml"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

info() { echo -e "\033[36m[deploy]\033[0m $*"; }
ok()   { echo -e "\033[32m[  ok  ]\033[0m $*"; }
warn() { echo -e "\033[33m[ warn ]\033[0m $*"; }
fail() { echo -e "\033[31m[ fail ]\033[0m $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
用法: ./deploy.sh [start|stop|down|restart|status|verify|logs|genkeys|help]

  start    默认。生成 .env、按 .env 渲染 livekit.yaml、起内置 Redis + LiveKit
  restart  改动 .env 后必须用它：重新渲染 + --force-recreate
  verify   冒烟：GET / 200、ports 输出、--node-ip、Redis PONG、密钥一致
  genkeys  生成 >=32 位密钥对，手动写入 .env 并同步 ai-server / livekit-worker

注意：7880/7881/7882 已被本机 mwb-livekit 占用时 start 会拒绝启动。
EOF
}

# ---------------- Docker / Compose ----------------
declare -a DC=()

detect_compose() {
    command -v docker >/dev/null 2>&1 || fail "未找到 docker"
    docker info >/dev/null 2>&1 || fail "docker daemon 未运行"
    if docker compose version >/dev/null 2>&1; then
        DC=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
        DC=(docker-compose)
    else
        fail "未找到 docker compose / docker-compose"
    fi
    "${DC[@]}" -f "$COMPOSE_FILE" config -q >/dev/null 2>&1 \
        || fail "docker-compose.yml 语法检查失败：${DC[*]} -f $COMPOSE_FILE config"
}

compose() { "${DC[@]}" -f "$COMPOSE_FILE" "$@"; }

# ---------------- .env ----------------
ensure_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        [[ -f "$ENV_SAMPLE" ]] || fail "缺少 $ENV_SAMPLE"
        cp "$ENV_SAMPLE" "$ENV_FILE"
        warn "已由 .env.example 生成 .env；跨机部署请先改 LIVEKIT_NODE_IP 再执行 start"
    fi
}

load_env() {
    ensure_env
    # Windows/Git 检出的 .env 可能是 CRLF，直接 source 会把 \r 带进变量值
    set -a
    # shellcheck disable=SC1090
    . <(tr -d '\r' < "$ENV_FILE")
    set +a

    LIVEKIT_IMAGE="${LIVEKIT_IMAGE:-crpi-c762f77rjuytqer9.cn-hangzhou.personal.cr.aliyuncs.com/llm-basic/base/livekit-server:v1.13.11}"
    LIVEKIT_NODE_IP="${LIVEKIT_NODE_IP:-127.0.0.1}"
    LIVEKIT_API_KEY="${LIVEKIT_API_KEY:-devkey}"
    LIVEKIT_API_SECRET="${LIVEKIT_API_SECRET:-secret}"
    REDIS_MODE="${REDIS_MODE:-internal}"
    LIVEKIT_REDIS_ADDRESS="${LIVEKIT_REDIS_ADDRESS:-redis:6379}"
    LIVEKIT_REDIS_PASSWORD="${LIVEKIT_REDIS_PASSWORD:-mediation_livekit_redis}"
    LIVEKIT_CONTAINER_NAME="${LIVEKIT_CONTAINER_NAME:-mediation-livekit}"
    REDIS_CONTAINER_NAME="${REDIS_CONTAINER_NAME:-mediation-livekit-redis}"

    case "$REDIS_MODE" in
        internal) LIVEKIT_REDIS_ADDRESS="redis:6379" ;;
        external)
            [[ "$LIVEKIT_REDIS_ADDRESS" != "redis:6379" ]] \
                || fail "REDIS_MODE=external 时必须把 LIVEKIT_REDIS_ADDRESS 改成外部 Redis 地址"
            ;;
        *) fail "REDIS_MODE 只能是 internal / external，当前=$REDIS_MODE" ;;
    esac
    [[ "${LIVEKIT_API_KEY}${LIVEKIT_API_SECRET}" != *'"'* ]] \
        || fail "密钥不能包含双引号（会破坏渲染出的 YAML）"
}

# ---------------- 渲染 livekit.yaml ----------------
render_config() {
    [[ -f "$TEMPLATE" ]] || fail "缺少 $TEMPLATE"
    local text
    text="$(cat "$TEMPLATE")"
    text="${text//@LIVEKIT_API_KEY@/$LIVEKIT_API_KEY}"
    text="${text//@LIVEKIT_API_SECRET@/$LIVEKIT_API_SECRET}"
    text="${text//@LIVEKIT_REDIS_ADDRESS@/$LIVEKIT_REDIS_ADDRESS}"
    text="${text//@LIVEKIT_REDIS_PASSWORD@/$LIVEKIT_REDIS_PASSWORD}"
    printf '%s\n' "$text" > "$CONFIG"
    chmod 600 "$CONFIG" 2>/dev/null || true
    if grep -Eq '@[A-Z][A-Z0-9_]*@' "$CONFIG"; then
        fail "模板存在未替换占位符：$(grep -Eo '@[A-Z][A-Z0-9_]*@' "$CONFIG" | head -1)"
    fi
    ok "已渲染 livekit.yaml（含明文密钥，权限 600，请勿提交到版本库）"
}

# ---------------- 前置检查 / 等待 ----------------
check_port_conflict() {
    local occupied other
    occupied="$(docker ps --format '{{.Names}}|{{.Ports}}' | grep -E ':7880->|:7881->|:7882->' || true)"
    if [[ -n "$occupied" ]]; then
        other="$(printf '%s\n' "$occupied" | grep -v "^${LIVEKIT_CONTAINER_NAME}|" || true)"
        if [[ -n "$other" ]]; then
            printf '%s\n' "$other" >&2
            fail "7880/7881/7882 已被其它容器占用（本机已有 mwb-livekit 时会命中）。复用现有实例：把 ai-server 的 LIVEKIT_* 指向它；或先 docker stop mwb-livekit 再部署。"
        fi
    fi
}

http_code() {
    if command -v curl >/dev/null 2>&1; then
        curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:7880/ 2>/dev/null || echo "000"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null --timeout=3 http://127.0.0.1:7880/ && echo "200" || echo "000"
    else
        fail "需要 curl 或 wget 做存活探测"
    fi
}

wait_ready() {
    local i
    for i in $(seq 1 30); do
        if [[ "$(http_code)" == "200" ]]; then
            ok "LiveKit 信令存活（GET / => 200）"
            return 0
        fi
        sleep 1
    done
    fail "30s 内 GET http://127.0.0.1:7880/ 未返回 200；排查：docker logs $LIVEKIT_CONTAINER_NAME"
}

wait_redis_healthy() {
    local i st
    for i in $(seq 1 30); do
        st="$(docker inspect --format '{{.State.Health.Status}}' "$REDIS_CONTAINER_NAME" 2>/dev/null || echo missing)"
        [[ "$st" == "healthy" ]] && return 0
        [[ "$st" == "unhealthy" ]] && return 1
        sleep 2
    done
    return 1
}

# ---------------- 动作 ----------------
show_summary() {
    cat <<EOF

================ 部署完成 ================
信令(浏览器) : ws://${LIVEKIT_NODE_IP}:7880
API(服务端)  : http://${LIVEKIT_NODE_IP}:7880
API Key      : ${LIVEKIT_API_KEY}   (Secret 见 .env)
容器 / 网络  : ${LIVEKIT_CONTAINER_NAME} / mediation-livekit-net

ai-server 需配置（application.yaml 的 livekit.*）：
  LIVEKIT_SERVER_URL=ws://${LIVEKIT_NODE_IP}:7880
  LIVEKIT_API_URL=http://${LIVEKIT_NODE_IP}:7880
  LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
  LIVEKIT_API_SECRET=<与 .env 完全一致>
livekit-worker 需：LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET，并加入 mediation-livekit-net
EOF
    if [[ "$LIVEKIT_NODE_IP" == "127.0.0.1" || "$LIVEKIT_NODE_IP" == "localhost" ]]; then
        warn "node-ip 为回环：仅本机浏览器可用；跨机部署必须改 .env 的 LIVEKIT_NODE_IP"
    fi
    if [[ "$LIVEKIT_API_KEY" == "devkey" ]]; then
        warn "仍为默认密钥 devkey/secret；生产请执行 ./deploy.sh genkeys 并同步后端"
    fi
    echo "冒烟验证： ./deploy.sh verify"
}

do_start() {
    local recreate="${1:-}"
    load_env
    render_config
    check_port_conflict

    info "镜像：$LIVEKIT_IMAGE"
    if [[ "$REDIS_MODE" == "internal" ]]; then
        info "启动内置 Redis（$REDIS_CONTAINER_NAME，地址 $LIVEKIT_REDIS_ADDRESS）"
        compose up -d redis
        wait_redis_healthy || fail "内置 Redis 未 healthy；查看 docker logs $REDIS_CONTAINER_NAME 后重试"
        ok "Redis healthy"
    else
        info "REDIS_MODE=external：跳过内置 Redis，server 将连 $LIVEKIT_REDIS_ADDRESS"
    fi

    info "启动 LiveKit Server（--node-ip $LIVEKIT_NODE_IP）"
    if [[ -n "$recreate" ]]; then
        compose up -d --force-recreate livekit-server
    else
        compose up -d livekit-server
    fi
    wait_ready
    show_summary
}

do_verify() {
    load_env
    local pass=0 failed=0 detail
    assert() {
        if [[ "$2" == "true" ]]; then
            echo -e "\033[32m[ pass ]\033[0m $1  $3"; pass=$((pass + 1))
        else
            echo -e "\033[31m[ FAIL ]\033[0m $1  $3"; failed=$((failed + 1))
        fi
    }

    detail="$(docker inspect --format '{{.State.Status}}' "$LIVEKIT_CONTAINER_NAME" 2>/dev/null || echo missing)"
    [[ "$detail" == "running" ]] && assert "容器运行" true "$detail" || assert "容器运行" false "$detail"

    # 同端口若跑着别的 LiveKit（例如本机 mwb-livekit），HTTP 200 不能算本部署件存活
    self_running="$(docker ps --format '{{.Names}}' | grep -Fx "$LIVEKIT_CONTAINER_NAME" || true)"
    detail="$(http_code)"
    if [[ "$detail" == "200" && -n "$self_running" ]]; then
        assert "GET / => 200" true "HTTP 200 (本项目容器运行中)"
    else
        assert "GET / => 200" false "HTTP $detail, 本项目容器运行中=$([[ -n "$self_running" ]] && echo yes || echo no)"
    fi

    detail="$(docker exec "$LIVEKIT_CONTAINER_NAME" /livekit-server ports --config /etc/lk/config.yaml 2>/dev/null | tr '\n' ' ' || true)"
    if [[ "$detail" == *7880* && "$detail" == *7881* && "$detail" == *7882* ]]; then
        assert "端口 7880/7881/7882" true "$detail"
    else
        assert "端口 7880/7881/7882" false "$detail"
    fi

    detail="$(docker inspect --format '{{json .Config.Cmd}}' "$LIVEKIT_CONTAINER_NAME" 2>/dev/null || true)"
    [[ "$detail" == *"--node-ip"* ]] && assert "--node-ip 已生效" true "$detail" || assert "--node-ip 已生效" false "$detail"

    if [[ "$REDIS_MODE" == "internal" ]]; then
        detail="$(docker exec "$REDIS_CONTAINER_NAME" redis-cli -a "$LIVEKIT_REDIS_PASSWORD" ping 2>/dev/null || true)"
        [[ "$detail" == *PONG* ]] && assert "Redis PONG" true "$detail" || assert "Redis PONG" false "$detail"
    else
        warn "REDIS_MODE=external：跳过容器内 ping，请确认 server 已连上外部 Redis"
    fi

    if [[ -f "$CONFIG" ]] && grep -qF "\"${LIVEKIT_API_KEY}\": \"${LIVEKIT_API_SECRET}\"" "$CONFIG"; then
        assert "密钥与 .env 一致" true "livekit.yaml keys"
    else
        assert "密钥与 .env 一致" false "livekit.yaml keys 与 .env 不符或文件缺失"
    fi

    detail="$(docker ps --format '{{.Names}}|{{.Ports}}' | grep -F "${LIVEKIT_CONTAINER_NAME}|" || true)"
    [[ "$detail" == *"7881/udp"* ]] && assert "UDP 7881 已映射" true "$detail" || assert "UDP 7881 已映射" false "$detail"

    echo ""
    echo "===== 汇总：pass=$pass fail=$failed ====="
    [[ "$failed" -eq 0 ]] || exit 1
}

do_genkeys() {
    load_env
    info "用 $LIVEKIT_IMAGE 生成密钥对 ..."
    docker run --rm --entrypoint /livekit-server "$LIVEKIT_IMAGE" generate-keys
    echo ""
    warn "本命令不改写 .env：请手动替换两行，并同步 ai-server 的 LIVEKIT_API_KEY / LIVEKIT_API_SECRET 与 livekit-worker"
    echo "       然后执行 ./deploy.sh restart 使新密钥生效"
}

# ---------------- 主流程 ----------------
ACTION="${1:-start}"
case "$ACTION" in
    -h|--help|help) usage; exit 0 ;;
esac

detect_compose

case "$ACTION" in
    start)        do_start ;;
    restart)      do_start --force-recreate ;;
    stop)         compose stop; ok "已停止容器（数据卷保留）" ;;
    down)         compose down; ok "已移除容器（数据卷 redis_data 保留）" ;;
    status)
        compose ps
        code="$(http_code)"
        [[ "$code" == "200" ]] && ok "GET / => 200（信令存活）" || warn "GET / => $code（未就绪）"
        load_env
        info "配置：node-ip=$LIVEKIT_NODE_IP  redis=$LIVEKIT_REDIS_ADDRESS  key=$LIVEKIT_API_KEY"
        ;;
    verify)  do_verify ;;
    logs)    compose logs -f "${2:-livekit-server}" ;;
    genkeys) do_genkeys ;;
    *)       usage; exit 1 ;;
esac
