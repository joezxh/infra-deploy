# MySQL + Neo4j 单机版

快速启动矛盾纠纷调解平台基础设施 (MySQL + Neo4j 图数据库)

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| MySQL | 8.4.0 | 3306 | 主关系数据库 |
| Redis | 7.4 | 6379 | 缓存 |
| Nacos | 3.2.1 | 8848 | 配置中心 |
| Neo4j | 5.22 | 7474/7687 | 图数据库 (HTTP/Bolt) |
| MinIO | Latest | 9000/9001 | 对象存储 |

## 快速启动

```bash
cd versions/mysql-neo4j/single
./start.sh
```

## 手动启动

```bash
cd versions/mysql-neo4j/single
docker compose up -d
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| MySQL | localhost:3306 | root / mediation123 |
| Redis | localhost:6379 | 无 |
| Nacos | http://localhost:8848/nacos | nacos / nacos |
| Neo4j HTTP | http://localhost:7474 | neo4j / mediation123 |
| Neo4j Bolt | bolt://localhost:7687 | neo4j / mediation123 |
| MinIO | http://localhost:9000 | mediation / mediation123456 |

## 停止服务

```bash
docker compose down
```

## 查看日志

```bash
docker compose logs -f
docker compose logs -f neo4j
```

## 环境变量

创建 `.env` 文件覆盖默认配置:

```env
MYSQL_ROOT_PASSWORD=your_password
MYSQL_PASSWORD=your_password
REDIS_PASSWORD=redis123
NACOS_AUTH_ENABLE=false
NEO4J_PASSWORD=your_password
```

## 系统要求

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB
