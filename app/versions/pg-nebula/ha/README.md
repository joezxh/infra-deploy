# PostgreSQL + NebulaGraph 版本 - 应用微服务高可用集群部署

## 概述

本版本使用 PostgreSQL 作为关系数据库（支持 pgvector 向量存储），NebulaGraph 作为分布式图数据库，采用多实例部署实现高可用，是生产环境推荐版本。

## 特性

- **PostgreSQL + pgvector**: 原生向量数据库支持，适合 AI 语义检索
- **NebulaGraph**: 分布式图数据库，适合大规模图分析
- **高可用**: 多实例部署，自动故障转移
- **生产就绪**: 完整的高可用架构

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务（HA 版本）：
   ```bash
   cd ../../infra/versions/pg-nebula/ha
   docker compose up -d
   ```

3. **资源要求**
   - 内存: 32GB+
   - CPU: 8核+

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh pg-nebula ha

# 检查服务状态
./check-health.sh pg-nebula ha

# 停止服务
./stop.sh pg-nebula ha
```

### Windows

```cmd
# 启动服务
start.bat pg-nebula ha

# 检查服务状态
check-health.bat pg-nebula ha

# 停止服务
stop.bat pg-nebula ha
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

## 高可用架构

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────┐          ┌────▼────┐          ┌────▼────┐
   │Gateway-1│          │Gateway-2│          │Gateway-N│
   └────┬────┘          └────┬────┘          └────┬────┘
        │                    │                    │
   ┌────┴────────────────────┴────────────────────┴────┐
   │                  Service Mesh                      │
   └────┬─────────┬────┬────┬─────────┬────┬────────────┘
        │         │    │    │         │    │
   ┌────▼───┐┌───▼─┐┌──▼─┐┌───▼─┐┌───▼─┐┌───▼─────┐
   │  UAA   ││Case ││Med.││ AI  ││Aux. ││ Others  │
   └────────┘└─────┘└────┘└─────┘└─────┘└─────────┘
        │         │    │    │         │
   ┌────┴─────────┴────┴────┴─────────┴────┐
   │          PostgreSQL + pgvector         │
   │              NebulaGraph               │
   └────────────────────────────────────────┘
```

## 配置说明

编辑 `.env` 文件来自定义配置：

```env
# 应用模式
APP_MODE=ha

# PostgreSQL HA 配置
PG_HOST=127.0.0.1
PG_PORT=5432
PG_NAME=mediation_db

# NebulaGraph 集群配置
NEBULA_GRAPH_HOST=127.0.0.1
NEBULA_GRAPH_PORT=9669

# 副本数配置 (HA 版本)
GATEWAY_REPLICAS=2
UAA_REPLICAS=2
SYSTEM_REPLICAS=2
CASE_REPLICAS=2
MEDIATION_REPLICAS=2
AI_REPLICAS=2

# JVM 配置
JAVA_XMS=512m
JAVA_XMX=2048m
JAVA_XMN=512m
```

## 生产部署建议

### 1. 外部负载均衡器
```nginx
upstream gateway_cluster {
    least_conn;
    server 127.0.0.1:8080 weight=5;
    server 127.0.0.1:8081 weight=3;
}

server {
    listen 80;
    location / {
        proxy_pass http://gateway_cluster;
    }
}
```

### 2. 数据库高可用
- PostgreSQL: 使用 PgBouncer 连接池 + 主从复制
- NebulaGraph: 官方集群模式

### 3. 监控告警
- Docker 健康检查
- 应用 Actuator 端点
- 数据库连接池
- 内存和 CPU 使用率
