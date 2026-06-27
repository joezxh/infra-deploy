# mediation-deploy

矛盾纠纷调解平台部署脚本和配置文件

## 需求目标

### 解决的问题

调解平台在引入大语言模型（LLM）辅助调解工作时，面临以下核心挑战：

1. **AI 输出不可控**：LLM 可能自由生成法律条文、编造法条引用，输出的法律依据无从验证
2. **多 Agent 协作混乱**：缺乏统一的编排机制，多个 Agent 之间无法有效通信、协同工作
3. **缺乏评测手段**：无法量化评估 AI 辅助调解的质量，无法检测模型更新后的能力回退
4. **领域知识污染**：Skill 描述被随意修改，Agent 行为逐渐偏离设计初衷
5. **上下文膨胀**：长会话导致 Token 消耗剧增，LLM 推理质量下降
6. **推理过程黑盒**：无法追溯 AI 的推理过程，出了问题难以定位根因

Mediation Harness Module 正是为解决这些问题而设计的**AI 能力评测与编排执行核心模块**。

### 核心功能

| 功能 | 说明 |
|------|------|
| **多 Agent 编排** | 6 种专业 Agent 角色（总指挥、法律顾问、情感监控、类案推荐、协议起草、调解策略），支持 Supervisor 主导的意图分类与动态路由 |
| **ReAct 推理引擎** | Think → Act → Lint → Observe 四阶段推理循环，每步输出均经过约束检查 |
| **领域约束引擎** | 5 条调解领域不变式（法条来源/人身安全/协议审核/数据隔离/禁止自由生成），违反即拒绝执行 |
| **Benchmark 评测** | AI 能力回归评测，支持 accuracy / F1 / rouge-l / bert-score 指标，对比基线版本检测回退 |
| **熵管理** | 每日定期扫描 Skill drift / Trace entropy / Fragment pattern 三类漂移，超阈值告警 |
| **上下文压缩** | 基于 Token 预算的三阶段智能压缩（截断 episodes → 生成摘要 → 截断实体描述） |
| **全链路追踪** | 分布式 Trace 记录，每步推理的 think/act/lint 结果均可追溯 |

### 使用场景

```
场景 1：调解会话 AI 辅助
  当事人来询 → Supervisor 意图分类 → 路由到对应 Agent → ReAct 推理 → Lint 检查 → 流式响应

场景 2：协议起草
  调解员发起起草请求 → 检索法律条文（来自 legal_provisions 表）→ 检索类案 → 生成草案
  → Lint 检查（必须标记 requires_review=true）→ 调解员审核 → 发送当事人

场景 3：情感风险预警
  会话中检测到情绪失控 → SENTIMENT_MONITOR 分析 → 风险评分 > 0.7 → 触发转人工工单
  → 调解员工作台收到通知 → 接管会话

场景 4：AI 能力回归检测
  模型更新后 → 触发 Benchmark 评测 → 加载评测数据集 → 执行全部样本
  → 计算指标并对比基线 → 检测回归 → 超阈值则告警

场景 5：每日系统健康检查
  凌晨 2:00 自动执行熵扫描 → 检测 Skill drift / Trace entropy / Fragment pattern
  → 计算漂移总分 → 超过阈值 10.0 → 发送告警通知
```

---

## 概念解析

### 1. Agent 角色体系

Harness 采用 **Supervisor + SubAgent** 的层级架构：

```
SUPERVISOR（调解总指挥）
    ├── LEGAL_ADVISOR（法律顾问）
    ├── SENTIMENT_MONITOR（情感监控）
    ├── SIMILAR_CASE（类案推荐）
    ├── PROTOCOL_DRAFTER（协议起草）
    └── MEDIATION_STRATEGIST（调解策略）
```

- **Supervisor**：入口 Agent，负责意图分类（`legal_consultation` / `sentiment_concern` / `case_analysis` / `protocol_draft` / `general`）并路由到对应 SubAgent
- **SubAgent**：专业 Agent，各自负责特定领域，通过 AgentMessageBus 与 Supervisor 及其他 Agent 通信

### 2. 三种执行模式

| 模式 | 本质 | 与 LLM 的关系 | 适用场景 |
|------|------|-------------|---------|
| **skill** | 确定性任务执行 | 调用 Skill instruction，不走推理循环 | 法律检索、情感监控、类案推荐 |
| **react** | 推理循环 | LLM 主导决策，每步通过 Lint 检查 | 复杂对话、多轮推理、意图分类 |
| **workflow** | 预定义流程 | 管道式执行，各阶段有序串联 | 协议起草（legal-search → similar-case → draft → review） |

三种模式的选路由 Supervisor 根据意图类型自动决定。

### 3. 领域不变式

**不变式（Invariant）** 是 Agent 行为必须始终满足的**硬约束**，违反则拒绝执行。这与 LLM 的"软提示"（soft prompting）形成对比——不变式是机械化的、不可绕过的规则。

```
不变式 1：法律条文不变式
  Agent 不得自行生成法律条文，所有引用必须来自 legal_provisions 表

不变式 2：人身安全不变式
  涉及人身伤害的建议必须转人工调解员

不变式 3：审核不变式
  协议草稿在发送前必须经过调解员审核（requires_review=true）

不变式 4：数据隔离不变式
  当事人只能看到自己的案件，不能跨当事人访问

不变式 5：禁止自由生成不变式
  禁止在回复中出现"《某某法》第N条"格式的法条引用
```

### 4. ReAct 推理循环

ReAct（Reasoning + Acting）是一种将推理与行动交替进行的范式。Harness 在标准 ReAct 基础上增加了 **Lint 阶段**，形成四阶段循环：

```
Think: LLM 分析当前状态，决定下一步行动（不执行，只推理）
   │
   ▼
Act: 执行选定的 Action（search_case / search_law / analyze_sentiment 等）
   │
   ▼
Lint: MediationLinter 检查输出是否符合 5 条不变式
   │
   ├─ 通过 → Observe 记录，进入下一轮循环
   └─ 失败 → 停止循环，返回修复指令
   │
   ▼
Observe: 记录本步结果，进入下一轮循环
```

Lint 阶段的引入是关键创新——它将约束检查嵌入推理循环内部，而不是事后检查，确保 Agent 在每一步都受到约束。

### 5. 熵管理

熵（Entropy）衡量 AI 系统的不确定性或混乱程度。熵管理是 Harness 的**垃圾回收机制**（每日凌晨执行），扫描三类漂移：

- **Skill drift**：Skill instruction 中被内嵌了具体法条内容（应只引用，不内嵌）
- **Trace entropy**：Trace 中自由生成内容过多（应从工具获取，不应自由发挥）
- **Fragment pattern**：同一 Skill 被不同 Agent 以不同方式调用（行为碎片化）

熵管理**只检测和告警，不自动修复**——修复需要人工介入，这遵循了"Human time is scarcest resource"的核心原则。

### 6. Benchmark 评测

Benchmark 是 Harness 的**质量守护者**，在模型更新、Prompt 调整、Skill 变更后自动运行，防止能力回退。评测结果包含：

- **通过率**：`passedSamples / totalSamples`，通过阈值 60%
- **回归检测**：对比基线版本的指标变化，回归阈值 5%
- **百分位统计**：mean / p50 / p95 / p99，全面反映性能分布

---

## 技术架构与设计思路

### 架构总览

Harness 采用 **Spring Boot 微服务架构**，分为 `harness-api`（接口层）和 `harness-server`（实现层）两个子模块：

```
┌─────────────────────────────────────────────────────────────┐
│                    mediation-harness-module                   │
│                                                             │
│  ┌──────────────────────┐   ┌──────────────────────────┐  │
│  │  harness-api         │   │  harness-server          │  │
│  │  (接口 + DTO)        │   │  (核心实现)              │  │
│  │                      │   │                          │  │
│  │  • HarnessApi Feign  │◄──│  • Controller           │  │
│  │  • Request/Response  │   │  • Engine               │  │
│  │  • AgentRole         │   │  • Agent                │  │
│  │  • Benchmark         │   │  • Context              │  │
│  │  • Lint              │   │  • Benchmark            │  │
│  │  • Entropy           │   │  • Entropy              │  │
│  └──────────────────────┘   │  • Messaging             │  │
│                              │  • Model                 │  │
│                              │  • Rules                 │  │
│                              │  • Observability         │  │
│                              └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 核心设计思路

#### 1. 约束优先于能力（Constraints First）

Harness 的首要设计原则不是"让 AI 能做什么"，而是"**AI 不能做什么**"。5 条不变式通过 `MediationLinter` 在推理循环的每一步强制执行。这意味着即使 LLM 模型能力很强，只要它违反不变式，输出就会被拒绝。

#### 2. Human-in-the-Loop

系统始终坚持"Human time is scarcest resource"原则，只在最高杠杆点让人类介入：

| 场景 | AI 自主决策 | 人类必须介入 |
|------|:-----------:|:-----------:|
| 争议焦点分析 | ✅ | — |
| 法律条文检索 | ✅ | — |
| 情感分析 | ✅ | — |
| 协议起草 | 起草 | ✅ 审核 |
| 通知发送 | — | ✅ 确认 |
| 转人工判断 | 建议 | ✅ 最终决定 |
| 涉及人身安全 | 识别 | ✅ 处理 |

#### 3. 可观测性内建

可观测性不是事后添加的，而是从一开始就内建于架构中：

- **Tracing**：每一步推理（Think/Act/Lint/Observe）都有独立 Trace 记录
- **Metrics**：Prometheus 格式指标（执行次数、耗时分布、Lint 失败率、转人工次数）
- **熵报告**：每日定期的系统健康扫描

#### 4. 多层抽象分离

```
┌──────────────────────────────────────────────┐
│  Controller 层（HarnessApiController）        │  ← HTTP/Feign 入口
├──────────────────────────────────────────────┤
│  Engine 层（MediationHarnessEngine）          │  ← 统一编排入口
│    ├── skill mode                            │
│    ├── react mode (ReActLoop)                │
│    └── workflow mode (WorkflowEngine)        │
├──────────────────────────────────────────────┤
│  Agent 层（Supervisor + 5× SubAgent）        │  ← 业务逻辑
├──────────────────────────────────────────────┤
│  约束层（MediationLinter）                   │  ← 领域不变式
├──────────────────────────────────────────────┤
│  工具层（mediation-ai-module 工具组件）       │  ← CaseQueryTool 等
├──────────────────────────────────────────────┤
│  LLM 层（Spring AI + DashScope）             │  ← 模型调用
└──────────────────────────────────────────────┘
```

每层只关注自己的职责，上层依赖下层，下层不感知上层。这种分层确保了系统的可测试性和可维护性。

#### 5. 离线评测与在线执行的一致性

Harness 的一个关键设计目标是在评测环境和生产环境中使用**完全相同的执行引擎**（ReActLoop、MediationLinter、Agent 等）。这确保了评测结果能真实反映生产环境的实际表现，避免"评测时正常、生产时出问题"的悖论。

#### 6. 上下文管理的 Token 感知

Context Lake 通过 `ContextBlockAssembler` 聚合多种上下文来源，在 `ContextCompressor` 中通过 Token 计数感知上下文膨胀，并按三阶段策略压缩：

```
阶段 1: Trim episodes      （保留最近 20 条消息）
         ↓ 超阈值
阶段 2: Generate summary   （LLM 生成摘要替换 episodes）
         ↓ 仍超阈值
