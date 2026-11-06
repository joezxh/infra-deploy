# CompreFace 部署件（SP-3 人像到场一致性核验）

> ## 状态：**已人工放行并置位（2026-11-07）· 收敛版业务链路已落地 · 真人/法务留档未齐备**
>
> 本目录按用户 2026-11-04 裁决「insightface 无商用授权，人脸识别采用 CompreFace」产出。
> **2026-11-05 已完成**：自定义 `compreface-core` 镜像（YuNet 检测 + SFace 识别插件）、
> 权重下载与 SHA256 留档、宿主 PostgreSQL 复用、`docker compose up` 实际部署、
> 经 nginx `:8050` 的 detect/verify/1:N 红线契约实测（`verify.ps1` 9/9 通过，见 §7）。
> 仍**不写 Java 核验代码、不改 `livekit-worker` 视频轨、不接入任何业务链路**。
> 对应设计见
> `mediation-docs/superpowers/specs/2026-11-04-face-vision-analysis-design.md` 顶部「覆盖性修订总纲」
> 与 `2026-11-04-meeting-ai-spec-review-and-revision.md` §4。
>
> **2026-11-05 权重裁决**：部署权重采用**可商用开源组合 YuNet（检测）+ SFace（识别）**（OpenCV Zoo / ONNX），
> 选型与三层许可核实见 SP-3 总纲 **D-2 段**；落地方式为**自定义 core 镜像 + Python 插件适配层**
> （`build/core-build/`，非官方内置模型，无需改 Java/yml）。
>
> **上线硬门槛**：G0–G3 四道门禁留档齐备并经人工确认前，
> `MEETING_FACE_POC_PASSED` 必须保持 `false`，平台侧 `video.available` 必须为 `false`。
> 部署成功 ≠ 门禁通过：G0（worker 视频轨）、G1（真实帧召回率）、G2（阈值标定）、
> G3 其余四项（许可快照/法务/卷留存/告知文案）仍为未完成，Task 11 前置不变。
>
> **2026-11-05 用户人工确认放行（决策留档）**：用户指令「通过并人工确认，继续」已启动 Task 11
> 的 CompreFace 1:1 业务链路（见 `mediation-docs/superpowers/specs/2026-11-05-ai-meeting-consolidated-revision.md` §7）。
> 但上述 G0/G1/G2/G3 **实证材料在本工作区仍不存在**，人工确认是风险接受与放行决策，不等于留档齐备；
> 因此本部署件 `.env` 的 `MEETING_FACE_POC_PASSED` **保持 `false`**（部署件门禁，改 true 会使 `deploy.ps1` 拒绝启动），
> 后端业务门禁改由 `MEETING_G3_VIDEO` + `MEETING_FACE_ENABLED` 双开关在部署环境显式置位，且
> `MEETING_FACE_SIMILARITY_THRESHOLD` 留空时**只回传相似度、不产任何身份结论**。
> 正式投产前仍须补齐四项留档与 G2 本地阈值标定。
>
> **2026-11-07 置位登记（用户「继续」指令）**：用户声明真人测试门禁已通过，已执行
> `.\scripts\enable-face-poc.ps1 -Action enable`：`MEETING_FACE_POC_PASSED=true`、
> `MEETING_G3_VIDEO=true`、`MEETING_FACE_ENABLED=true`，阈值取现有标定报告帧域值 `0.55`
> （**样本量不足，仅供联调**；真人 G2 报告到手后用 `-Action rollback` → `-Action enable -Threshold <真人值>` 替换）。
> 置位留档 `evidence/poc-enablement-record.md`；`deploy.ps1` 已改为「true 时校验置位留档存在」，不再一律拒绝启动。
> 一键回滚：`.\scripts\enable-face-poc.ps1 -Action rollback`。
> 新增交付：`evidence/g3/`（G3 四项，模型清单已坐实、其余待签字）、`verify.ps1 -CheckLatency/-CheckResidual`
> （V5 延迟 / V8 残留巡检，默认关闭不影响 9/9）、当事人下拉与「无活体检测」告知文案。
> **本工作区仍无真人 G0/G1/G2 报告与 G3 法务/运维签字，投产前须补齐。**

---

## 1. 为什么是 CompreFace，以及为什么只用 1:1

| 项 | 结论 |
|---|---|
| 选型 | 用户裁决替换 insightface 自建容器；CompreFace 为 Exadel 开源自托管人脸识别平台，**平台代码 Apache-2.0** |
| 比对方式 | **只用 `POST /api/v1/verification/verify` 的 1:1 两图比对**（证件照 `source_image` + 会中帧 `target_image` → `similarity`） |
| 检测 | `POST /api/v1/detection/detect` → `result[].box{x_min,y_min,x_max,y_max,probability}`；多人同框由适配层按 `result.length > 1` 拒答 |
| 明确禁用 | **recognition / subjects / face collection 等 1:N 能力**。SP-3 §1.2 把「1:N 人脸检索、以脸搜人、跨会议人脸聚类」列为红线；nginx 只放行 detection 与 verification 两段路径，其余一律 404 |
| 业务侧留存 | 只存 `similarity`、结论、依据摘要、模型标识；**不存向量、不存帧、不存图像 URL 明文**；原 SP-3 的 `ai_face_gallery` 整表废弃 |

**代价**：每次核验需临时取证件照字节（SP-5 `FileApi.getFileContent` 通道），且相似度阈值必须按 **YuNet + SFace 的 similarity 口径**本地标定（G2），**不得沿用原 spec 的余弦阈值 0.45**。识别维度由 `512` 变为 `128`，SFace 特征只在服务侧内存计算，不落库、不进日志。

---

## 2. 授权认知（G3 门禁：权重授权子项已解决，G3 整体未通过）

> **换 CompreFace 不等于自动取得模型权重的商用授权；2026-11-05 改用可商用开源权重后，只解决「模型权重授权」这一子项。**

- CompreFace **平台代码**为 Apache-2.0，可用于商业项目；
- 其内置/可选模型仍含 **FaceNet（自定义许可）、SubCenter-ArcFace / InsightFace 系模型**等，部分预训练权重可能限非商业研究用途，故本部署**不再沿用平台内置权重**；
- 按用户裁决改用 **YuNet（检测）+ SFace（识别）** 可商用开源 ONNX 权重（选型、备选比较与**代码许可 / 权重许可 / 训练数据集许可**三层核实清单见 SP-3 总纲 **D-2 段**）；
- 原 SP-3 §8.1 的 G3 门禁**不删除、不改为「已通过」**；**「模型权重授权」子项判为已解决**，其余四项待办逐条保留：

| # | G3 必答项 | 交付物 |
|---|---|---|
| 1 | 列出部署实际使用的**每个模型名与版本**（含检测模型、识别模型） | 模型清单表 |
| 2 | ~~取得各模型权重许可全文~~ → **已选定可商用开源权重（YuNet + SFace），「权重授权」子项已解决**；仍须补齐许可快照、出处链接与三层核实（代码 / 权重 / 训练数据集） | 许可证快照 + 出处链接（**待留档**） |
| 3 | 法务确认并留档；确认 CompreFace 发行包内不含其它受限组件 | 法务意见 + 组件扫描 |
| 4 | 内置 Postgres 命名卷的留存期、备份加密、撤回后的删除流程 | 运维工单号，回填 SP-3 §11 |
| 5 | 告知文案含「无活体检测 / 不保存图像 / 不改实名状态」三点 | 审定记录 |

**2026-11-07 状态**：用户已声明真人门禁通过并完成置位（见顶部置位登记），
`MEETING_FACE_POC_PASSED=true`、阈值 `0.55`（**联调值，来源样例报告，样本量不足**）。
但「权重授权」子项已解决**不等于 G3 整体通过**：真人 G0/G1/G2 报告与 G3 四项签字仍不在工作区，
投产前须补齐，并复核阈值来源；一键回滚见 `enable-face-poc.ps1 -Action rollback`。
若三层核实发现训练数据集存在研究用途限制，须按自定义构建路径换入其它已授权权重并**重跑 G1/G2**（SFace 为 128 维，阈值须重新标定）。
G3 留档包见 `evidence/g3/`：第 1 项模型清单已坐实，第 2–4 项为待签字模板。

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
| **G3 许可与合规** | 见 §2 五项必答 + 告知文案审定 | **未通过**：2026-11-05 选定可商用开源权重（YuNet + SFace），**仅「模型权重授权」子项已解决**；模型清单、许可快照与法务意见、卷留存/删除、告知文案审定四项仍待办。`MEETING_FACE_POC_PASSED=false` 不变 |

