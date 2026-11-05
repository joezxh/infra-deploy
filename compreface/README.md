# CompreFace 部署件（SP-3 人像到场一致性核验）

> ## 状态：**未实测 · 不接业务链路 · 不得投产**
>
> 本目录按用户 2026-11-04 裁决「insightface 无商用授权，人脸识别采用 CompreFace」产出，
> 范围仅限 **设计 + 部署件**：不写 Java 核验代码、不改 `livekit-worker` 视频轨、不部署运行、
> 不接入任何业务链路。对应设计见
> `mediation-docs/superpowers/specs/2026-11-04-face-vision-analysis-design.md` 顶部「覆盖性修订总纲」
> 与 `2026-11-04-meeting-ai-spec-review-and-revision.md` §4。
>
> **上线硬门槛**：G0–G3 四道门禁留档齐备并经人工确认前，
> `MEETING_FACE_POC_PASSED` 必须保持 `false`，平台侧 `video.available` 必须为 `false`。

---

## 1. 为什么是 CompreFace，以及为什么只用 1:1

| 项 | 结论 |
|---|---|
| 选型 | 用户裁决替换 insightface 自建容器；CompreFace 为 Exadel 开源自托管人脸识别平台，**平台代码 Apache-2.0** |
| 比对方式 | **只用 `POST /api/v1/verification/verify` 的 1:1 两图比对**（证件照 `source_image` + 会中帧 `target_image` → `similarity`） |
| 检测 | `POST /api/v1/detection/detect` → `result[].box{x_min,y_min,x_max,y_max,probability}`；多人同框由适配层按 `result.length > 1` 拒答 |
| 明确禁用 | **recognition / subjects / face collection 等 1:N 能力**。SP-3 §1.2 把「1:N 人脸检索、以脸搜人、跨会议人脸聚类」列为红线；nginx 只放行 detection 与 verification 两段路径，其余一律 404 |
| 业务侧留存 | 只存 `similarity`、结论、依据摘要、模型标识；**不存向量、不存帧、不存图像 URL 明文**；原 SP-3 的 `ai_face_gallery` 整表废弃 |

**代价**：每次核验需临时取证件照字节（SP-5 `FileApi.getFileContent` 通道），且相似度阈值必须按 CompreFace similarity 口径本地标定（G2），**不得沿用原 spec 的余弦阈值 0.45**。

---

## 2. 授权认知（G3 门禁，最容易被误判的一条）

> **换 CompreFace 不等于自动取得模型权重的商用授权。**

- CompreFace **平台代码**为 Apache-2.0，可用于商业项目；
- 但公开资料显示其内置/可选模型仍含 **FaceNet（自定义许可）、SubCenter-ArcFace / InsightFace 系模型**等，部分预训练权重可能仍限非商业研究用途；
- 因此原 SP-3 §8.1 的 G3 门禁**不删除、不改为「已通过」**，判据改写为：

| # | G3 必答项 | 交付物 |
|---|---|---|
| 1 | 列出部署实际使用的**每个模型名与版本**（含检测模型、识别模型） | 模型清单表 |
| 2 | 取得各模型**权重许可全文**，确认允许商业使用 | 许可证快照 + 出处链接 |
| 3 | 法务确认并留档；确认 CompreFace 发行包内不含其它受限组件 | 法务意见 + 组件扫描 |
| 4 | 内置 Postgres 命名卷的留存期、备份加密、撤回后的删除流程 | 运维工单号，回填 SP-3 §11 |
| 5 | 告知文案含「无活体检测 / 不保存图像 / 不改实名状态」三点 | 审定记录 |

未留档前 `MEETING_FACE_POC_PASSED=false`。若许可不满足，按 CompreFace 自定义构建路径换入自有或已商用授权的模型，再重跑 G1/G2。

---

## 3. 隐私边界（与 SP-3 原「服务侧无持久化」硬约束的差异）

原 SP-3 §3.3/§9.4 要求「服务侧 `persistence:false`、不挂任何卷、帧不落盘」。**CompreFace 自带 Postgres 命名卷，该约束在平台层无法成立**，本部署件改用「约束使用方式」收敛：

