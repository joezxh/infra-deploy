# MySQL + NebulaGraph 版本 - 应用微服务单机版部署

## 概述

本版本使用 MySQL 作为关系数据库，NebulaGraph 作为分布式图数据库，适用于需要处理大规模图数据的场景。

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务：
   ```bash
   cd ../../infra/versions/mysql-nebula/single
   docker compose up -d
   ```

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh mysql-nebula single

# 检查服务状态
./check-health.sh mysql-nebula single

# 停止服务
./stop.sh mysql-nebula single
```

### Windows

```cmd
# 启动服务
start.bat mysql-nebula single

# 检查服务状态
check-health.bat mysql-nebula single

# 停止服务
stop.bat mysql-nebula single
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
- **NebulaGraph Studio**: http://127.0.0.1:7001

## NebulaGraph 配置

NebulaGraph 服务配置在基础设施层，应用层通过环境变量连接：

```env
NEBULA_GRAPH_HOST=127.0.0.1
NEBULA_GRAPH_PORT=9669
```

## 与 Neo4j 版本对比

| 特性 | MySQL+Neo4j | MySQL+NebulaGraph |
|------|-------------|-------------------|
| 图数据库类型 | 单机图数据库 | 分布式图数据库 |
| 数据规模 | 中小规模 | 大规模 |
| 查询语言 | Cypher | nGQL |
| 适用场景 | 通用图场景 | 超大规模图分析 |

## NebulaGraph Studio 使用

1. 访问 NebulaGraph Studio: http://127.0.0.1:7001
2. 连接信息：
   - Host: `127.0.0.1:9669`
   - 用户名: `root`
   - 密码: `nebula` (在 infra 中配置)
