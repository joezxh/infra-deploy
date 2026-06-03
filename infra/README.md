# 基础设施部署文档

## 概述

本目录包含矛盾纠纷调解平台所需的全部基础设施组件的 Docker Compose 部署配置。

### 基础设施组件

| 组件 | 版本 | 用途 |
|------|------|------|
| MySQL | 8.4.0 | 主关系数据库 |
| PostgreSQL | 17 + pgvector | 向量数据库 (AI向量化存储) |
| Redis | 7.4 | 缓存 / Session |
| Nacos | 3.2.1 | 配置中心 + 服务注册 |
| Neo4j | 5.22 | 图数据库 (关系图谱) |
| NebulaGraph | 3.8.0 | 图数据库 (大规模关系分析) |
| MinIO | Latest | 对象存储 |

## 部署版本

### 单机版部署

#### MySQL 版本 (使用 MySQL 作为主数据库)

```bash
cd infra

# 启动服务
./start-mysql.sh

# 查看状态
docker compose -f docker-compose.mysql.single.yml ps

# 停止服务
docker compose -f docker-compose.mysql.single.yml down
```

#### PostgreSQL 版本 (使用 PostgreSQL 作为主数据库 + pgvector)

```bash
cd infra

# 启动服务
./start-pg.sh

# 查看状态
docker compose -f docker-compose.pg.single.yml ps

# 停止服务
docker compose -f docker-compose.pg.single.yml down
```

### 高可用集群版 (Docker Compose)

在同一台机器上运行多个服务实例:

```bash
cd infra

# 启动集群
./start-cluster.sh

# 查看状态
docker compose -f docker-compose.cluster.yml ps

# 停止集群
./stop-cluster.sh
```

### 多服务器集群部署 (生产环境)

3 台服务器分别部署，实现真正的高可用:

```bash
# 详细步骤请参考: multi-server/DEPLOYMENT_GUIDE.md
```

## 部署架构

### 单机版架构

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Network                        │
│                   (mediation-infra)                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────┐  ┌────────┐  ┌────────┐  ┌──────────┐   │
│  │  MySQL  │  │ Redis  │  │ Nacos  │  │   Nginx  │   │
│  │  3306   │  │  6379  │  │  8848  │  │    80    │   │
│  └─────────┘  └────────┘  └────────┘  └──────────┘   │
│  或                                                      │
│  ┌───────────┐                                          │
│  │ PostgreSQL│                                          │
│  │   5432   │                                          │
│  └───────────┘                                          │
│                                                          │
│  ┌─────────┐  ┌──────────┐  ┌────────┐  ┌──────────┐   │
│  │  Neo4j  │  │NebulaGraph│ │ MinIO  │  │   Nginx  │   │
│  │  7474   │  │   9669   │  │  9000  │  │    80    │   │
│  │  7687   │  └──────────┘  │  9001  │  └──────────┘   │
│  └─────────┘                 └────────┘                  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 多服务器高可用架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     3-Server High Availability Cluster           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Server 1              Server 2              Server 3           │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐   │
│  │   DB Node-1 │◄──► │   DB Node-2 │◄──► │   DB Node-3 │   │
│  │   (Leader)  │      │  (Follower) │      │  (Follower) │   │
│  ├──────────────┤      ├──────────────┤      ├──────────────┤   │
│  │ Redis Master│      │Redis Replica │      │Redis Replica │   │
│  │   Sentinel  │      │   Sentinel   │      │   Sentinel   │   │
│  ├──────────────┤      ├──────────────┤      ├──────────────┤   │
│  │  Nacos-1   │◄──► │  Nacos-2   │◄──► │  Nacos-3   │   │
│  ├──────────────┤      ├──────────────┤      ├──────────────┤   │
│  │   Neo4j     │      │Nebula Meta-2 │      │Nebula Meta-3 │   │
│  │Nebula Meta-1│      │Nebula Graph-2│      │ Nebula Graph-3│   │
│  │Nebula Graph-1│     │Nebula Store-2│      │Nebula Store-3│   │
│  │Nebula Store-1│     └──────────────┘      └──────────────┘   │
│  ├──────────────┤                                          │   │
│  │ MinIO Node1 │◄─────────► MinIO Cluster ◄──────────────┤   │
│  └──────────────┘                                          │   │
│                                                              │   │
│  Server 3 还运行: HAProxy (数据库负载均衡)                   │
│                                                              │   │
└─────────────────────────────────────────────────────────────────┘
```

## 服务访问

### 单机版服务端口

| 服务 | MySQL 版本 | PostgreSQL 版本 | 默认凭证 |
|------|-----------|----------------|----------|
| MySQL | localhost:3306 | - | root / mediation123 |
| PostgreSQL | - | localhost:5432 | mediation / mediation123 |
| Redis | localhost:6379 | localhost:6379 | 无密码 |
| Nacos | http://localhost:8848/nacos | http://localhost:8848/nacos | nacos / nacos |
| Neo4j HTTP | http://localhost:7474 | http://localhost:7474 | neo4j / mediation123 |
| Neo4j Bolt | bolt://localhost:7687 | bolt://localhost:7687 | neo4j / mediation123 |
| NebulaGraph | localhost:9669 | localhost:9669 | - |
| MinIO API | http://localhost:9000 | http://localhost:9000 | mediation / mediation123456 |
| MinIO Console | http://localhost:9001 | http://localhost:9001 | mediation / mediation123456 |

### 多服务器集群服务端口

| 服务 | 地址 |
|------|------|
| MySQL HAProxy | Server3:33060 |
| PostgreSQL | Server3:5432 |
| Redis Sentinel | Server2:26379, Server3:26380 |
| Nacos 集群 | Server1-3:8848 |
| Neo4j | Server1:7474, 7687 |
| NebulaGraph | Server1:9669, Server2:9670 |
| MinIO Console | http://Server1:9001 |

## 环境变量配置

复制 `.env.example` 并根据需要修改:

```bash
cp .env.example .env
vi .env
```

主要配置项:

```env
# MySQL 配置
MYSQL_ROOT_PASSWORD=mediation123
MYSQL_USER=mediation
MYSQL_PASSWORD=mediation123

