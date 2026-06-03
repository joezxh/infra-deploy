# MySQL + NebulaGraph 版本 - 应用微服务高可用集群部署

## 概述

本版本使用 MySQL 作为关系数据库，NebulaGraph 作为分布式图数据库，采用多实例部署实现高可用。

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务（HA 版本）：
   ```bash
   cd ../../infra/versions/mysql-nebula/ha
   docker compose up -d
   ```

3. **资源要求**
   - 内存: 16GB+
   - CPU: 4核+

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh mysql-nebula ha

# 检查服务状态
./check-health.sh mysql-nebula ha

# 停止服务
./stop.sh mysql-nebula ha
```

### Windows

```cmd
# 启动服务
start.bat mysql-nebula ha

# 检查服务状态
check-health.bat mysql-nebula ha

# 停止服务
stop.bat mysql-nebula ha
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
- **NebulaGraph**: 分布式集群，自动故障转移

## 配置说明

编辑 `.env` 文件来自定义配置：

```env
# NebulaGraph 集群配置
NEBULA_GRAPH_HOST=127.0.0.1
NEBULA_GRAPH_PORT=9669
NEBULA_META_HOST=127.0.0.1
NEBULA_META_PORT=9559

# 副本数配置
GATEWAY_REPLICAS=2
UAA_REPLICAS=2
SYSTEM_REPLICAS=2
```
