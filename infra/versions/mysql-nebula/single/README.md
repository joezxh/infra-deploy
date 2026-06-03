# MySQL + NebulaGraph 单机版

快速启动矛盾纠纷调解平台基础设施 (MySQL + NebulaGraph 图数据库)

## 组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| MySQL | 8.4.0 | 3306 | 主关系数据库 |
| Redis | 7.4 | 6379 | 缓存 |
| Nacos | 3.2.1 | 8848 | 配置中心 |
| NebulaGraph | 3.8.0 | 9669/9559/9779 | 图数据库 |
| MinIO | Latest | 9000/9001 | 对象存储 |

## 快速启动

```bash
cd versions/mysql-nebula/single
./start.sh
```

## 手动启动

```bash
cd versions/mysql-nebula/single
docker compose up -d
```

## 服务访问

| 服务 | 地址 | 凭证 |
|------|------|------|
| MySQL | localhost:3306 | root / mediation123 |
| Redis | localhost:6379 | 无 |
| Nacos | http://localhost:8848/nacos | nacos / nacos |
| NebulaGraph | localhost:9669 | - |
| NebulaGraph Meta | localhost:9559 | - |
| NebulaGraph Storage | localhost:9779 | - |
| MinIO | http://localhost:9000 | mediation / mediation123456 |

## NebulaGraph 客户端连接

```bash
# 使用 nebula-console 连接
docker run --rm -it vesoft/nebula-console:latest \
  -addr localhost -port 9669
```

## 停止服务

```bash
docker compose down
```

## 环境变量

```env
MYSQL_ROOT_PASSWORD=your_password
NEBULA_META_SEEDS=127.0.0.1:9559
```

## 系统要求

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB
