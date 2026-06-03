# PostgreSQL + Neo4j 版本 - 应用微服务单机版部署

## 概述

本版本使用 PostgreSQL 作为关系数据库（支持 pgvector 向量存储），Neo4j 作为图数据库，适用于 AI 向量检索场景。

## 特性

- **PostgreSQL + pgvector**: 原生向量数据库支持，适合 AI 语义检索
- **Neo4j**: 图数据库，适合关系分析
- **向量存储**: 支持将 AI 生成的向量存储在 PostgreSQL 中

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务：
   ```bash
   cd ../../infra/versions/pg-neo4j/single
   docker compose up -d
   ```

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh pg-neo4j single

# 检查服务状态
./check-health.sh pg-neo4j single

# 停止服务
./stop.sh pg-neo4j single
```

### Windows

```cmd
# 启动服务
start.bat pg-neo4j single

# 检查服务状态
check-health.bat pg-neo4j single

# 停止服务
stop.bat pg-neo4j single
```

## 服务列表

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

## 访问地址

- **Gateway**: http://127.0.0.1:8080
- **Nacos**: http://127.0.0.1:8848/nacos (nacos/nacos)
- **Web 控制台**: http://127.0.0.1:80
- **PostgreSQL**: localhost:5432
- **Neo4j Browser**: http://127.0.0.1:7474

## PostgreSQL 配置

数据库配置使用 PostgreSQL 环境变量：

```env
PG_HOST=127.0.0.1
PG_PORT=5432
PG_NAME=mediation_db
PG_USERNAME=mediation
PG_PASSWORD=mediation123
```

## pgvector 使用

pgvector 扩展已预装在 PostgreSQL 镜像中，支持向量操作：

```sql
-- 创建向量列
CREATE TABLE IF NOT EXISTS document_embeddings (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)
);

-- 相似度查询
SELECT * FROM document_embeddings 
ORDER BY embedding <=> '[0.1, 0.2, ...]'
LIMIT 5;
```

## 与 MySQL 版本对比

| 特性 | MySQL 版本 | PostgreSQL 版本 |
|------|-----------|----------------|
| 向量支持 | 需额外插件 | 原生 pgvector |
| JSON 支持 | 一般 | 原生 JSONB |
| 全文搜索 | LIKE | 全文索引 |
| 适用场景 | 通用业务 | AI + 图分析 |