| 风险面 | 处置 |
|---|---|
| 服务侧生物特征副本 | 禁用 recognition/subject 能力 → 不因本平台产生当事人人脸底库；verification 1:1 不建 subject |
| 会中帧 / 证件照 | 仅在核验任务期经内网传输；帧不落盘、不入库、不进日志；证件照字节不新增落库（原图已在 `party_identity`） |
| 平台管理数据 | 命名卷 `compreface-postgres-data` 存管理员账号、应用与服务 key；若误启用 recognition 则还会存人脸样例 —— 由 nginx 路径白名单 + 门禁巡检共同防止 |
| 撤回与删除 | 撤回同意后：平台侧无向量可删；CompreFace 侧的删除流程（`-Volumes` 或按应用清理）须走数据删除审批并登记时间/操作人，见 `stop.ps1` |
| 日志 | 禁止出现图像 base64 长串与证件照 URL 全串；外层 nginx 不记录请求体 |

> 该差异已在评审方案 C24 登记为 P1-2 合规项，属 G3 必答内容，不得在文档中写成「无持久化」。

---

## 4. 四道门禁（任一未过，本目录只作为设计资产存在）

| 门禁 | 判据 | 现状 |
|---|---|---|
| **G0 帧可达** | 双人真机各开摄像头，`livekit-worker` 能观察到 2 个参与方的 `KIND_VIDEO` 轨 | **未证实**。`worker.py:84` 显式丢弃非音频轨，worker README 自陈「未运行联调」；本轮不触碰该行 |
| **G1 检测可用率** | 20 段真实会中帧人工标注，检测召回 ≥ 85%、误报 ≤ 5% | 未测 |
| **G2 阈值标定** | 按 CompreFace similarity 口径，用本地同人异时 / 异人样本标定 FAR/FRR 并给出阈值 | 未测；禁止用论文或余弦默认值 |
| **G3 许可与合规** | 见 §2 五项必答 + 告知文案审定 | **未通过**（权重许可待核实） |

---

## 5. 目录、端口与双层密钥

```
mediation-deploy/compreface/
├── docker-compose.yml              # 编排骨架（6 服务：postgres/core/admin/api/fe/nginx）
├── .env.example                    # 环境与门禁开关样例
├── nginx/default.conf.template     # 唯一对外入口 + X-API-Key + 路径白名单
├── scripts/deploy.ps1              # 生成 .env 与随机密钥、校验门禁、拉起、等健康
├── scripts/status.ps1              # 容器状态、探针、回环 UI、资源占用
├── scripts/verify.ps1              # 四段式验证（本目录唯一可执行证明）
├── scripts/stop.ps1                # 停止；-Volumes 才物理删卷
├── samples/                        # 运维自行放入 face.jpg / face_same_person.jpg（不入仓）
└── README.md                       # 本文件
```

| 服务 | 暴露 | 默认端口 | 说明 |
|---|---|---|---|
| `compreface-nginx` | `0.0.0.0` | **8050** | 唯一对外入口，需 `X-API-Key` |
| `compreface-fe` | `127.0.0.1` | **8051** | 仅回环，运维首次创建管理员与 Face Verification 服务 |
| 其余 4 容器 | 仅内部网络 | — | 不对外暴露 |

端口避让：OCR `8011`、SER `8020/8021`、`paddle-nginx` `8080`、以及 `80`（GPUStack 已占）。

**双层密钥**：业务调用方只持外层 `API_KEY`（`X-API-Key`）；CompreFace 自身的 `x-api-key` 由 nginx 用 `proxy_set_header` 注入，业务侧不接触，便于单独轮换与回收。运维首次需访问回环 UI 创建 **Face Verification** 类型服务并把生成的 key 回填 `.env` 的 `COMPREFACE_API_KEY`。

---

## 6. 实施前置（第一步必须做，否则不得启动）

1. **核对官方编排**：取所选 `COMPREFACE_VERSION` 的官方 `docker-compose.yml`（`.env.example` 中 `COMPREFACE_OFFICIAL_COMPOSE_URL`），逐项核对本目录 compose 的镜像 tag、`environment` 变量名、`depends_on`、`healthcheck`。**本环境的 `web_fetch` 拉取 `raw.githubusercontent.com` / GitHub 页面 / deepwiki 均超时或 429，官方 REST 文档全文未能取到**，因此本目录所有 API 路径、请求体与返回字段名都来自公开检索摘要，一律标注「待实测」。
2. 复制 `.env.example` → `.env`（或运行 `deploy.ps1` 自动生成），确认 `.env` 被 `.gitignore` 排除。
3. `.\scripts\deploy.ps1`，按提示在回环 UI 创建服务并回填 `COMPREFACE_API_KEY`。
4. 放入两张同一人的正面照到 `samples/`，运行 `.\scripts\verify.ps1`。
5. 把实测结论**回写本文件 §7 的留档表**；未回写前不得置启用开关。

---

## 7. 实测留档（未回写即视为未交付）

