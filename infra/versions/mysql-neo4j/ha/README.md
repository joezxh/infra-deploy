# MySQL + Neo4j 高可用集群

生产级高可用部署，使用 MySQL Group Replication + Neo4j 负载均衡

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| MySQL | 8.4.0 | 33060 (HAProxy) | 3节点 Group Replication |
| Redis | 7.4 | 6379/26379 | 主从 + Sentinel |
| Nacos | 3.2.1 | 8848/8858/8868 | 3节点集群 |
| Neo4j | 5.22 | 7689/7476 (HAProxy) | 2节点 + HAProxy |
| MinIO | Latest | 9000-9030 | 4节点 Erasure Code |

## 快速启动

```bash
cd versions/mysql-neo4j/ha
./start.sh
```

## 手动启动

```bash
cd versions/mysql-neo4j/ha
docker compose up -d
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| MySQL HAProxy | localhost:33060 | root / mediation123 |
| Redis | localhost:6379 | redis123 |
| Redis Sentinel | localhost:26379 | - |
| Nacos-1 | http://localhost:8848/nacos | nacos / nacos |
| Nacos-2 | http://localhost:8858/nacos | nacos / nacos |
| Nacos-3 | http://localhost:8868/nacos | nacos / nacos |
| Neo4j HAProxy | localhost:7689/7476 | neo4j / mediation123 |
| MinIO Console | http://localhost:9001 | mediation / mediation123456 |
| HAProxy Admin | localhost:8404 | admin / admin |

## 架构

```
┌──────────────────────────────────────────────────────┐
│              MySQL + Neo4j HA Cluster                 │
├──────────────────────────────────────────────────────┤
│                                                      │
│  MySQL GR  ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│             │ Node-1  │◄►│ Node-2  │◄►│ Node-3  │   │
│             └────┬────┘ └────┬────┘ └────┬────┘   │
│                  └──────────┼──────────┘         │
│                              ▼                      │
│                      ┌──────────────┐               │
│                      │   HAProxy    │               │
│                      │   :33060     │               │
│                      └──────────────┘               │
│                                                      │
│  Neo4j HA    ┌─────────┐ ┌─────────┐ ┌──────────┐  │
│             │ Neo4j-1 │◄►│ Neo4j-2 │►│ HAProxy  │  │
│             └─────────┘ └─────────┘ │ :7689/7476│  │
│                                     └──────────┘  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## 系统要求

- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

## 初始化 MySQL 集群

首次部署后需要初始化 Group Replication:

```bash
# 在 mysql-1 容器执行
docker exec mediation-mysql-1 mysql -uroot -p'mediation123' -e "
SET GLOBAL group_replication_group_name = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
SET GLOBAL group_replication_bootstrap_group = ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group = OFF;
"
```

## 停止服务

```bash
docker compose down
```

## 查看集群状态

```bash
docker exec mediation-mysql-1 mysql -uroot -p'mediation123' -e "SELECT * FROM performance_schema.replication_group_members;"
```
