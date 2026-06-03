# mediation-deploy

矛盾纠纷调解平台部署脚本和配置文件

## 部署版本选择

本项目提供 **4 种基础设施部署版本**，涵盖单机版和高可用集群:

| 版本 | 数据库 | 图数据库 | 适用场景 |
|------|--------|----------|----------|
| **mysql-neo4j** | MySQL 8.4 | Neo4j 5.22 | 传统业务，成熟稳定 |
| **mysql-nebula** | MySQL 8.4 | NebulaGraph 3.8 | 大规模图数据 |
| **pg-neo4j** | PostgreSQL 17 | Neo4j 5.22 | 需要向量检索 |
| **pg-nebula** | PostgreSQL 17 | NebulaGraph 3.8 | AI + 大规模图计算 |

## 快速开始

### 单机版 (开发/测试)

```bash
# MySQL + Neo4j
cd infra/versions/mysql-neo4j/single && ./start.sh

# MySQL + NebulaGraph
cd infra/versions/mysql-nebula/single && ./start.sh

# PostgreSQL + Neo4j
cd infra/versions/pg-neo4j/single && ./start.sh

# PostgreSQL + NebulaGraph (推荐 AI 场景)
cd infra/versions/pg-nebula/single && ./start.sh
```

### 高可用集群 (生产环境)

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

## 版本详情

### mysql-neo4j

- **组件**: MySQL 8.4 + Redis 7.4 + Nacos 3.2.1 + Neo4j 5.22 + MinIO
- **特点**: 成熟稳定的传统架构
- **单机版 README**: [versions/mysql-neo4j/single/README.md](infra/versions/mysql-neo4j/single/README.md)
- **高可用版 README**: [versions/mysql-neo4j/ha/README.md](infra/versions/mysql-neo4j/ha/README.md)

### mysql-nebula

- **组件**: MySQL 8.4 + Redis 7.4 + Nacos 3.2.1 + NebulaGraph 3.8 + MinIO
- **特点**: MySQL 业务数据 + NebulaGraph 大规模图分析
- **单机版 README**: [versions/mysql-nebula/single/README.md](infra/versions/mysql-nebula/single/README.md)
- **高可用版 README**: [versions/mysql-nebula/ha/README.md](infra/versions/mysql-nebula/ha/README.md)

### pg-neo4j

- **组件**: PostgreSQL 17 (pgvector) + Redis 7.4 + Nacos 3.2.1 + Neo4j 5.22 + MinIO
- **特点**: 支持向量检索 + 图关系分析
- **单机版 README**: [versions/pg-neo4j/single/README.md](infra/versions/pg-neo4j/single/README.md)
- **高可用版 README**: [versions/pg-neo4j/ha/README.md](infra/versions/pg-neo4j/ha/README.md)

### pg-nebula

- **组件**: PostgreSQL 17 (pgvector) + Redis 7.4 + Nacos 3.2.1 + NebulaGraph 3.8 + MinIO
- **特点**: 全功能 AI + 图计算平台
- **单机版 README**: [versions/pg-nebula/single/README.md](infra/versions/pg-nebula/single/README.md)
- **高可用版 README**: [versions/pg-nebula/ha/README.md](infra/versions/pg-nebula/ha/README.md)

## 基础设施组件

| 组件 | 版本 | 用途 |
|------|------|------|
| MySQL | 8.4.0 | 主关系数据库 (mysql 版本) |
| PostgreSQL | 17 + pgvector | 主数据库 + 向量存储 (pg 版本) |
| Redis | 7.4 | 缓存 / Session |
| Nacos | 3.2.1 | 配置中心 + 服务注册 |
| Neo4j | 5.22 社区版 | 图数据库 (关系图谱) |
| NebulaGraph | 3.8.0 社区版 | 图数据库 (大规模图分析) |
| MinIO | Latest | 对象存储 |

## 服务端口

### 单机版

| 服务 | MySQL 版本 | PostgreSQL 版本 | 凭证 |
|------|-----------|----------------|------|
| MySQL | 3306 | - | root / mediation123 |
| PostgreSQL | - | 5432 | mediation / mediation123 |
| Redis | 6379 | 6379 | 无 |
| Nacos | 8848 | 8848 | nacos / nacos |
| Neo4j HTTP | 7474 | 7474 | neo4j / mediation123 |
| Neo4j Bolt | 7687 | 7687 | neo4j / mediation123 |
| NebulaGraph | 9669 | 9669 | - |
| MinIO Console | 9001 | 9001 | mediation / mediation123456 |

### 高可用集群

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL HAProxy | 33060 | 多主负载均衡 |
| PostgreSQL | 5435 | 通过 PgBouncer |
| Redis | 6379 | Sentinel 自动故障转移 |
| Redis Sentinel | 26379 | - |
| Nacos | 8848/8858/8868 | 3节点集群 |
| Neo4j HAProxy | 7689/7476 | 2节点负载均衡 |
| NebulaGraph | 9669/9670 | 2 Graph 节点 |
| HAProxy Admin | 8404 | admin / admin |

## 系统要求

### 单机版

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB

### 高可用集群

- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

## 默认凭证

> **生产环境请务必修改默认密码！**

| 服务 | 用户名 | 密码 |
|------|--------|------|
| MySQL | root | mediation123 |
| PostgreSQL | mediation | mediation123 |
| Redis | - | 无密码 |
| Nacos | nacos | nacos |
| Neo4j | neo4j | mediation123 |
| MinIO | mediation | mediation123456 |

## 目录结构