| # | 待实测项 | 为何不能先猜 | 实测结论（运维回填） |
|---|---|---|---|
| V1 | 官方 compose 的镜像 tag 与环境变量名是否与本骨架一致 | 版本差异会直接导致容器起不来或 API 不可达 | 待回写 |
| V2 | `GET/POST` 路径是否确为 `/api/v1/detection/detect`、`/api/v1/verification/verify`；nginx 剥 `/face` 前缀后是否正确 | 官方 REST 文档未取到，路径是公开检索摘要 | 待回写 |
| V3 | detection 返回体是否含 `result[].box.probability`；verification 返回 `similarity` 的**确切字段路径**（`result.similarity` 还是顶层） | `verify.ps1` 已兼容两种，但判定表与日志口径依赖确切形态 | 待回写 |
| V4 | verification 是否需要先创建 Application/Service；`x-api-key` 头名大小写与注入是否生效 | 双层 key 设计的有效性取决于此 | 待回写 |
| V5 | CPU 分支下一帧 640px 检测 + 1:1 比对的 P50/P95；多人同框返回结构 | 决定采样间隔、并发门与降级阈值 | 待回写 |
| V6 | 中文东亚面孔的本地 FAR/FRR 与选定 `similarity-threshold` | 公开分族准确率提示这里会明显低于通用基准，阈值不得取默认值 | 待回写 |
| V7 | 所选模型权重的商用许可核实结论（§2） | G3 通过与否 | 待回写 |
| V8 | 禁用 recognition 后，CompreFace 侧是否仍残留任何当事人图像/特征（卷内巡检） | 撤回后「无副本」的可执行证明 | 待回写 |

---

## 8. 与 SP-3 spec 的对应关系

| SP-3 原章节 | 本目录对应 |
|---|---|
| §8.4 部署形态（`mediation-deploy/face/` + insightface-svc） | **整体替换为本目录**；原 `app.py`/`Dockerfile`/`requirements.txt`/`models/buffalo_l` 全部作废 |
| §3.3 服务契约（自建 detect/embed + HMAC 任务凭据） | 改为 CompreFace 原生 API + 外层 nginx 双层 key；任务窗口守卫上移 Java |
| §5 底库（`ai_face_gallery.embedding REAL[]` + Java 余弦） | 整表废弃；平台只存 similarity 与结论 |
| §4.3 判定表 / §6 端点 / §7 DDL / §10 用例 | 见 SP-3 顶部「覆盖性修订总纲」B 段与评审方案 §4.3 对照表 |
| §8.1 G3 门禁 | 见本文件 §2（保留且仍为未通过） |
| §9.3 / §9.4 隐私 | 见本文件 §3（原「服务侧无持久化」结论改写） |

**实施顺序不可颠倒**：SP-1/2 → SP-5 → SP-4 → SP-3。本目录可并行准备，但 G0 未证实、四份上游 spec 未落地前，不得接入业务链路。

## 9. 门禁取证状态登记（2026-11-05 执行结果）

| 门禁 | 本轮交付 | 结论 |
|---|---|---|
| G0 帧可达 | `worker.py` 的 `_handle_track` 已加 `[track-observe]` 结构化观测日志（只打印轨元信息，**不改判断分支**，仍只处理 `KIND_AUDIO`） | **未证实**：需双人真机各开摄像头跑一次，判据为日志出现 2 个参与方各一条 `KIND_VIDEO`；本会话无真实房间，不得据此置位 |
| G1 召回/误报 | `scripts/verify.ps1` 第三/四段（detection `box.probability`、verification `similarity`）+ 第五段 1:N 红线 | **未实测**：无样本 JPEG、未运行容器；§7 V1–V8 全部仍为「待回写」 |
| G2 阈值标定 | 未开工 | **未通过**：禁止沿用余弦 0.45，须按 CompreFace similarity 本地标定 FAR/FRR |
| G3 许可与合规 | §2 五项必答清单 + §3 命名卷留存/删除边界 | **未通过**：平台 Apache-2.0 ≠ 内置模型权重可商用，需逐模型核实 + 法务留档 |

按 D4/D5 保留的号段（V3.56/V3.57、菜单 9506、错误码 `1_040_065_*`）**本轮不落任何代码或 SQL**：计划 Task 11 明确「仅当 Task 10 全部通过」方可开工。`MEETING_FACE_POC_PASSED` 保持 `false`。

> 官方 REST 文档在本环境未能取到（raw.githubusercontent / GitHub / deepwiki 均超时或 429），
> `verify.ps1` 是 API 契约的唯一可执行证明；实测后须按返回体真实形态修正脚本与 README，
> 不得把检索摘要写成已验证事实。
