# 部署向导 (README)

本文件描述**当前需要部署的基础设施底座**，以及面向 AI 会议能力的 4 个独立部署件（LiveKit / PP-OCRv6 / CompreFace / SER）的部署方法。

基础设施 = 数据库 / 缓存 / 配置中心 / 图数据库 / 对象存储 等共享依赖；AI 能力组件为解耦的独立 Docker Compose 部署件。两者均通过一键脚本部署。业务应用（`app/`）的部署请查阅 `app/` 目录自己的 README。

---

## 一、部署向导（先选后跑）

按下面三步决定你要启动的版本，然后直接复制最后一步的命令即可。

### 第 1 步：选主数据库

| 主数据库 | 适用场景 | 版本 |
|----------|----------|------|
| **MySQL 8.4** | 传统关系型业务，成熟稳定 | `mysql-*` |
| **PostgreSQL 17 + pgvector** | 需要向量检索（AI 场景） | `pg-*` |

### 第 2 步：选图数据库（可选）

| 图数据库 | 适用场景 | 版本后缀 |
|----------|----------|----------|
| **Neo4j 5.22** | 关系图谱，社区版开箱即用 | `*-neo4j` |
| **NebulaGraph 3.8** | 大规模图数据分析 | `*-nebula` |

> 不需要图能力的环境可只保留主数据库，去掉图数据库组件（见各版本 README）。

### 第 3 步：选部署模式

| 模式 | 适用 | 目录 |
|------|------|------|
| **single（单机）** | 开发 / 测试 / 单机生产 | `.../single` |
| **ha（高可用）** | 生产集群，含负载均衡冗余 | `.../ha` |

### 一键命令表（按选择查表执行）

**单机版**

```bash
# MySQL + Neo4j
cd infra/versions/mysql-neo4j/single && ./start.sh

# MySQL + NebulaGraph
cd infra/versions/mysql-nebula/single && ./start.sh

# PostgreSQL + Neo4j
cd infra/versions/pg-neo4j/single && ./start.sh

# PostgreSQL + NebulaGraph（推荐 AI 场景）
cd infra/versions/pg-nebula/single && ./start.sh
```

**高可用集群版**

```bash
# MySQL + Neo4j HA
cd infra/versions/mysql-neo4j/ha && ./start.sh

# MySQL + NebulaGraph HA
cd infra/versions/mysql-nebula/ha && ./start.sh

# PostgreSQL + Neo4j HA
cd infra/versions/pg-neo4j/ha && ./start.sh

# PostgreSQL + NebulaGraph HA
cd infra/versions/pg-nebula/ha && ./start.sh
```

选择示例：开发联调、需要向量检索 → 选 **PostgreSQL + Neo4j + 单机** → 执行 `cd infra/versions/pg-neo4j/single && ./start.sh`。

---

## 二、可部署版本总览

| 版本 | 主数据库 | 图数据库 | 适用场景 |
|------|----------|----------|----------|
| **mysql-neo4j** | MySQL 8.4 | Neo4j 5.22 | 传统业务，成熟稳定 |
| **mysql-nebula** | MySQL 8.4 | NebulaGraph 3.8 | 大规模图数据 |
| **pg-neo4j** | PostgreSQL 17 + pgvector | Neo4j 5.22 | 需要向量检索 |
| **pg-nebula** | PostgreSQL 17 + pgvector | NebulaGraph 3.8 | AI + 大规模图计算 |

每个版本下均含 `single/` 与 `ha/` 两个子目录，各自带 `docker-compose.yml`、`start.sh`、建库 SQL 与 README。

### 各版本组件清单

| 版本 | 组件 | 特点 |
|------|------|------|
| mysql-neo4j | MySQL 8.4 + Redis 7.4 + Nacos 3.2.1 + Neo4j 5.22 + MinIO | 成熟稳定的传统架构 |
| mysql-nebula | MySQL 8.4 + Redis 7.4 + Nacos 3.2.1 + NebulaGraph 3.8 + MinIO | MySQL 业务 + NebulaGraph 大规模图分析 |
| pg-neo4j | PostgreSQL 17 (pgvector) + Redis 7.4 + Nacos 3.2.1 + Neo4j 5.22 + MinIO | 向量检索 + 图关系分析 |
| pg-nebula | PostgreSQL 17 (pgvector) + Redis 7.4 + Nacos 3.2.1 + NebulaGraph 3.8 + MinIO | 全功能 AI + 图计算平台 |

