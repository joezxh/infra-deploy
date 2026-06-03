# PostgreSQL + Neo4j 单机版

快速启动矛盾纠纷调解平台基础设施 (PostgreSQL + pgvector + Neo4j)

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| PostgreSQL | 17 | 5432 | 主数据库 + pgvector |
| Redis | 7.4 | 6379 | 缓存 |
| Nacos | 3.2.1 | 8848 | 配置中心 |
| Neo4j | 5.22 | 7474/7687 | 图数据库 |
| MinIO | Latest | 9000/9001 | 对象存储 |

## 特性

- PostgreSQL 内置 pgvector 扩展，支持向量检索
- 适合 AI 场景的向量存储

## 快速启动

```bash
cd versions/pg-neo4j/single
./start.sh
```

## 手动启动

```bash
cd versions/pg-neo4j/single
docker compose up -d
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| PostgreSQL | localhost:5432 | mediation / mediation123 |
| Redis | localhost:6379 | 无 |
| Nacos | http://localhost:8848/nacos | nacos / nacos |
| Neo4j HTTP | http://localhost:7474 | neo4j / mediation123 |
| Neo4j Bolt | bolt://localhost:7687 | neo4j / mediation123 |
| MinIO | http://localhost:9000 | mediation / mediation123456 |

## 创建向量扩展

PostgreSQL 启动后会自动启用 pgvector 扩展

## 停止服务

```bash
docker compose down
```

## 系统要求

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB
