# PostgreSQL + NebulaGraph 高可用集群

生产级高可用部署，使用 PostgreSQL Patroni HA + NebulaGraph 集群

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| PostgreSQL | 17 | 5435 (PgBouncer) | 3节点 Patroni HA + pgvector |
| etcd | 3.5 | 2379 | 分布式协调 |
| PgBouncer | Latest | 5435 | 连接池 |
| Redis | 7.4 | 6379/26379 | 主从 + Sentinel |
| Nacos | 3.2.1 | 8848/8858/8868 | 3节点集群 |
| NebulaGraph | 3.8.0 | 9669/9670 | 2 Meta + 3 Storage + 2 Graph |
| MinIO | Latest | 9000-9030 | 4节点 Erasure Code |

## 特性

- PostgreSQL Patroni 自动故障转移
- pgvector + NebulaGraph 双重向量/图数据支持
- 适合大规模 AI + 图计算场景

## 快速启动

```bash
cd versions/pg-nebula/ha
./start.sh
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| PostgreSQL | localhost:5435 | mediation / mediation123 |
| Redis | localhost:6379 | redis123 |
| Redis Sentinel | localhost:26379 | - |
| Nacos 集群 | localhost:8848/8858/8868 | nacos / nacos |
| NebulaGraph-1 | localhost:9669 | - |
| NebulaGraph-2 | localhost:9670 | - |
| NebulaGraph Meta | localhost:9559/9560 | - |
| NebulaGraph Storage | localhost:9779-9781 | - |
| MinIO Console | http://localhost:9001 | mediation / mediation123456 |

## Patroni 集群状态

```bash
docker exec mediation-postgres-1 patronictl list
```

## NebulaGraph 状态

```bash
docker exec mediation-nebula-console nebula -u root -p mediation123 -e "SHOW HOSTS;"
```

## 系统要求

- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

## 停止服务

```bash
docker compose down
```
