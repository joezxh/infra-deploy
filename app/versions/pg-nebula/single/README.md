# PostgreSQL + NebulaGraph 版本 - 应用微服务单机版部署

## 概述

本版本使用 PostgreSQL 作为关系数据库（支持 pgvector 向量存储），NebulaGraph 作为分布式图数据库，是最完整的 AI + 图分析组合。

## 特性

- **PostgreSQL + pgvector**: 原生向量数据库支持，适合 AI 语义检索
- **NebulaGraph**: 分布式图数据库，适合大规模图分析
- **完整 AI 栈**: 向量 + 图谱 + LLM

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务：
   ```bash
   cd ../../infra/versions/pg-nebula/single
   docker compose up -d
   ```

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh pg-nebula single

# 检查服务状态
./check-health.sh pg-nebula single

# 停止服务
./stop.sh pg-nebula single
```

### Windows

```cmd
# 启动服务
start.bat pg-nebula single

# 检查服务状态
check-health.bat pg-nebula single

# 停止服务
stop.bat pg-nebula single
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
- **NebulaGraph Studio**: http://127.0.0.1:7001

## AI + 图分析场景

本版本特别适合以下场景：

### 1. 案件关联分析
- 将案件信息存储在 PostgreSQL
- 使用 pgvector 存储案件语义向量
- 使用 NebulaGraph 分析案件关联关系

### 2. 智能调解
- AI 分析案件内容生成向量
- 图数据库发现相似案件和关联关系
- 向量检索快速匹配历史案例

### 3. 知识图谱
- NebulaGraph 存储实体关系
- PostgreSQL 存储详细属性
- pgvector 支持语义查询

## 与其他版本对比

| 特性 | mysql-neo4j | mysql-nebula | pg-neo4j | pg-nebula |
|------|-------------|--------------|----------|-----------|
| 向量支持 | ❌ | ❌ | ✅ | ✅ |
| 图数据库 | Neo4j | NebulaGraph | Neo4j | NebulaGraph |
| 推荐场景 | 通用图 | 超大图 | AI+图 | 完整AI栈 |