---

## 5. 目录、端口与双层密钥

```
mediation-deploy/compreface/
├── docker-compose.yml              # 编排（core/admin/api/fe/nginx，5 服务；PG 复用宿主，无内置 postgres）
├── .env.example                    # 环境与门禁开关样例（首次部署复制为 .env）
├── .gitignore                      # 排除 .env / models/*.onnx / build/ / samples/
├── nginx/default.conf.template     # 唯一对外入口 + X-API-Key + 路径白名单 + 服务 key 注入
├── scripts/deploy.ps1              # 生成 .env 与随机密钥、校验门禁、拉起、等健康
├── scripts/build-core.ps1          # 构建自定义 compreface-core 镜像（YuNet + SFace 插件）
├── scripts/status.ps1              # 容器状态、探针、回环 UI、资源占用
├── scripts/verify.ps1              # 全套契约验证（本目录唯一可执行证明）
├── scripts/stop.ps1                # 停止（PG 为外部宿主库，无命名卷可删）
├── build/core-build/               # 自定义 core 镜像构建上下文：yunet/sface 插件 + Dockerfile
├── models/                         # 只读权重挂载位：YuNet / SFace ONNX（已下载，不入仓）
├── samples/                        # 验证样例图（不入仓）：face / face_same_person / face_other_person
└── README.md                       # 本文件
```

| 服务 | 暴露 | 默认端口 | 说明 |
|---|---|---|---|
| `compreface-nginx` | `0.0.0.0` | **8050** | 唯一对外入口，需 `X-API-Key` |
| `compreface-fe` | `127.0.0.1` | **8051** | 仅回环，运维首次创建管理员与服务、取服务 key |
| 其余 3 容器 | 仅内部网络 | — | 不对外暴露 |

端口避让：OCR `8011`、SER `8020/8021`、`paddle-nginx` `8080`、以及 `80`（GPUStack 已占）。

**双层密钥（注意 key 与服务类型绑定）**：业务调用方只持外层 `API_KEY`（`X-API-Key`）；
CompreFace 自身的 `x-api-key` 由 nginx 按路径注入——`detection/*` 注入 **DETECTION 服务 key**
（`.env` 的 `COMPREFACE_DET_KEY`），`verification/*` 注入 **VERIFY 服务 key**（`COMPREFACE_API_KEY`）。
CompreFace 的 key 不能跨服务类型混用（实测：VERIFY key 调 detect 返回 code 10 "service not found"）。

**数据库**：复用宿主 PostgreSQL（`postgres/postgres`，库 `compreface`，经 `host.docker.internal:5432`）。
compose 用 `POSTGRES_URL` 注入 JDBC 串——**Spring 只认 `POSTGRES_URL`，配 `POSTGRES_HOST` 无效**
（实测 `UnknownHostException: compreface-postgres-db`）。表结构由 liquibase 自动建；
**数据库本身须预先存在**（PG 不会自建库），见 §6 步骤 2。

**模型声明（2026-11-05，已落地）**：权重文件已下载至 `models/` 并与 `.env` 中的 SHA256 实测一致；
compose 把 `./models` 以只读挂到 `/opt/face-weights`。自定义镜像 `compreface-core-yunet-sface:1.2.0`
（基于 `exadel/compreface-core:1.2.0`，注入 yunet/sface 插件并打补丁禁用属性类默认插件，见 `build/core-build/`）。

---

## 6. 部署手册（2026-11-05 实测通过；换机重放按此步骤）

### 6.0 墙内准备

- Docker daemon 出网：`docker info` 确认代理项；若继承系统死代理（`http.docker.internal:3128`），先按
  `HKCU\...\Internet Settings` 置 `ProxyEnable=0` 并重启 Docker Desktop（会中断现有容器，择机执行），
  或配置 `registry-mirrors`。**TLS 握手成功但下载失败 = 代理已死，不是镜像不存在**。
- 宿主 PostgreSQL：监听 `0.0.0.0:5432`（或已映射），账号 `postgres/postgres`。
- 权重（一次性）：`face_detection_yunet_2023mar.onnx`（227 KB）与
  `face_recognition_sface_2021dec.onnx`（37 MB）来自 OpenCV Zoo（Apache-2.0）。
  GitHub LFS 的 raw/media 直链只会拿到指针文件；**可用带 git-lfs 的本地 clone + sparse-checkout
  经 VPN 代理拉取**（历史命令见 `download-weights.ps1` 注释）。放入 `models/`，
  SHA256 实测值已回填 `.env.example`（`verify.ps1` 第 0 段做离线比对）。

### 6.1 构建自定义 core 镜像（一次性）

```powershell
.\scripts\build-core.ps1
# 等价：docker build -f build/core-build/Dockerfile -t compreface-core-yunet-sface:1.2.0 build/core-build/
```

镜像内容：官方 `exadel/compreface-core:1.2.0` + `opencv-contrib-python-headless==4.9.0.80`（清华 PyPI 源，
提供 `cv2.FaceDetectorYN/FaceRecognizerSF`）+ `yunet`/`sface` 插件包 + 一行 sed 补丁
（把 `EXTRA_PLUGINS` 进程内默认值置空——core 的 `get_env` 对空串会回退官方默认插件
landmarks/agegender/mask/pose，SP-3 只允许检测+1:1，不产出任何属性类插件）。

### 6.2 首次启动

```powershell
Copy-Item .env.example .env      # 或运行 .\scripts\deploy.ps1 自动生成并注入随机 API_KEY
.\scripts\deploy.ps1             # compose up -d + 等待 compreface-core / compreface-nginx healthy
```

前置检查：宿主库中 `compreface` 数据库必须已存在（不存在则
`docker run --rm -e PGPASSWORD=postgres postgres:15-alpine createdb -h host.docker.internal -U postgres compreface`）。

### 6.3 创建服务 key（REST 引导，也可走回环 UI `http://127.0.0.1:8051`）

CompreFace 的注册/登录走 admin 的 OAuth2 端点（FE 容器 nginx 代理 `/admin/`）：

```
POST /admin/user/register     {"email","firstName","lastName","password"}          # 免鉴权
POST /admin/oauth/token       表单 username/password/grant_type=password，
                              Authorization: Basic Q29tbW9uQ2xpZW50SWQ6cGFzc3dvcmQ=（CommonClientId:password）
POST /admin/app               {"name":"..."}            # 需 Cookie: CFSESSION=<access_token>，且全局角色须为 OWNER
POST /admin/app/{guid}/model  {"name":"...","type":"VERIFY"}    → 返回 apiKey = COMPREFACE_API_KEY
POST /admin/app/{guid}/model  {"name":"...","type":"DETECTION"} → 返回 apiKey = COMPREFACE_DET_KEY
```

三个实测坑：
1. **token 放 Cookie 不放 Authorization 头**（admin 的 `CookieTokenExtractor` 只读 `CFSESSION` Cookie，
   Bearer 头无效，实测 `invalid_token`）。
2. **全局只允许一个 OWNER 用户**（`findByGlobalRole(OWNER)` 单结果查询，两个 OWNER 会导致建应用 500
   `NonUniqueResultException`）；新注册用户是 USER，无权建应用——须在库中改
   `UPDATE "user" SET global_role='O' WHERE email='...'`（保证唯一 OWNER）。
3. 重建 admin/api 容器后 **必须 `docker restart compreface-fe`**：FE 内置 nginx 在启动时解析上游 IP，
   容器重建换 IP 后旧 IP 会被其它容器续用，请求会打到错误服务（实测表现为 `/admin/*` 返回
   api 的 `Missing header: x-api-key`）。

把两个服务 key 回填 `.env` 的 `COMPREFACE_API_KEY` / `COMPREFACE_DET_KEY`，
然后 `docker compose up -d --force-recreate compreface-nginx`。

### 6.4 验证

```powershell
# 放三张样例图到 samples/（可从 CompreFace 源码 embedding-calculator/sample_images/ 取：
# 001_A.jpg→face.jpg、004_A.jpg→face_same_person.jpg（同人）、007_B.jpg→face_other_person.jpg）
.\scripts\verify.ps1     # 9 项断言：权重 SHA256 / 镜像 / nginx / 401 / detect / 同人高分 / 异人低分 / 1:N 404
```

业务调用方实际用到的接口（经 `:8050`，带外层 `X-API-Key`）：

```powershell
curl.exe -X POST "http://127.0.0.1:8050/face/api/v1/detection/detect?limit=1" -H "X-API-Key: <外层key>" -F "file=@会中帧.jpg"
curl.exe -X POST "http://127.0.0.1:8050/face/api/v1/verification/verify" -H "X-API-Key: <外层key>" -F "source_image=@证件照.jpg" -F "target_image=@会中帧.jpg"
```

### 6.5 故障排查速查

| 症状 | 根因与处置 |
|---|---|
| core 起不来，`ModuleNotFoundError: ...plugins.""` | compose 的 `${EXTRA_PLUGINS:-""}` 把引号当字面字符传进容器；默认值必须写 `${EXTRA_PLUGINS:-}`（已修） |
| api/admin 反复重启，`UnknownHostException: compreface-postgres-db` | 只配了 `POSTGRES_HOST`；必须配 `POSTGRES_URL`（compose 已改为拼接注入） |
| fe 反复重启，`"client_max_body_size" directive invalid value` | FE 内置 nginx 模板缺 `CLIENT_MAX_BODY_SIZE` 等变量；compose 已补齐 |
| verify 返回 `Maximum upload size exceeded ... (10)` | `MAX_FILE_SIZE` 必须带单位（`10MB`），裸数字按字节解析 |
| `/admin/*` 返回 `Missing header: x-api-key`（code 20） | FE nginx 上游 IP 过期（admin/api 容器重建过）；`docker restart compreface-fe` |
| detect 返回 code 10 service not found | 用了 VERIFY key 调 detection；nginx 按 location 注入对应类型 key（已修） |
| verify 返回 code 31 / 28 | 源图含多张人脸 / 未检出人脸：1:1 接口要求两图各恰好一张脸 |

---

## 7. 实测留档（2026-11-05 回填；`verify.ps1` 9/9 通过，fail=0 skip=0）

