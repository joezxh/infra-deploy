# MySQL + NebulaGraph 高可用集群

生产级高可用部署，使用 MySQL Group Replication + NebulaGraph 集群

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| MySQL | 8.4.0 | 33060 (HAProxy) | 3节点 Group Replication |
| Redis | 7.4 | 6379/26379 | 主从 + Sentinel |
| Nacos | 3.2.1 | 8848/8858/8868 | 3节点集群 |
| NebulaGraph | 3.8.0 | 9669/9670 | 2 Meta + 3 Storage + 2 Graph |
| MinIO | Latest | 9000-9030 | 4节点 Erasure Code |

## 快速启动

```bash
cd versions/mysql-nebula/ha
./start.sh
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| MySQL HAProxy | localhost:33060 | root / mediation123 |
| Redis | localhost:6379 | redis123 |
| Redis Sentinel | localhost:26379 | - |
| Nacos 集群 | localhost:8848/8858/8868 | nacos / nacos |
| NebulaGraph-1 | localhost:9669 | - |
| NebulaGraph-2 | localhost:9670 | - |
| NebulaGraph Meta | localhost:9559/9560 | - |
| NebulaGraph Storage | localhost:9779-9781 | - |
| MinIO Console | http://localhost:9001 | mediation / mediation123456 |
| HAProxy Admin | localhost:8404 | admin / admin |

## 架构

```
┌──────────────────────────────────────────────────────┐
│            MySQL + NebulaGraph HA Cluster              │
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
│  NebulaGraph  ┌──────────────────────────────────┐  │
│               │  Meta-1 :9559  │  Meta-2 :9560  │  │
│               ├──────┬────────┴──────┬─────────┤  │
│               │Storage│Storage│Storage│Graph-1│Graph-2│
│               │ :9779  :9780  :9781  │ :9669  │ :9670  │
│               └──────────────────────┴─────────┘  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## 系统要求

- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

## 停止服务

```bash
docker compose down
```