阶段 3: Truncate entities  （截断实体描述至 200 字符）
```

这种渐进式压缩策略比直接截断更好地保留了上下文的核心信息。

#### 7. 多模型动态路由

`ModelSelector` + `LlmLoadBalancer` 实现了按场景选择最优模型的能力：

- **复杂法律推理** → qwen-max（高质量，低延迟可接受）
- **快速分类** → qwen-plus（速度快，质量足够）
- **长文本摘要** → claude-3-5-sonnet（长上下文能力强）
- **成本敏感** → deepseek-chat（成本低）
- **离线场景** → ollama/qwen2.5（无需外网）

熔断器（50% 错误率触发，60 秒恢复）确保单模型故障不会导致整个系统不可用。

---

## 部署版本选择

本项目提供 **4 种基础设施部署版本**，涵盖单机版和高可用集群:

| 版本 | 数据库 | 图数据库 | 适用场景 |
|------|--------|----------|----------|
| **mysql-neo4j** | MySQL 8.4 | Neo4j 5.22 | 传统业务，成熟稳定 |
| **mysql-nebula** | MySQL 8.4 | NebulaGraph 3.8 | 大规模图数据 |
| **pg-neo4j** | PostgreSQL 17 | Neo4j 5.22 | 需要向量检索 |
| **pg-nebula** | PostgreSQL 17 | NebulaGraph 3.8 | AI + 大规模图计算 |

## 快速开始

### 单机版 (开发/测试)

```bash
# MySQL + Neo4j
cd infra/versions/mysql-neo4j/single && ./start.sh

# MySQL + NebulaGraph
cd infra/versions/mysql-nebula/single && ./start.sh

# PostgreSQL + Neo4j
cd infra/versions/pg-neo4j/single && ./start.sh

# PostgreSQL + NebulaGraph (推荐 AI 场景)
cd infra/versions/pg-nebula/single && ./start.sh
```

### 高可用集群 (生产环境)

```bash
# MySQL + Neo4j HA
cd infra/versions/mysql-neo4j/ha && ./start.sh

# MySQL + NebulaGraph HA
cd infra/versions/mysql-nebula/ha && ./start.sh

# PostgreSQL + Neo4j HA
cd infra/versions/pg-neo4j/ha && ./start.sh

# PostgreSQL + NebulaGraph HA
cd infra/versions/pg-nebula/ha && ./start.sh
```

## 版本详情

### mysql-neo4j

- **组件**: MySQL 8.4 + Redis 7.4 + Nacos 3.2.1 + Neo4j 5.22 + MinIO
- **特点**: 成熟稳定的传统架构
- **单机版 README**: [versions/mysql-neo4j/single/README.md](infra/versions/mysql-neo4j/single/README.md)
- **高可用版 README**: [versions/mysql-neo4j/ha/README.md](infra/versions/mysql-neo4j/ha/README.md)

### mysql-nebula

- **组件**: MySQL 8.4 + Redis 7.4 + Nacos 3.2.1 + NebulaGraph 3.8 + MinIO
- **特点**: MySQL 业务数据 + NebulaGraph 大规模图分析
- **单机版 README**: [versions/mysql-nebula/single/README.md](infra/versions/mysql-nebula/single/README.md)
- **高可用版 README**: [versions/mysql-nebula/ha/README.md](infra/versions/mysql-nebula/ha/README.md)

### pg-neo4j

- **组件**: PostgreSQL 17 (pgvector) + Redis 7.4 + Nacos 3.2.1 + Neo4j 5.22 + MinIO
- **特点**: 支持向量检索 + 图关系分析
- **单机版 README**: [versions/pg-neo4j/single/README.md](infra/versions/pg-neo4j/single/README.md)
- **高可用版 README**: [versions/pg-neo4j/ha/README.md](infra/versions/pg-neo4j/ha/README.md)

### pg-nebula

- **组件**: PostgreSQL 17 (pgvector) + Redis 7.4 + Nacos 3.2.1 + NebulaGraph 3.8 + MinIO
- **特点**: 全功能 AI + 图计算平台
- **单机版 README**: [versions/pg-nebula/single/README.md](infra/versions/pg-nebula/single/README.md)
- **高可用版 README**: [versions/pg-nebula/ha/README.md](infra/versions/pg-nebula/ha/README.md)

## 基础设施组件

| 组件 | 版本 | 用途 |
|------|------|------|
| MySQL | 8.4.0 | 主关系数据库 (mysql 版本) |
| PostgreSQL | 17 + pgvector | 主数据库 + 向量存储 (pg 版本) |
| Redis | 7.4 | 缓存 / Session |
| Nacos | 3.2.1 | 配置中心 + 服务注册 |
| Neo4j | 5.22 社区版 | 图数据库 (关系图谱) |
| NebulaGraph | 3.8.0 社区版 | 图数据库 (大规模图分析) |
| MinIO | Latest | 对象存储 |

## 服务端口

### 单机版

| 服务 | MySQL 版本 | PostgreSQL 版本 | 凭证 |
|------|-----------|----------------|------|
| MySQL | 3306 | - | root / mediation123 |
| PostgreSQL | - | 5432 | mediation / mediation123 |
| Redis | 6379 | 6379 | 无 |
| Nacos | 8848 | 8848 | nacos / nacos |
| Neo4j HTTP | 7474 | 7474 | neo4j / mediation123 |
| Neo4j Bolt | 7687 | 7687 | neo4j / mediation123 |
| NebulaGraph | 9669 | 9669 | - |
| MinIO Console | 9001 | 9001 | mediation / mediation123456 |

### 高可用集群

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL HAProxy | 33060 | 多主负载均衡 |
| PostgreSQL | 5435 | 通过 PgBouncer |
| Redis | 6379 | Sentinel 自动故障转移 |
| Redis Sentinel | 26379 | - |
| Nacos | 8848/8858/8868 | 3节点集群 |
| Neo4j HAProxy | 7689/7476 | 2节点负载均衡 |
| NebulaGraph | 9669/9670 | 2 Graph 节点 |
| HAProxy Admin | 8404 | admin / admin |

## 系统要求

### 单机版

- CPU: 4 核心
- 内存: 8 GB
- 磁盘: 50 GB

### 高可用集群

- CPU: 8 核心
- 内存: 16 GB
- 磁盘: 100 GB

## 默认凭证

> **生产环境请务必修改默认密码！**

| 服务 | 用户名 | 密码 |
|------|--------|------|
| MySQL | root | mediation123 |
| PostgreSQL | mediation | mediation123 |
| Redis | - | 无密码 |
| Nacos | nacos | nacos |
| Neo4j | neo4j | mediation123 |
| MinIO | mediation | mediation123456 |

## 目录结构

```
mediation-deploy/
├── README.md                      # 本文件
├── docker-compose.dev.yml          # 开发环境配置 (旧)
│
├── infra/                         # 基础设施部署
│   ├── README.md                  # 基础设施文档
│   │
│   └── versions/                  # 版本化部署配置
│       │
│       ├── mysql-neo4j/
│       │   ├── single/            # 单机版
│       │   │   ├── docker-compose.yml
│       │   │   ├── start.sh
│       │   │   └── README.md
│       │   └── ha/               # 高可用版
│       │       ├── docker-compose.yml
│       │       ├── haproxy-*.cfg
│       │       ├── start.sh
│       │       └── README.md
│       │
│       ├── mysql-nebula/
│       │   ├── single/
│       │   └── ha/
│       │
│       ├── pg-neo4j/
│       │   ├── single/
│       │   └── ha/
│       │
│       └── pg-nebula/
│           ├── single/
│           └── ha/
│
└── app/                           # 应用部署 (微服务)
    ├── versions/                   # 应用部署版本
    │   ├── mysql-neo4j/
    │   │   ├── single/
    │   │   └── ha/
    │   ├── mysql-nebula/
    │   │   ├── single/
    │   │   └── ha/
    │   ├── pg-neo4j/
    │   │   ├── single/
    │   │   └── ha/
    │   └── pg-nebula/
    │       ├── single/
    │       └── ha/
    └── scripts/
        ├── start.sh / start.bat
        ├── stop.sh / stop.bat
        └── check-health.sh / check-health.bat
```

## 常见问题

### Q: 如何选择版本?

- 传统业务系统: **mysql-neo4j**
- 需要 AI 向量检索: **pg-neo4j** 或 **pg-nebula**
- 大规模图数据分析: **mysql-nebula** 或 **pg-nebula**
- 综合 AI + 图计算: **pg-nebula**

### Q: Neo4j 社区版如何实现高可用?

Neo4j 社区版不支持原生集群，本方案采用:
1. 部署 2 个 Neo4j 实例
2. 使用 HAProxy 负载均衡
3. 通过备份恢复实现数据冗余

### Q: 如何扩展 NebulaGraph 集群?

NebulaGraph 支持在线扩容:
```bash
docker compose scale nebula-storaged=5
docker compose scale nebula-graphd=3
```

## 相关文档

- [基础设施部署文档](infra/README.md)
- [各版本详细文档](infra/versions/)

## 应用部署 (app)

本项目还包括微服务应用的 Docker 部署脚本。

### 目录结构

```
app/
├── versions/                    # 应用部署版本
│   ├── mysql-neo4j/            # MySQL + Neo4j 版本
│   │   ├── single/            # 单机版
│   │   └── ha/                # 高可用版
│   ├── mysql-nebula/           # MySQL + NebulaGraph 版本
│   │   ├── single/
│   │   └── ha/
│   ├── pg-neo4j/              # PostgreSQL + Neo4j 版本
│   │   ├── single/
│   │   └── ha/
│   └── pg-nebula/             # PostgreSQL + NebulaGraph 版本
│       ├── single/
│       └── ha/
└── scripts/                    # 公共脚本
    ├── start.sh / start.bat
    ├── stop.sh / stop.bat
    └── check-health.sh / check-health.bat
```

### 快速启动应用服务

> **注意**: 应用服务依赖基础设施服务，请先启动 `infra` 再启动 `app`。

#### 1. 启动基础设施

```bash
# 选择版本启动基础设施 (以 mysql-neo4j 单机版为例)
cd infra/versions/mysql-neo4j/single && ./start.sh
```

#### 2. 启动应用服务

```bash
# 返回 app 目录
cd ../../app

# 启动应用 (使用相同的版本参数)
./scripts/start.sh mysql-neo4j single
```

#### 3. 验证服务

```bash
# 检查健康状态
./scripts/check-health.sh mysql-neo4j single
```

### 应用服务列表

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

### 部署版本对应关系

| 应用版本 | 基础设施版本 | 说明 |
|----------|-------------|------|
| mysql-neo4j | mysql-neo4j | MySQL + Neo4j，通用业务 |
| mysql-nebula | mysql-nebula | MySQL + NebulaGraph，大规模图 |
| pg-neo4j | pg-neo4j | PostgreSQL + Neo4j，向量检索 |
| pg-nebula | pg-nebula | PostgreSQL + NebulaGraph，完整AI栈 |

### 各版本详细文档

- [mysql-neo4j 单机版](app/versions/mysql-neo4j/single/README.md)
- [mysql-neo4j 高可用版](app/versions/mysql-neo4j/ha/README.md)
- [mysql-nebula 单机版](app/versions/mysql-nebula/single/README.md)
- [mysql-nebula 高可用版](app/versions/mysql-nebula/ha/README.md)
- [pg-neo4j 单机版](app/versions/pg-neo4j/single/README.md)
- [pg-neo4j 高可用版](app/versions/pg-neo4j/ha/README.md)
- [pg-nebula 单机版](app/versions/pg-nebula/single/README.md)
- [pg-nebula 高可用版](app/versions/pg-nebula/ha/README.md)