| # | 待实测项 | 实测结论（2026-11-05，Docker Desktop / WSL2 / 无 GPU） |
|---|---|---|
| V1 | compose 镜像 tag 与环境变量名 | **已核对并实测**：api/admin/fe 用官方 `exadel/compreface-*:1.2.0`，core 用自定义 `compreface-core-yunet-sface:1.2.0`。官方骨架的三处坑已实测修正：`POSTGRES_URL`（非 `POSTGRES_HOST`）、`MAX_FILE_SIZE` 须带 `MB` 单位、FE 需 `CLIENT_MAX_BODY_SIZE` 等三变量 |
| V2 | API 路径与 `/face` 前缀剥离 | **实测正确**：`/face/api/v1/detection/detect` 与 `/face/api/v1/verification/verify` 经外层 nginx 剥前缀后直达 CompreFace 原生路径 |
| V3 | 返回体确切字段路径 | **实测**：detection → `result[].box{x_min,y_min,x_max,y_max,probability}`；verification → `result[0].face_matches[0].similarity`（另含 `source_image_face.box`）。`verify.ps1` 已按此形态断言 |
| V4 | 服务创建与 key 注入 | **实测**：key 与服务类型绑定（VERIFY/DETECTION 各一个，不可混用）；`x-api-key` 头由外层 nginx `proxy_set_header` 注入，业务侧不接触服务 key，设计成立；admin token 走 `CFSESSION` Cookie（Bearer 无效） |
| V5 | 延迟（CPU） | **实测（热态）**：verify ≈ 2.5–2.9s、detect ≈ 2.8–2.9s——但样例为 400 万像素 JPEG（300 KB+），全图解码 + 640 检测开销大；会中 640 长边帧预计显著更快，**真实帧的 P50/P95 仍待 G1 用真实样本实测**。多人同框返回多元素 `result[]`，1:1 verify 对多脸源图直接 400（code 31） |
| V6 | **按 YuNet + SFace 重标定**的中文东亚面孔本地 FAR/FRR 与 `similarity-threshold` | **未测（G2）**：本轮仅得参考点——同图对（官方样例 001_A vs 004_A，同人）similarity=0.919，异人（001_A vs 007_B）similarity=0.078，区分度充足；正式标定须用本地真实样本 |
| V7 | YuNet / SFace 三层许可核实 | **「权重授权」子项已解决**（Apache-2.0）；许可证快照、出处链接与法务意见**待留档**（G3 其余项不变） |
| V8 | recognition 禁用后的残留巡检 | **未巡检**：本轮未启用 recognition、未入库任何 subject（1:N 路径 404 拦截实测有效）；卷内巡检流程仍待补 |
| V9 | 权重 SHA256 实测比对 | **通过**：`8F2383E4…52FA4`（YuNet）/ `0BA9FBFA…34E79`（SFace），与 `.env` 期望值一致 |

---

## 8. 与 SP-3 spec 的对应关系

| SP-3 原章节 | 本目录对应 |
|---|---|
| §8.4 部署形态（`mediation-deploy/face/` + insightface-svc） | **整体替换为本目录**；原 `app.py`/`Dockerfile`/`requirements.txt`/`models/buffalo_l` 全部作废 |
| §3.3 服务契约（自建 detect/embed + HMAC 任务凭据） | 改为 CompreFace 原生 API + 外层 nginx 双层 key；任务窗口守卫上移 Java |
| §5 底库（`ai_face_gallery.embedding REAL[]` + Java 余弦） | 整表废弃；平台只存 similarity 与结论 |
| §4.3 判定表 / §6 端点 / §7 DDL / §10 用例 | 见 SP-3 顶部「覆盖性修订总纲」B 段与评审方案 §4.3 对照表 |
| §8.1 G3 门禁 | 见本文件 §2/§4/§9（**仅「模型权重授权」子项已解决，G3 整体仍未通过**） |
| 总纲 D-2 可商用开源权重选型 | 见本文件 §1/§5/§7 与 `docker-compose.yml`、`.env.example`、`scripts/verify.ps1` 第 0 段的模型来源与 SHA256 声明 |
| §9.3 / §9.4 隐私 | 见本文件 §3（原「服务侧无持久化」结论改写） |

**实施顺序不可颠倒**：SP-1/2 → SP-5 → SP-4 → SP-3。本目录可并行准备，但 G0 未证实、四份上游 spec 未落地前，不得接入业务链路。

## 9. 门禁取证状态登记（2026-11-05 更新：部署 PoC 已完成）

| 门禁 | 本轮交付 | 结论 |
|---|---|---|
| G0 帧可达 | `worker.py` 的 `_handle_track` 已加 `[track-observe]` 结构化观测日志（只打印轨元信息，**不改判断分支**，仍只处理 `KIND_AUDIO`） | **未证实**：需双人真机各开摄像头跑一次，判据为日志出现 2 个参与方各一条 `KIND_VIDEO`；本会话无真实房间，不得据此置位 |
| G1 召回/误报 | **部署 PoC 已完成**：自定义 core 镜像 + YuNet/SFace 插件落地，`verify.ps1` 9/9 通过（detect 返回 box+probability、verify 同人 0.919 / 异人 0.078、1:N 红线 404、权重 SHA256 一致）。**判据（20 段真实会中帧、召回 ≥85%、误报 ≤5%）仍未测** | **契约层已验证；召回率口径未通过** |
| G2 阈值标定 | 参考点：同人 0.919 / 异人 0.078（官方样例图，非本地真实样本） | **未通过**：禁止沿用余弦 0.45，须按本地真实同人异时/异人样本标定 FAR/FRR |
| G3 许可与合规 | §2 五项必答清单 + §3 留存/删除边界 + 2026-11-05 选定 YuNet + SFace 可商用开源权重（总纲 D-2）并**已实际部署** | **未通过**：**「模型权重授权」子项已解决**；模型清单、许可快照与法务意见、卷留存/删除、告知文案审定四项仍待办。`MEETING_FACE_POC_PASSED=false` 不变，Task 11 前置不变 |