```
mediation-deploy/
├── README.md                      # 本文件
├── docker-compose.dev.yml          # 开发环境配置 (旧)
│
├── infra/                         # 基础设施部署
│   ├── README.md                  # 基础设施文档
│   │
│   └── versions/                  # 版本化部署配置
│       │
│       ├── mysql-neo4j/
│       │   ├── single/            # 单机版
│       │   │   ├── docker-compose.yml
│       │   │   ├── start.sh
│       │   │   └── README.md
│       │   └── ha/               # 高可用版
│       │       ├── docker-compose.yml
│       │       ├── haproxy-*.cfg
│       │       ├── start.sh
│       │       └── README.md
│       │
│       ├── mysql-nebula/
│       │   ├── single/
│       │   └── ha/
│       │
│       ├── pg-neo4j/
│       │   ├── single/
│       │   └── ha/
│       │
│       └── pg-nebula/
│           ├── single/
│           └── ha/
│
└── app/                           # 应用部署 (微服务)
    ├── versions/                   # 应用部署版本
    │   ├── mysql-neo4j/
    │   │   ├── single/
    │   │   └── ha/
    │   ├── mysql-nebula/
    │   │   ├── single/
    │   │   └── ha/
    │   ├── pg-neo4j/
    │   │   ├── single/
    │   │   └── ha/
    │   └── pg-nebula/
    │       ├── single/
    │       └── ha/
    └── scripts/
        ├── start.sh / start.bat
        ├── stop.sh / stop.bat
        └── check-health.sh / check-health.bat
```

## 常见问题

### Q: 如何选择版本?

- 传统业务系统: **mysql-neo4j**
- 需要 AI 向量检索: **pg-neo4j** 或 **pg-nebula**
- 大规模图数据分析: **mysql-nebula** 或 **pg-nebula**
- 综合 AI + 图计算: **pg-nebula**

### Q: Neo4j 社区版如何实现高可用?

Neo4j 社区版不支持原生集群，本方案采用:
1. 部署 2 个 Neo4j 实例
2. 使用 HAProxy 负载均衡
3. 通过备份恢复实现数据冗余

### Q: 如何扩展 NebulaGraph 集群?

NebulaGraph 支持在线扩容:
```bash
docker compose scale nebula-storaged=5
docker compose scale nebula-graphd=3
```

## 相关文档

- [基础设施部署文档](infra/README.md)
- [各版本详细文档](infra/versions/)

## 应用部署 (app)

本项目还包括微服务应用的 Docker 部署脚本。

### 目录结构

```
app/
├── versions/                    # 应用部署版本
│   ├── mysql-neo4j/            # MySQL + Neo4j 版本
│   │   ├── single/            # 单机版
│   │   └── ha/                # 高可用版
│   ├── mysql-nebula/           # MySQL + NebulaGraph 版本
│   │   ├── single/
│   │   └── ha/
│   ├── pg-neo4j/              # PostgreSQL + Neo4j 版本
│   │   ├── single/
│   │   └── ha/
│   └── pg-nebula/             # PostgreSQL + NebulaGraph 版本
│       ├── single/
│       └── ha/
└── scripts/                    # 公共脚本
    ├── start.sh / start.bat
    ├── stop.sh / stop.bat
    └── check-health.sh / check-health.bat
```

### 快速启动应用服务

> **注意**: 应用服务依赖基础设施服务，请先启动 `infra` 再启动 `app`。

#### 1. 启动基础设施

```bash
# 选择版本启动基础设施 (以 mysql-neo4j 单机版为例)
cd infra/versions/mysql-neo4j/single && ./start.sh
```

#### 2. 启动应用服务

```bash
# 返回 app 目录
cd ../../app

# 启动应用 (使用相同的版本参数)
./scripts/start.sh mysql-neo4j single
```

#### 3. 验证服务

```bash
# 检查健康状态
./scripts/check-health.sh mysql-neo4j single
```

### 应用服务列表

| 服务 | 端口 | 描述 |
|------|------|------|
| Gateway | 8080 | API 网关 |
| UAA | 8081 | 认证服务 |
| System | 8082 | 系统服务 |
| Case | 8084 | 案件服务 |
| Mediation | 8085 | 调解服务 |
| AI | 8086 | AI 服务 |
| Harness | 8091 | Agent 编排 |
| Auxiliary | 8089 | 辅助服务 |
| Video | 8090 | 视频服务 |
| Dispatch | 8093 | 派发服务 |
| Content | 8094 | 内容服务 |
| Web | 80 | Web 控制台 |

### 部署版本对应关系

| 应用版本 | 基础设施版本 | 说明 |
|----------|-------------|------|
| mysql-neo4j | mysql-neo4j | MySQL + Neo4j，通用业务 |
| mysql-nebula | mysql-nebula | MySQL + NebulaGraph，大规模图 |
| pg-neo4j | pg-neo4j | PostgreSQL + Neo4j，向量检索 |
| pg-nebula | pg-nebula | PostgreSQL + NebulaGraph，完整AI栈 |

### 各版本详细文档

- [mysql-neo4j 单机版](app/versions/mysql-neo4j/single/README.md)
- [mysql-neo4j 高可用版](app/versions/mysql-neo4j/ha/README.md)
- [mysql-nebula 单机版](app/versions/mysql-nebula/single/README.md)
- [mysql-nebula 高可用版](app/versions/mysql-nebula/ha/README.md)
- [pg-neo4j 单机版](app/versions/pg-neo4j/single/README.md)
- [pg-neo4j 高可用版](app/versions/pg-neo4j/ha/README.md)
- [pg-nebula 单机版](app/versions/pg-nebula/single/README.md)
- [pg-nebula 高可用版](app/versions/pg-nebula/ha/README.md)
