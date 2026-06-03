# MySQL + Neo4j 版本 - 应用微服务单机版部署

## 概述

本版本使用 MySQL 作为关系数据库，Neo4j 作为图数据库，适用于开发、测试环境。

## 前置要求

1. **Docker 和 Docker Compose**
   - Docker 20.10+
   - Docker Compose 2.0+

2. **基础设施服务**
   - 请先启动基础设施服务：
   ```bash
   cd ../../infra/versions/mysql-neo4j/single
   docker compose up -d
   ```

## 快速启动

### Linux/macOS

```bash
# 启动服务
./start.sh mysql-neo4j single

# 检查服务状态
./check-health.sh mysql-neo4j single

# 停止服务
./stop.sh mysql-neo4j single
```

### Windows

```cmd
# 启动服务
start.bat mysql-neo4j single

# 检查服务状态
check-health.bat mysql-neo4j single

# 停止服务
stop.bat mysql-neo4j single
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
- **Neo4j Browser**: http://127.0.0.1:7474 (neo4j/mediation123)

## 配置说明

编辑 `.env` 文件来自定义配置：

```env
# 应用版本
APP_VERSION=latest

# Nacos 配置
NACOS_SERVER_ADDR=127.0.0.1:8848
NACOS_USERNAME=nacos
NACOS_PASSWORD=nacos

# MySQL 配置
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=mediation_db
DB_USERNAME=root
DB_PASSWORD=mediation123

# Redis 配置
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

# Neo4j 配置
NEO4J_HOST=127.0.0.1
NEO4J_PORT=7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=mediation123
```

## 日志查看

```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f gateway

# 查看本地日志文件
tail -f logs/gateway/gateway.log
```

## 数据持久化

所有数据通过 Docker volume 持久化：

- `mediation-video-data`: 视频文件存储
- `mediation-web-logs`: Web 日志

## 故障排查

### 服务启动失败

1. 检查基础设施是否正常运行：
   ```bash
   cd ../../infra/versions/mysql-neo4j/single
   docker compose ps
   ```

2. 检查端口占用：
   ```bash
   netstat -an | grep 8080
   ```

3. 查看日志：
   ```bash
   docker compose logs service_name
   ```

### 数据库连接失败

1. 确认 MySQL 服务正常运行
2. 检查 `.env` 中的数据库配置
3. 确认数据库已创建