各版本详细文档：
- [mysql-neo4j 单机](infra/versions/mysql-neo4j/single/README.md) / [HA](infra/versions/mysql-neo4j/ha/README.md)
- [mysql-nebula 单机](infra/versions/mysql-nebula/single/README.md) / [HA](infra/versions/mysql-nebula/ha/README.md)
- [pg-neo4j 单机](infra/versions/pg-neo4j/single/README.md) / [HA](infra/versions/pg-neo4j/ha/README.md)
- [pg-nebula 单机](infra/versions/pg-nebula/single/README.md) / [HA](infra/versions/pg-nebula/ha/README.md)

---

## 三、基础设施组件

| 组件 | 版本 | 用途 |
|------|------|------|
| MySQL | 8.4.0 | 主关系数据库（mysql 版本） |
| PostgreSQL | 17 + pgvector | 主数据库 + 向量存储（pg 版本） |
| Redis | 7.4 | 缓存 / Session |
| Nacos | 3.2.1 | 配置中心 + 服务注册 |
| Neo4j | 5.22 社区版 | 图数据库（关系图谱） |
| NebulaGraph | 3.8.0 社区版 | 图数据库（大规模图分析） |
| MinIO | Latest | 对象存储 |

---

## 四、服务端口

### 单机版

| 服务 | MySQL 版本 | PostgreSQL 版本 | 凭证 |
|------|------------|----------------|------|
| MySQL | 3306 | - | root / admin123 |
| PostgreSQL | - | 5432 | admin / admin123 |
| Redis | 6379 | 6379 | 无 |
| Nacos | 8848 | 8848 | nacos / nacos |
| Neo4j HTTP | 7474 | 7474 | neo4j / admin123 |
| Neo4j Bolt | 7687 | 7687 | neo4j / admin123 |
| NebulaGraph | 9669 | 9669 | - |
| MinIO Console | 9001 | 9001 | admin / admin123456 |

### 高可用集群

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL HAProxy | 33060 | 多主负载均衡 |
| PostgreSQL | 5435 | 通过 PgBouncer |
| Redis | 6379 | Sentinel 自动故障转移 |
| Redis Sentinel | 26379 | - |
| Nacos | 8848/8858/8868 | 3 节点集群 |
| Neo4j HAProxy | 7689/7476 | 2 节点负载均衡 |
| NebulaGraph | 9669/9670 | 2 Graph 节点 |
| HAProxy Admin | 8404 | admin / admin |

---

## 五、系统要求

### 单机版
- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB

### 高可用集群
- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

---

## 六、默认凭证

> **生产环境请务必修改默认密码！**

| 服务 | 用户名 | 密码 |
|------|--------|------|
| MySQL | root | admin123 |
| PostgreSQL | admin | admin123 |
| Redis | - | 无密码 |
| Nacos | nacos | nacos |
| Neo4j | neo4j | admin123 |
| MinIO | admin | admin123456 |

---

## 七、顶层脚本速查（infra/）

| 脚本 | 作用 | 常用命令 |
|------|------|----------|
| `start-mysql.sh` | 启动 MySQL 版单机基础设施 | `cd infra && ./start-mysql.sh` |
| `start-pg.sh` | 启动 PostgreSQL 版单机基础设施 | `cd infra && ./start-pg.sh` |
| `stop-all.sh` | 停止所有单机版 compose | `cd infra && ./stop-all.sh` |
| `backup.sh` | 全量备份 MySQL/PG/Redis/Neo4j/Nebula/MinIO，打包 `./backups/*.tar.gz`（保留 7 天） | `cd infra && ./backup.sh [single\|cluster]` |
| `check-health.sh` | 逐项探活（MySQL/PG/Redis/Nacos/Neo4j/MinIO）并汇总 | `cd infra && ./check-health.sh` |
| `docker-compat.sh` | 检测 `docker compose` V1/V2 并设置 `DOCKER_API_VERSION=1.44`，其它脚本 `source` 它 | — |

---

## 八、目录结构

```
infra-deploy/
├── README.md                     # 本文件
├── infra/                        # 基础设施部署（共享底座）
│   ├── README.md                 # 基础设施详细文档
│   ├── start-mysql.sh / start-pg.sh
│   ├── stop-all.sh
│   ├── backup.sh
│   ├── check-health.sh
│   ├── docker-compat.sh
│   ├── docker-compose.mysql.single.yml
│   ├── docker-compose.pg.single.yml
│   ├── haproxy-mysql.cfg
│   └── versions/                 # 版本化部署配置
│       ├── mysql-neo4j/{single,ha}/
│       ├── mysql-nebula/{single,ha}/
│       ├── pg-neo4j/{single,ha}/
│       └── pg-nebula/{single,ha}/
└── scripts/db/                   # Flyway 数据库迁移脚本 (V2026xxxx__*.sql)
```

---

## 九、AI 能力组件部署（livekit / paddle / compreface / ser）

以下 4 个为面向「AI 会议能力」的独立部署件，均为 Docker Compose + 一键脚本，彼此解耦、各自带 README；**默认不接入业务链路**，多数带上线门禁开关（详见各目录 README）。

### 组件总览

| 目录 | 部署件 | 用途 | 对外端口 |
|------|--------|------|----------|
| `livekit/` | 视频会议 SFU | 会议音视频信令 / 媒体 | 7880/tcp · 7881/udp · 7882/tcp |
| `paddle/` | PP-OCRv6 文本识别 | 证件 / 材料 OCR | 80（Nginx 反代） |
| `compreface/` | 人脸 1:1 比对 | 人像到场一致性核验 | 8050 / 8051(回环) |
| `ser/` | 声学情感识别 | 会议情绪识别 | 8020 / 8021 |

> 端口避让（同一宿主）：OCR `8011`、SER `8020/8021`、`paddle-nginx` `8080`、`80`（GPUStack 已占）、LiveKit `7880/7881/7882`、CompreFace `8050/8051`。

### 通用部署约定

- **一键脚本形态**：各组件提供 `deploy.ps1`（Windows/PowerShell）+ `deploy.sh`（Linux/WSL）或 PowerShell 专用脚本；首次运行自动从 `.env.example` 生成 `.env` 并注入随机 `API_KEY`（外层调用凭证）。
- **鉴权**：OCR / 人脸 / 声学三类推理服务统一用 Nginx 反代 + 请求头 `X-API-Key` 鉴权（缺失/错误返回 401/403），推理容器只绑 `127.0.0.1` 防直连绕过。
- **健康检查**：推理容器自带 `healthcheck`；对外暴露免鉴权探针（`/nginx-health`、`/ser-nginx-health`、`/face-nginx-health`）。
- **墙内构建**：Docker daemon 若继承系统死代理（`http.docker.internal:3128`）会导致镜像/权重下载失败，需置 `ProxyEnable=0` 并重启 Docker Desktop，或配置 `registry-mirrors`；PyPI 走清华源、Docker 镜像走 DaoCloud/阿里云中转。
- **门禁纪律**：AI 能力组件（compreface / ser / 人脸 OCR 链路）均带上线开关，未通过对应门禁前不得修改为接入业务链路。

### 1. 视频会议 — livekit/

单节点 `livekit-server` v1.13.11 SFU，供会议模块、`admin-web` 房间页与 `livekit-worker` 转录服务使用。

```powershell
cd livekit
Copy-Item .env.example .env      # 跨机部署先改 LIVEKIT_NODE_IP
.\deploy.ps1                      # 渲染 livekit.yaml + 起 Redis + 起 LiveKit + 等 GET / 200
.\deploy.ps1 -Action verify       # 冒烟验证
```

要点：`deploy.ps1`/`deploy.sh` 负责按 `.env` 渲染 `livekit.yaml`（LiveKit 不展开 YAML 变量）；`LIVEKIT_NODE_IP` 必须设为客户端可达 IP；`REDIS_MODE=internal|external` 可选；`GET /` 返回 200 即存活（无 `/health`）。详见 [livekit/README.md](livekit/README.md)。

### 2. 文本识别 — paddle/（PP-OCRv6）

PP-OCRv6 超轻量文本识别，CPU 推理、零显存，经 Nginx 反代 + `X-API-Key` 鉴权对外暴露（容器内 OCR 只绑 `127.0.0.1`）。

```powershell
cd paddle
.\scripts\deploy.ps1             # 生成随机 API_KEY -> 构建镜像 -> 启动 -> 等健康
.\scripts\verify.ps1             # 鉴权 401 + OCR 文本识别
```

接口：`POST http://localhost/ocr/v6/ocr`（multipart `image`）、`/ocr/v6/health`，均需 `X-API-Key`。权重在构建期烘焙进镜像（约 177MB），运行期不再联网。详见 [paddle/README.md](paddle/README.md)。

### 3. 人脸比对 — compreface/（1:1）

CompreFace 自托管人脸比对（Exadel 开源自托管平台，Apache-2.0），自定义 `compreface-core` 镜像（YuNet 检测 + SFace 识别，Apache-2.0 ONNX 权重）。**仅提供 1:1 `verification` 与 `detection`**，1:N 在 nginx 层 404 拒绝；平台不建人脸底库、不持久化向量。

```powershell
cd compreface
.\scripts\build-core.ps1         # 一次性构建自定义 core 镜像
Copy-Item .env.example .env      # 或让 deploy.ps1 自动生成随机 API_KEY
.\scripts\deploy.ps1             # compose up -d + 等 core/nginx healthy
.\scripts\verify.ps1             # 9 项契约验证
```

接口：经 `:8050` 带外层 `X-API-Key` —— `POST /face/api/v1/detection/detect`、`POST /face/api/v1/verification/verify`。双层密钥：业务侧只见外层 `API_KEY`，CompreFace 服务 key 由 nginx 按路径注入（detection 注 DET key、verification 注 VERIFY key）。数据库复用宿主 PostgreSQL（库 `compreface`）。详见 [compreface/README.md](compreface/README.md)。

### 4. 声学情感 — ser/

`emotion2vec_plus_large` 声学情感识别，推理容器（CPU 或 GPU）＋ Nginx 反代鉴权；输出平台 5 类 `{calm,anxious,agitated,anger,threat}`，3s 全静音拒答（不降级为 `calm`）。

```powershell
cd ser
Copy-Item .env.example .env      # 或让 deploy.ps1 生成随机 API_KEY
.\scripts\deploy.ps1             # build + up -d + 等 healthy (900s)
.\scripts\verify.ps1             # 五段契约验证
```

接口：经 `:8020/ser` 带 `X-API-Key` —— `POST /ser/v1/audio/emotion`（multipart `file`/`sample_rate`/`language`）、`GET /ser/health`；免鉴权探针 `/ser-nginx-health`。

> 版本分支：**CPU 分支**长音频 P95 远超 1500ms（延迟门禁 FAIL）；**GPU 分支 A**（`torch 2.7.1+cu128`、`emotion2vec:gpu-cu128`、项目名 `ser-gpu`、端口 8022/8023）预热后 P95 ≤566ms（PASS），但冷启动首轮不达标、须就绪探针预热。需 `Blackwell sm_120` 必须用 cu128。当前开关仍 `false`，未接入业务链路。详见 [ser/README.md](ser/README.md)。

---

## 十、常见问题

### Q: 如何选择版本？
- 传统业务系统：**mysql-neo4j**
- 需要 AI 向量检索：**pg-neo4j** 或 **pg-nebula**
- 大规模图数据分析：**mysql-nebula** 或 **pg-nebula**
- 综合 AI + 图计算：**pg-nebula**

### Q: Neo4j 社区版如何实现高可用？
Neo4j 社区版不支持原生集群，本方案采用：
1. 部署 2 个 Neo4j 实例
2. 使用 HAProxy 负载均衡
3. 通过备份恢复实现数据冗余

### Q: 如何扩展 NebulaGraph 集群？
```bash
docker compose scale nebula-storaged=5
docker compose scale nebula-graphd=3
```

### Q: 启动失败 / 端口被占用？
- 确认宿主 3306/5432/6379/8848/7474/7687/9669/9000/9001 未被占用
- 容器出网异常（镜像/权重拉取失败）多为系统死代理导致，置 `ProxyEnable=0` 并重启 Docker Desktop，或配置 `registry-mirrors`

更详细的环境变量、健康检查、备份恢复说明见 [infra/README.md](infra/README.md) 与各版本子目录 README。