# PostgreSQL 配置
PG_USER=mediation
PG_PASSWORD=mediation123

# Redis 配置
REDIS_PASSWORD=redis123

# Nacos 配置
NACOS_AUTH_ENABLE=false

# Neo4j 配置
NEO4J_PASSWORD=mediation123
```

## 常用命令

```bash
# 查看服务状态
docker compose -f docker-compose.mysql.single.yml ps
docker compose -f docker-compose.pg.single.yml ps

# 查看日志
docker compose -f docker-compose.mysql.single.yml logs -f
docker compose -f docker-compose.pg.single.yml logs -f

# 查看特定服务日志
docker compose -f docker-compose.mysql.single.yml logs -f mysql

# 重启服务
docker compose -f docker-compose.mysql.single.yml restart

# 重新创建服务
docker compose -f docker-compose.mysql.single.yml up -d --force-recreate

# 删除数据卷 (完全重置)
docker compose -f docker-compose.mysql.single.yml down -v
```

## 数据备份

```bash
# 备份单机版数据
./backup.sh

# 备份文件保存在 ./backups 目录
```

## 系统要求

### 单机版

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB

### Docker Compose 集群版

- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

### 多服务器集群版

- CPU: 每台 8 核心+
- 内存: 每台 16 GB+
- 磁盘: 每台 100 GB+ SSD
- 网络: 千兆内网互通

## 组件版本

| 组件 | 单机版 | 集群版 |
|------|--------|--------|
| MySQL | 8.4.0 | 8.4.0 (Group Replication) |
| PostgreSQL | 17 + pgvector | 17 + pgvector (Patroni HA) |
| Redis | 7.4 | 7.4 (主从 + Sentinel) |
| Nacos | 3.2.1 | 3.2.1 (集群模式) |
| Neo4j | 5.22 社区版 | 5.22 社区版 |
| NebulaGraph | 3.8.0 社区版 | 3.8.0 社区版 |
| MinIO | Latest | Latest (Erasure Code) |
| HAProxy | - | 2.9 |
| etcd | - | 3.5 (PostgreSQL HA) |
| Consul | - | 1.17 (服务发现) |

## 常见问题

### Q: 如何选择 MySQL 版本还是 PostgreSQL 版本?

- 如果项目主要使用 MySQL，选择 **MySQL 版本**
- 如果需要 AI 向量检索功能，选择 **PostgreSQL 版本** (pgvector)
- 两种版本可以同时部署在不同环境

### Q: MySQL 集群初始化失败?

```bash
# 重置 MySQL 集群
docker compose -f docker-compose.cluster.yml down -v
docker compose -f docker-compose.cluster.yml up -d

# 等待 2-3 分钟让 MySQL 完成初始化
```

### Q: PostgreSQL Patroni 无法选举 Leader?

```bash
# 检查 etcd 状态
docker exec mediation-etcd etcdctl endpoint health

# 查看 Patroni 日志
docker logs mediation-postgres-cluster-1 --tail 100
```

### Q: 如何修改服务配置?

1. 编辑 `.env` 文件
2. 重新创建服务:

```bash
docker compose down
docker compose up -d
```

## 快速参考

```bash
# 启动 MySQL 版本
./start-mysql.sh

# 启动 PostgreSQL 版本
./start-pg.sh

# 停止所有服务
./stop-all.sh

# 健康检查
./check-health.sh

# 集群健康检查
./check-cluster-health.sh
```
