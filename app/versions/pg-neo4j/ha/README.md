# PostgreSQL + Neo4j 版本 - 应用微服务高可用集群部署

## 概述

本版本使用 PostgreSQL 作为关系数据库（支持 pgvector 向量存储），Neo4j 作为图数据库，采用多实例部署实现高可用。

## 特性

- **PostgreSQL + pgvector**: 原生向量数据库支持，适合 AI 语义检索
- **Neo4j**: 图数据库，适合关系分析
- **高可用**: 多实例部署，自动故障转移

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务（HA 版本）：
   ```bash
   cd ../../infra/versions/pg-neo4j/ha
   docker compose up -d
   ```

3. **资源要求**
   - 内存: 16GB+
   - CPU: 4核+

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh pg-neo4j ha

# 检查服务状态
./check-health.sh pg-neo4j ha

# 停止服务
./stop.sh pg-neo4j ha
```

### Windows

```cmd
# 启动服务
start.bat pg-neo4j ha

# 检查服务状态
check-health.bat pg-neo4j ha

# 停止服务
stop.bat pg-neo4j ha
```

## 服务列表

| 服务 | 端口 | 副本数 | 描述 |
|------|------|--------|------|
| Gateway | 8080 | 2 | API 网关 |
| UAA | 8081 | 2 | 认证服务 |
| System | 8082 | 2 | 系统服务 |
| Case | 8084 | 2 | 案件服务 |
| Mediation | 8085 | 2 | 调解服务 |
| AI | 8086 | 2 | AI 服务 |
| Harness | 8091 | 1 | Agent 编排 |
| Auxiliary | 8089 | 1 | 辅助服务 |
| Video | 8090 | 1 | 视频服务 |
| Dispatch | 8093 | 1 | 派发服务 |
| Content | 8094 | 1 | 内容服务 |
| Web | 80 | 1 | Web 控制台 |

## 高可用特性

- **Gateway**: 2 副本，通过负载均衡提供服务
- **UAA**: 2 副本，支持会话保持
- **核心业务服务**: 2 副本，分布式部署
- **Neo4j**: HA 集群，通过负载均衡器访问

## 配置说明

编辑 `.env` 文件来自定义配置：

```env
# PostgreSQL HA 配置
PG_HOST=127.0.0.1
PG_PORT=5432
PG_NAME=mediation_db
PG_USERNAME=mediation
PG_PASSWORD=mediation123

# Neo4j HA 配置
NEO4J_HOST=127.0.0.1
NEO4J_PORT=7687

# 副本数配置
JAVA_XMS=512m
JAVA_XMX=2048m
JAVA_XMN=512m
```
