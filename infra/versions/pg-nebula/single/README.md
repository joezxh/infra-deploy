# PostgreSQL + NebulaGraph 单机版

快速启动矛盾纠纷调解平台基础设施 (PostgreSQL + pgvector + NebulaGraph)

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| PostgreSQL | 17 | 5432 | 主数据库 + pgvector |
| Redis | 7.4 | 6379 | 缓存 |
| Nacos | 3.2.1 | 8848 | 配置中心 |
| NebulaGraph | 3.8.0 | 9669/9559/9779 | 图数据库 |
| MinIO | Latest | 9000/9001 | 对象存储 |

## 特性

- PostgreSQL 内置 pgvector 扩展，支持向量检索
- NebulaGraph 提供大规模图数据处理能力
- 适合需要向量检索 + 图计算的综合 AI 场景

## 快速启动

```bash
cd versions/pg-nebula/single
./start.sh
```

## 手动启动

```bash
cd versions/pg-nebula/single
docker compose up -d
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| PostgreSQL | localhost:5432 | mediation / mediation123 |
| Redis | localhost:6379 | 无 |
| Nacos | http://localhost:8848/nacos | nacos / nacos |
| NebulaGraph | localhost:9669 | - |
| NebulaGraph Meta | localhost:9559 | - |
| NebulaGraph Storage | localhost:9779 | - |
| MinIO | http://localhost:9000 | mediation / mediation123456 |

## pgvector 示例

```sql
-- 创建向量扩展
CREATE EXTENSION IF NOT EXISTS vector;

-- 创建向量表
CREATE TABLE embeddings (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)
);

-- 插入向量数据
INSERT INTO embeddings (content, embedding) 
VALUES ('example', '[0.1, 0.2, ...]');

-- 相似度检索
SELECT * FROM embeddings 
ORDER BY embedding <=> '[0.1, 0.2, ...]' LIMIT 5;
```

## NebulaGraph 连接

```bash
docker run --rm -it vesoft/nebula-console:latest \
  -addr localhost -port 9669
```

## 停止服务

```bash
docker compose down
```

## 系统要求

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB
