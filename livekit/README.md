# LiveKit 视频会议部署件（矛盾纠纷调解平台）

单节点 `livekit-server` SFU 的 Docker 部署脚本，供 `mediation-ai` 会议模块（`meeting` 包）、
`mediation-web` 房间页与 `livekit-worker` 转录服务使用。

## 参考来源

本部署件按本机已部署实例 `mwb-livekit` 落地（配置在 `D:\projects\MinWorkBuddy\docker\livekit`，
`scratch/livekit.yaml` 是同一份配置副本）：

| 项 | 本机已部署 `mwb-livekit` | 本部署件 |
|---|---|---|
| 镜像 | `livekit-server:v1.13.11`（ACR 中转） | 同版本，`.env` 可换 DaoCloud/官方源 |
| 端口 | `7880/tcp` 信令、`7881/udp` 单媒体端口、`7882/tcp` ICE-TCP | 完全一致 |
| 配置 | `--config /etc/lk/config.yaml`，密钥写死 `devkey: secret` | 同挂载方式，密钥由 `.env` 渲染进模板 |
| Redis | 复用本机 `redis` 容器，走 `host.docker.internal:6379`（`infra_net` 与 `mwb-infra-network` 两网隔离） | 默认自带 Redis 同网络直连；也可 `REDIS_MODE=external` 复用 |
| 通告 IP | 无 `--node-ip`（通告 bridge 内网 `172.19.x.x`） | 显式 `--node-ip`，跨机可正常出图出声 |
| 网络 | `mwb-infra-network`（external） | `mediation-livekit-net`（固定名，worker 可加入） |

> **端口冲突**：本机 `mwb-livekit` 已占用 `7880/7881/7882`，`start` 会检测到并拒绝启动。
> 只是本地联调时直接复用现有实例即可（把后端 `LIVEKIT_*` 指向 `localhost:7880`）；
> 需要独立实例时先 `docker stop mwb-livekit`，或把整套文件拷到目标服务器再跑。

## 文件

| 文件 | 说明 |
|---|---|
| `docker-compose.yml` | `livekit-server` + 可选内置 `redis`；固定网络 `mediation-livekit-net` |
| `livekit.yaml.template` | v1.13.11 配置模板，`@XXX@` 占位符由脚本替换 |
| `livekit.yaml` | **生成物**，含明文密钥，已 gitignore；改配置请改 `.env` |
| `.env.example` / `.env` | 变量模板 / 实际配置（已 gitignore） |
| `deploy.ps1` | Windows 一键脚本（start/stop/down/restart/status/verify/logs/genkeys） |
| `deploy.sh` | Linux / WSL 同功能脚本 |

## 快速开始

```powershell
# Windows（PowerShell 7 / PowerShell Core；5.1 下中文提示可能乱码但功能可用）
cd D:\work\mediation_platform\mediation-deploy\livekit
Copy-Item .env.example .env
# 跨机部署：先改 .env 的 LIVEKIT_NODE_IP 为宿主机对客户端可达的 IP
.\deploy.ps1                    # 渲染配置 + 起 Redis + 起 LiveKit + 等待 GET / 200
.\deploy.ps1 -Action verify     # 冒烟验证
```

```bash
# Linux / WSL
cd mediation-deploy/livekit
cp .env.example .env
vim .env                        # 至少改 LIVEKIT_NODE_IP
chmod +x deploy.sh
./deploy.sh
./deploy.sh verify
```

改完 `.env`（密钥、node-ip、Redis 地址）必须用 `restart` 才会重新渲染并重建容器：

```powershell
.\deploy.ps1 -Action restart
# 或 ./deploy.sh restart
```

## 配置项（`.env`）

| 变量 | 默认 | 说明 |
|---|---|---|
| `LIVEKIT_IMAGE` | `crpi-.../livekit-server:v1.13.11` | 禁止 `latest`；本机已预拉 `docker.m.daocloud.io/livekit/livekit-server:v1.13.11` |
| `LIVEKIT_NODE_IP` | `127.0.0.1` | **跨机必改**，通告给客户端的媒体 IP，对应 CLI `--node-ip` |
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | `devkey` / `secret` | 必须与 ai-server、worker 完全一致；生产换 ≥32 位 |
| `REDIS_MODE` | `internal` | `internal` 用自带 Redis；`external` 复用已有 Redis |
| `LIVEKIT_REDIS_ADDRESS` | `redis:6379` | `external` 时改成真实地址（如 `host.docker.internal:6379`）；`internal` 时脚本强制 `redis:6379` |
| `LIVEKIT_REDIS_PASSWORD` | `mediation_livekit_redis` | 自带 Redis 的 `requirepass`；`external` 时填外部实例密码 |
| `REDIS_IMAGE` | `docker.m.daocloud.io/library/redis:7.4-alpine` | 内置 Redis 镜像 |
| `LIVEKIT_CONTAINER_NAME` / `REDIS_CONTAINER_NAME` | `mediation-livekit` / `mediation-livekit-redis` | 容器名 |

### 复用已有 Redis（外部模式）

```dotenv
REDIS_MODE=external
LIVEKIT_REDIS_ADDRESS=host.docker.internal:6379
LIVEKIT_REDIS_PASSWORD=<该 redis 的 requirepass>
```

Docker Desktop 原生解析 `host.docker.internal`；Linux 已由 compose 的
`extra_hosts: host.docker.internal:host-gateway` 兜底。外部模式下脚本不启动内置 Redis，
LiveKit 直接连指定地址；Redis 未就绪时 server 会重启重试，请先确认可达。

## 端口与防火墙

| 端口 | 协议 | 用途 | 方向 |
|---|---|---|---|
| 7880 | TCP | HTTP API（房间管理 / webhook）+ WebSocket 信令 | 客户端 → 服务器 |
| 7881 | UDP | 单一媒体端口（多路复用） | 客户端 ↔ 服务器 |
| 7882 | TCP | ICE-TCP 兜底 | 客户端 ↔ 服务器 |

服务器需放行 `7880/tcp`、`7881/udp`、`7882/tcp`。**不要**改宿主端口而不改容器内端口：
媒体端口会被通告给客户端，映射成不一致的端口会导致连上信令但无媒体。
内网 HTTP 页面用 `ws://`；前端若为 HTTPS，浏览器会拦 `ws://`（Mixed Content），
必须上 `wss://` + 证书（可加一层反代，本部署件不含 TLS 终止）。

## 与业务服务对接

### ai-server（`application.yaml` 的 `livekit.*`）

```dotenv
LIVEKIT_SERVER_URL=ws://<客户端可达 host>:7880     # 下发给浏览器
LIVEKIT_API_URL=http://<服务端可达 host>:7880      # 服务端探活
LIVEKIT_API_KEY=<与 .env 一致>
LIVEKIT_API_SECRET=<与 .env 一致>
```

`ai-server` 与 LiveKit 不在同一台机器时，这四个变量必须显式配置：默认值
`ws://localhost:7880` 会让浏览器连到 ai-server 所在机器的回环地址而失败。
前端不持有密钥，token 由 Java 侧 HS256 签发。

### livekit-worker

`LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` 与上面同源，并把 worker 加入同一网络：

```yaml
# worker 的 compose 片段
services:
  worker:
    networks:
      - mediation-livekit-net
networks:
  mediation-livekit-net:
    external: true
    name: mediation-livekit-net
```

已有容器也可 `docker network connect mediation-livekit-net <worker-container>`。

## 密钥轮换

```powershell
.\deploy.ps1 -Action genkeys        # 或 ./deploy.sh genkeys
```

脚本调用镜像内置 `generate-keys` 打印 `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`，
**不自动改写 `.env`**（避免与后端配置失配）。手动替换 `.env` 两行，同步 ai-server、
livekit-worker，再执行 `restart`。三处密钥不一致的典型症状是浏览器报
`LiveKit 密钥配置不一致` / `token 校验失败`。

## 离线 / 内网服务器部署

目标机无公网时，先在有镜像的机器上导出，再导入目标机：

```powershell
# 开发机
docker save <livekit-image> <redis-image> -o livekit-images.tar
# 传到目标机（按实际通道），然后：
docker load -i livekit-images.tar
# 把本目录 4 个文件（compose / template / .env.example / deploy 脚本）拷过去
# 目标机上改 .env 的 LIVEKIT_NODE_IP 为目标机 IP，执行 .\deploy.ps1 或 ./deploy.sh
```

## 验证

```powershell
.\deploy.ps1 -Action verify
# 等价手工检查：
curl.exe http://127.0.0.1:7880/                       # 无 /health；GET / 返回 200 即存活
docker exec mediation-livekit /livekit-server ports --config /etc/lk/config.yaml
docker logs mediation-livekit --tail 30               # 找 "livekit starting" 与 node IP
```

`verify` 依次断言：容器 running、`GET /` 200 **且本项目容器在运行**（避免同端口的
`mwb-livekit` 造成误判）、容器内端口配置 7880/7881/7882、`--node-ip` 已注入、
Redis PONG（external 模式跳过）、渲染产物密钥与 `.env` 一致、宿主 `7881/udp` 已映射。

## 已知坑（v1.13.x 实测）

| 现象 | 原因 / 规避 |
|---|---|
| 启动即 `could not parse config`、容器反复重启 | 写了 v1.13.x 已删字段：`rtc.use_websocket`、`rtc.hostname`、`auth`、`static_auth_secret`、`enable_egress`。模板已避开；通告 IP 只能走 CLI `--node-ip` |
| 连上信令但黑屏无声 | bridge 网络下 server 默认通告 `172.x` 容器 IP。跨机部署把 `LIVEKIT_NODE_IP` 设为宿主机对客户端可达的 IP |
| `.env` 里的密钥没生效 | LiveKit 不展开 YAML 的 `${VAR}`，`keys` 是 map 也不能靠 `LIVEKIT_*` 覆盖 → 必须由部署脚本渲染模板 |
| `docker compose up -d` 直接起失败 | 没跑脚本 → `livekit.yaml` 不存在，Docker 会把它建成目录。必须用 `deploy.ps1` / `deploy.sh` |
| 映射 50000-60000 UDP 卡死 | Windows Docker Desktop 映射万级端口极慢；模板固定单端口 `udp_port: 7881` |
| `/health` 404 | LiveKit 无标准健康端点，用 `GET /` 或 `ports` 子命令探活 |
| 生产误用 `--dev` | 会开 debug 日志与 pprof；本编排只用 `--config` + `--node-ip` |
| 录制/Egress 起不来 | 本部署件**不含 Egress**（会议能力设计 §9.3 明确本期不做录制落盘）。需要时参考 `D:\projects\MinWorkBuddy\docker\livekit` 的 `--profile record`：Egress 需同一 Redis 消息总线，Linux 生产建议 `network_mode: host` |
