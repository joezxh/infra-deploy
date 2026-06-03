# MySQL + Neo4j 版本 - 应用微服务高可用集群部署

## 概述

本版本使用 MySQL 作为关系数据库，Neo4j 作为图数据库，采用多实例部署实现高可用。

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务（HA 版本）：
   ```bash
   cd ../../infra/versions/mysql-neo4j/ha
   docker compose up -d
   ```

3. **资源要求**
   - 内存: 16GB+
   - CPU: 4核+

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh mysql-neo4j ha

# 检查服务状态
./check-health.sh mysql-neo4j ha

# 停止服务
./stop.sh mysql-neo4j ha
```

### Windows

```cmd
# 启动服务
start.bat mysql-neo4j ha

# 检查服务状态
check-health.bat mysql-neo4j ha

# 停止服务
stop.bat mysql-neo4j ha
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
- **System**: 2 副本，分布式缓存
- **Case/Mediation/AI**: 2 副本，数据库连接池共享

## 配置说明

编辑 `.env` 文件来自定义配置：

```env
# 副本数配置
GATEWAY_REPLICAS=2
UAA_REPLICAS=2
SYSTEM_REPLICAS=2
CASE_REPLICAS=2
MEDIATION_REPLICAS=2
AI_REPLICAS=2

# JVM 配置 (HA 版本建议增加)
JAVA_XMS=512m
JAVA_XMX=2048m
JAVA_XMN=512m
```

## 负载均衡

HA 版本推荐在 Gateway 前配置外部负载均衡器：

```nginx
upstream gateway {
    server 127.0.0.1:8080;
    # 如果有多个实例
    # server 127.0.0.1:8080 backup;
}

server {
    listen 80;
    location / {
        proxy_pass http://gateway;
    }
}
```

## 监控

建议配置以下监控：

- Docker 容器健康状态
- 应用 Actuator 端点 (`/actuator/health`)
- 数据库连接池状态
- 内存和 CPU 使用率

## 日志查看

```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务所有副本日志
docker compose logs -f --tail=100 gateway

# 查看本地日志文件
ls -la logs/gateway/
```