> 上表与 §4 记录的是**工作区留档材料状态**（2026-11-05/06 口径），不是对用户 2026-11-06
> 「真人测试门禁都通过」与 2026-11-07 置位决策的否定：当前本地 `.env` 已置位，见顶部置位登记与
> `evidence/poc-enablement-record.md`。投产前仍须把真人报告、G3 四项签字与真人 G2 阈值补齐并回写本表。
> 核验历史落库（V3.56/V3.57、菜单 9506、065 号段）已由 2026-11-07 另一轮交付，迁移须在共享库执行。

> 官方 REST 文档在本环境未能取到（raw.githubusercontent / GitHub / deepwiki 均超时或 429），
> `verify.ps1` 是 API 契约的唯一可执行证明；**2026-11-05 已按返回体真实形态修正脚本与 README（§7）**。
>
> **2026-11-05 部署 PoC 结论**：自定义镜像已构建（含 `EXTRA_PLUGINS` 置空补丁，属性类插件全部禁用）、
> 权重已下载并校验、宿主 PG 复用已实测（`POSTGRES_URL` 坑已修）、detect/verify/1:N 红线契约全部实测通过。
> **本部署件当前仅限内网取证用途，不接业务链路**；G0/G1/G2/G3 其余项未过前，
> `MEETING_FACE_POC_PASSED` 恒为 `false`，平台侧 `video.available` 恒为 `false`。

## 10. G2 相似度阈值标定（2026-11-05 交付工具，尚未产出生产阈值）

工具：`scripts/calibrate-threshold.ps1`（只出报告，**不自动改** ai-server 配置）。

```powershell
# 样本目录：samples/calibration/{positive,negative}/<person_id>/*.jpg
.\scripts\calibrate-threshold.ps1                       # 默认样本目录 + 本地 8050
.\scripts\calibrate-threshold.ps1 -CalibDir D:/data/face-calib `
    -ApiBase 'http://192.168.110.169:8050/face/api/v1/verification/verify'
```

**双域口径（关键）**：生产链路的相似度来自「浏览器抓帧 → 上传」，因此阈值必须按**帧域**
（长边 640 + JPEG q0.72，与前端 `useFaceVerification.grabFrame` 一致）标定；原图域会系统性高估。
工具同时输出两域分布：

| 域 | 同人（正样本） | 异人（负样本） | 建议阈值 |
|---|---|---|---|
| 原图域 | 0.884-0.985（mean 0.928） | 0.030-0.093（mean 0.059） | 0.60 |
| **帧域** | 0.748-0.969（mean 0.847） | 0.020-0.241（mean 0.125） | **0.55**（Youden 0.45） |

> 上表仅基于官方样例 8 张（正 6 对 / 负 6 对），**样本量远低于门槛（各 20 组）**，
> 属工具自检，**不构成 G2 通过依据**，因此 `MEETING_FACE_SIMILARITY_THRESHOLD` 保持未设置，
> 系统恒返回 `FACE_INSUFFICIENT`（只回传相似度、不产身份结论）。

**采集规范（补齐真实样本后重跑）**：至少 2 名参与者、每人 10 张以上，覆盖不同日期/时段/光照/朝向/表情/距离；
证件照式正面照与「会中帧」式随意照混合；全部单人脸；**分组必须人工确认**——文件名后缀不代表同一人
（实测官方样例 `005_A` 与 `001_A` 仅 0.21、`007_B` 与 `008_B` 仅 0.083，均为不同人）。