# CompreFace 自托管人脸比对系统 —— 组件说明与完整使用/部署手册

> 适用范围：`mediation-deploy/compreface/` 部署件，SP-3「人像到场一致性核验」G1/G2 门禁取证的
> 内网部署 PoC（2026-11-05 实测通过，`verify.ps1` 9/9）。
>
> **红线与门禁纪律**：本系统只提供 **1:1 verification** 与 **detection** 能力，1:N（recognition /
> subjects / face collection）在 nginx 层一律 404 拒绝；平台不建当事人人脸底库、不持久化向量。
> G0–G3 门禁未全部通过前 `MEETING_FACE_POC_PASSED` 恒为 `false`，本部署件**不接业务链路、不得投产**。

---

## 第一部分：系统组件构成

### 1.1 组件总览

```
业务调用方 ──X-API-Key──▶ compreface-nginx(:8050)
                              │ 路径白名单 + 剥 /face 前缀 + 注入 CompreFace 服务 key
                              ▼
                         compreface-fe(:80, 仅宿主回环 8051)
                              │  FE 内置 nginx 静态托管 + 反向代理
              ┌───────────────┼────────────────┐
              │ /admin/       │ /api/v1/       │ /core/
              ▼               ▼                ▼
        compreface-admin  compreface-api   compreface-core(:3000)
         (Spring :8080)    (Spring :8080)   (自定义镜像, uwsgi Python ML)
              │               │                │
              └───────┬───────┘                │ 加载 /opt/face-weights 权重
                      ▼                        │ (YuNet + SFace ONNX)
              宿主 PostgreSQL                   ▼
        host.docker.internal:5432          内存中计算 embedding
          库: compreface                   (1:1 比对在 api 侧用两图向量完成)
```

### 1.2 服务模块职责

| 服务 | 镜像 | 端口（容器内） | 暴露方式 | 职责 |
|---|---|---|---|---|
| **compreface-nginx** | `docker.m.daocloud.io/library/nginx:1.27-alpine` | 80 | **`0.0.0.0:8050`（唯一对外入口）** | ① 校验外层 `X-API-Key`（业务调用方唯一持有的密钥）；② 路径白名单：仅放行 `/face/api/v1/detection/*` 与 `/face/api/v1/verification/*`，其余一律 404（1:N 红线的部署层实现）；③ 剥掉 `/face` 前缀转发到 FE；④ 按路径注入 CompreFace 自身服务 key（detection 注 DET key、verification 注 VERIFY key），业务侧不接触服务 key；⑤ `/face-nginx-health` 免鉴权存活探针 |
| **compreface-fe** | `exadel/compreface-fe:1.2.0`（或改造版 `compreface-fe-cn:1.2.0`，见 `.env` 的 `COMPREFACE_FE_IMAGE`） | 80 | `8051`，绑定地址由 `COMPREFACE_UI_BIND` 控制：默认 `127.0.0.1`（仅回环）；设 `0.0.0.0` 则内网可达（远端 192.168.110.169 已按此配置） | Web 管理控制台（Angular 静态资源）+ 内置 nginx 反代：`/admin/` → admin、`/api/v1/` → api、`/core/` → core。运维通过它注册管理员、建应用与服务、查看调用统计。**管理端无外层 X-API-Key 保护，放开绑定前须确认内网边界/ufw 白名单**。改造版含「UI 美化 + 中英双语」，构建方式见 `build/fe-image/Dockerfile` 注释 |
| **compreface-admin** | `exadel/compreface-admin:1.2.0` | 8080 | 仅内部网络 | 管理面：用户注册/登录（OAuth2，token 走 `CFSESSION` Cookie）、应用（App）与服务（Model，类型 DETECTION/RECOGNITION/VERIFY）的增删、服务 key 生成与轮换、调用统计。REST 基路径 `/admin/*`，liquibase 自动建表 |
| **compreface-api** | `exadel/compreface-api:1.2.0` | 8080 | 仅内部网络 | 数据面：对外 REST（`/api/v1/detection/detect`、`/api/v1/verification/verify`、`/api/v1/recognition/*`）。全局 `SecurityValidationFilter` 校验 `x-api-key` 与服务类型绑定关系；verification 的 1:1 相似度在 api 侧用两图 embedding 的欧氏距离在**内存**中完成，不落库 |
| **compreface-core** | **自定义** `compreface-core-yunet-sface:1.2.0` | 3000 | 仅内部网络 | ML 推理核心（Python 3.8 + uwsgi 单进程）。加载 YuNet/SFace 插件，提供 `/status`、`/healthcheck`、`/detect`、`/calculate` 等内部端点；权重从只读挂载 `/opt/face-weights` 加载。`EXTRA_PLUGINS` 已补丁置空——**不加载 landmarks/agegender/mask/pose 等属性类插件**（SP-3 不产出任何人脸属性） |
| 宿主 PostgreSQL（外部） | 宿主已运行实例 | 5432 | `host.docker.internal:5432` | 库 `compreface`，账号 `postgres/postgres`。存管理员账号、应用/服务/Key、调用统计；**不存在内置 postgres 容器与命名卷**。禁用 recognition 时库内无任何当事人人脸图像/向量 |

### 1.3 模型清单（G3 权重授权子项留档口径）

| 角色 | 模型 | 权重文件 | 大小 | SHA256 | 许可 | 加载方式 |
|---|---|---|---|---|---|---|
| 人脸检测 | **YuNet**（OpenCV Zoo，2023mar） | `models/face_detection_yunet_2023mar.onnx` | 227 KB | `8F2383E4DD3CFBB4553EA8718107FC0423210DC964F9F4280604804ED2552FA4` | Apache-2.0（OpenCV 系） | `cv2.FaceDetectorYN`（opencv-contrib-python-headless 4.9.0.80，自带 ONNX 后端） |
| 人脸识别 / 1:1 特征 | **SFace**（OpenCV Zoo，2021dec） | `models/face_recognition_sface_2021dec.onnx` | 37 MB | `0BA9FBFA01B5270C96627C4EF784DA859931E02F04419C829E83484087C34E79` | Apache-2.0（OpenCV 系） | `cv2.FaceRecognizerSF`，128 维 L2 归一化特征 |

说明：

- 插件以 Python 包形式注入镜像：`build/core-build/yunet/`（`yunet.FaceDetector@yunet_2023mar`）与
  `build/core-build/sface/`（`sface.Calculator@sface_2021dec`），通过环境变量
  `FACE_DETECTION_PLUGIN` / `CALCULATION_PLUGIN` 选择，遵循 CompreFace 官方插件契约
  （`FaceDetectorMixin` / `CalculatorMixin`），**无需修改任何 Java 代码**。
- 相似度口径：verify 返回的 `similarity` 由 Java 侧欧氏距离转换（`/status` 的
  `similarity_coefficients=[1.0, 5.0]`），取值 0~1，**与论文余弦阈值口径不同**，
  G2 本地标定前不得把任何阈值写入生产配置。
- 训练数据集（WIDER FACE / CASIA-WebFace / WebFace260M 等）许可仍属 G3 三层核实待办项；
  「权重授权」子项已解决不等于 G3 整体通过。

### 1.4 服务间通信关系

| 调用方 | 目标 | 协议/端口 | 用途与关键变量 |
|---|---|---|---|
| 业务调用方 | compreface-nginx | HTTP :8050，头 `X-API-Key`（外层 key） | detect / verify；key 错误 → 401 |
| compreface-nginx | compreface-fe | HTTP `COMPREFACE_UPSTREAM`（默认 `http://compreface-fe:80`） | 转发 `/face/api/v1/*`（剥前缀） |
| compreface-nginx | （随转发注入） | `proxy_set_header x-api-key` | detection 路径注 `COMPREFACE_DET_KEY`，verification 路径注 `COMPREFACE_API_KEY` |
| compreface-fe（内置 nginx） | compreface-admin | HTTP `compreface-admin:8080`，`/admin/*` | 控制台管理请求 |
| compreface-fe（内置 nginx） | compreface-api | HTTP `compreface-api:8080`，`/api/v1/*` | 数据面请求 |
| compreface-api | compreface-core | HTTP `FRS_CORE_URL=http://compreface-core:3000` | 检测/特征提取（uwsgi） |
| compreface-admin | compreface-core | HTTP :3000 | 健康探测、服务可用性检查 |
| admin / api | 宿主 PostgreSQL | JDBC `POSTGRES_URL=jdbc:postgresql://host.docker.internal:5432/compreface` | 业务/管理数据（liquibase 建表） |
| compreface-core | 宿主卷 `./models` | 只读挂载 `/opt/face-weights` | 运行期加载 ONNX 权重 |

> **运维陷阱**：FE 内置 nginx 在**启动时**解析上游容器 IP。`admin`/`api` 容器重建（IP 变化）后
> 必须 `docker restart compreface-fe`，否则请求会被路由到持有旧 IP 的错误服务
> （典型症状：`/admin/*` 返回 api 的 `Missing header: x-api-key`，code 20）。

---

## 第二部分：部署手册

### 2.1 环境准备（墙内）

1. **Docker Desktop + WSL2**，确认 daemon 出网：
   - `docker info` 查看 HTTP/HTTPS Proxy。若继承系统死代理（`http.docker.internal:3128`），
     先把注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 的
     `ProxyEnable` 置 `0` 并重启 Docker Desktop（会中断现有容器，择机执行）；
     TLS 握手成功但下载失败 = 代理已死，不是镜像不存在。
   - 或在 daemon.json 配 `registry-mirrors`（docker.1ms.run / daocloud / 阿里云）。
2. **宿主 PostgreSQL**：监听 `0.0.0.0:5432`（或已映射到宿主），账号 `postgres/postgres`，
   防火墙/`pg_hba.conf` 允许来自 Docker 网关的连接。
3. **模型权重（一次性）**：两份 ONNX 已在 `models/`（SHA256 见 §1.3）。换机重放时：
   GitHub LFS 直链（raw/media）只会拿到指针文件，须用带 git-lfs 的本地 clone +
   `sparse-checkout` 经 VPN 代理拉取 `opencv/opencv_zoo` 的对应目录（参考
   `download-weights.ps1` 注释）。放入 `models/` 后 `verify.ps1` 第 0 段做离线 SHA256 比对。
4. **端口核对**（本机约定避让）：OCR `8011`、SER `8020/8021`、paddle-nginx `8080`、`80`（GPUStack）。
   本系统占用 **8050（对外）**、**8051（回环 UI）**。

### 2.2 首次部署步骤

```powershell
# ① 构建自定义 core 镜像（一次性；或 .\scripts\build-core.ps1）
docker build -f build/core-build/Dockerfile -t compreface-core-yunet-sface:1.2.0 build/core-build/

# ② 生成 .env（deploy.ps1 会自动复制 .env.example 并注入随机外层 API_KEY）
Copy-Item .env.example .env
.\scripts\deploy.ps1        # compose up -d + 等待 compreface-core / compreface-nginx healthy
```

前置检查：`compreface` 数据库必须已存在（PG 不会自建库）：

```powershell
docker run --rm -e PGPASSWORD=postgres postgres:15-alpine psql -h host.docker.internal -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='compreface'"
# 不存在则：
docker run --rm -e PGPASSWORD=postgres postgres:15-alpine createdb -h host.docker.internal -U postgres compreface
```

### 2.3 创建管理员与服务 key（REST 引导，或走回环 UI）

回环 UI：`http://127.0.0.1:8051/login`（当前 OWNER 账号见运维留档）。REST 等价流程：

```powershell
$base = 'http://127.0.0.1:8051/admin'

# 1) 注册管理员（免鉴权；首个注册用户不会被自动授 OWNER，需库内提权）
Invoke-RestMethod -Method Post -Uri "$base/user/register" -ContentType 'application/json' `
  -Body (@{email='ops@example.local'; firstName='Ops'; lastName='User'; password='<强密码>'} | ConvertTo-Json)

# 1b) 提为 OWNER（注意：全局只允许一个 OWNER，两个 OWNER 会导致建应用 500 NonUniqueResultException）
@'
UPDATE "user" SET global_role='O' WHERE email='ops@example.local';
'@ | docker run --rm -i -e PGPASSWORD=postgres postgres:15-alpine psql -h host.docker.internal -U postgres -d compreface

# 2) OAuth2 登录（注意：token 要放 CFSESSION Cookie，Bearer 头无效）
$login = Invoke-RestMethod -Method Post -Uri "$base/oauth/token" `
  -Headers @{ Authorization='Basic Q29tbW9uQ2xpZW50SWQ6cGFzc3dvcmQ=' } `   # CommonClientId:password
  -Body @{ username='ops@example.local'; password='<强密码>'; grant_type='password' }
$sess = @{ 'Cookie' = "CFSESSION=$($login.access_token)" }

# 3) 建应用
$app = Invoke-RestMethod -Method Post -Uri "$base/app" -Headers $sess -ContentType 'application/json' `
  -Body (@{name='sp3-face-verify'} | ConvertTo-Json)

# 4) 建两个服务（key 与服务类型绑定，不可混用！）
$v = Invoke-RestMethod -Method Post -Uri "$base/app/$($app.id)/model" -Headers $sess -ContentType 'application/json' `
  -Body (@{name='face-verify-1to1'; type='VERIFY'} | ConvertTo-Json)      # → COMPREFACE_API_KEY
$d = Invoke-RestMethod -Method Post -Uri "$base/app/$($app.id)/model" -Headers $sess -ContentType 'application/json' `
  -Body (@{name='face-detect'; type='DETECTION'} | ConvertTo-Json)        # → COMPREFACE_DET_KEY
```

把 `VERIFY` 服务 key 回填 `.env` 的 `COMPREFACE_API_KEY`、`DETECTION` 服务 key 回填
`COMPREFACE_DET_KEY`，然后重建 nginx：

```powershell
docker compose up -d --force-recreate compreface-nginx
```

### 2.4 配置项说明（.env）

| 变量 | 默认 | 说明 |
|---|---|---|
| `COMPREFACE_VERSION` | `1.2.0` | 官方镜像版本（api/admin/fe） |
| `COMPREFACE_CORE_IMAGE` | `compreface-core-yunet-sface:1.2.0` | 自定义 core 镜像 tag，必须与构建输出一致 |
| `COMPREFACE_NGINX_PORT` / `COMPREFACE_UI_PORT` | `8050` / `8051` | 业务入口 / Web 控制台端口 |
| `COMPREFACE_UI_BIND` | `127.0.0.1` | 控制台绑定地址；设 `0.0.0.0` 后内网任意机器可访问 `:8051`（管理端无外层 key 保护，需评估网络边界；远端 192.168.110.169 已设为 `0.0.0.0`） |
| `API_KEY` | deploy.ps1 随机生成 40 位 | **外层 key**，业务调用方唯一持有，`X-API-Key` 头 |
| `COMPREFACE_API_KEY` | 需回填 | VERIFY 服务 key（verification 路径注入） |
| `COMPREFACE_DET_KEY` | 需回填 | DETECTION 服务 key（detection 路径注入） |
| `POSTGRES_HOST` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | `host.docker.internal` / `postgres` / `postgres` | 宿主库连接；compose 用前两者拼出 `POSTGRES_URL`（Spring 只认 `POSTGRES_URL`） |
| `PG_DB` | `compreface` | 库名；须预先存在 |
| `MAX_FILE_SIZE` / `MAX_REQUEST_SIZE` | `10MB` | Spring multipart 上限，**必须带单位** |
| `FACE_DET_SIZE` / `FACE_MIN_DET_SCORE` | `640` / `0.5` | 检测输入长边 / 检置信门槛（G1 标定后回写） |
| `FACE_DETECTION_PLUGIN` / `CALCULATION_PLUGIN` | `yunet.FaceDetector@yunet_2023mar` / `sface.Calculator@sface_2021dec` | 插件选择（`包.类@模型名`） |
| `EXTRA_PLUGINS` | 空者最宜 | 追加属性类插件；**必须留空**（不得写 `""`，引号会当字面字符传进容器） |
| `FACE_DET_MODEL` / `FACE_REC_MODEL` / `FACE_*_SHA256` | 已填真实值 | 权重文件名与期望哈希（verify.ps1 第 0 段离线比对） |
| `FACE_WEIGHTS_DIR` | `./models` | 权重挂载源（只读挂到 `/opt/face-weights`） |
| `MEETING_FACE_POC_PASSED` | **恒 `false`** | 上线门禁开关，四道门禁留档齐备并人工确认前禁止改动 |

### 2.5 服务启动 / 停止 / 状态

```powershell
.\scripts\deploy.ps1     # 启动（首次生成 .env）+ 等待 core/nginx healthy（最多 900s）
.\scripts\status.ps1     # 容器状态、探针、资源占用
.\scripts\stop.ps1       # 停止（PG 为外部宿主库，无命名卷可删）
docker compose up -d --force-recreate compreface-nginx   # 改 .env 后仅重建网关
docker compose logs -f compreface-core                    # 排障看日志
```

健康判定：`docker ps` 中 `compreface-core` 应为 `(healthy)`（uwsgi `/healthcheck`），
`compreface-nginx` 应为 `(healthy)`（`/face-nginx-health`）。

### 2.6 部署验证

```powershell
.\scripts\verify.ps1
```

9 项断言：0) 权重 SHA256×2；0b) 自定义镜像存在；1) nginx 存活；2) 无 key 401；
3) detect 返回 `box.probability`；4) verify 同人 similarity>0.7、异人（如提供）<0.5；
5) recognition 路径 404。全绿输出 `pass=9 fail=0 skip=0`。

样例图（`samples/`，不入仓，可从 CompreFace 源码 `embedding-calculator/sample_images/` 取）：
`face.jpg`（001_A）与 `face_same_person.jpg`（004_A，同人两拍）、`face_other_person.jpg`（007_B，异人）。

### 2.7 API 调用示例（业务调用方视角）

所有请求经 `:8050`，带外层 `X-API-Key`；**两图须各恰好一张人脸**（多脸/无脸直接 400）。

```powershell
$k = '<外层 API_KEY>'   # .env 的 API_KEY

# ① 人脸检测（返回人脸框与置信度）
curl.exe -X POST "http://127.0.0.1:8050/face/api/v1/detection/detect?limit=1" `
  -H "X-API-Key: $k" -F "file=@会中帧.jpg"
# 200 → { "result": [ { "box": { "probability":0.94, "x_min":..,"y_min":..,"x_max":..,"y_max":.. } } ] }

# ② 1:1 比对（证件照 source_image + 会中帧 target_image）
curl.exe -X POST "http://127.0.0.1:8050/face/api/v1/verification/verify" `
  -H "X-API-Key: $k" -F "source_image=@证件照.jpg" -F "target_image=@会中帧.jpg"
# 200 → { "result": [ { "source_image_face": { "box": {...} },
#                      "face_matches": [ { "box": {...}, "similarity": 0.919 } ] } ] }
```

实测参考点（官方样例图，CPU）：同人 0.919 / 异人 0.078，区分度充足；
热态延迟 verify ≈2.5s、detect ≈2.9s（400 万像素大图；640 长边会中帧预计显著更快，
真实帧 P50/P95 由 G1 实测）。

### 2.8 常见使用场景操作流程

**场景 A：接入新的业务调用方**
1. 评估是否需要隔离 key；如需，在 UI/REST 新建一个 App + VERIFY/DETECTION 服务，把新服务 key
   告知网关管理员（即由 nginx 注入，业务侧无感知；若需多业务分别注入，须扩展 nginx 模板按来源路由）。
2. 当前默认形态：所有业务共用外层 `API_KEY`，轮换时改 `.env` 后 `--force-recreate compreface-nginx`。

**场景 B：轮换服务 key（泄露/定期）**
1. `PUT /admin/app/{guid}/model/{guid}/apikey`（CFSESSION Cookie）→ 得新 key；
2. 回填 `.env` 对应变量 → `docker compose up -d --force-recreate compreface-nginx`；
3. `verify.ps1` 回归。

**场景 C：更换模型权重（如 G3 核实后需换件）**
1. 按三层许可核实清单先评审核实新权重；
2. 替换 `models/*.onnx`，更新 `.env` 的文件名与 SHA256；
3. `build/core-build/yunet|sface` 插件代码按新模型适配（输入尺寸等）→ `build-core.ps1` 重建镜像；
4. `docker compose up -d --force-recreate compreface-core` → `verify.ps1` 回归；
5. **阈值须重新标定（G2）**，相似度分布随模型改变。

**场景 D：核验一条业务请求（1:1 流程）**
1. 业务侧取证件照字节（临时、不落盘）+ 会中帧 → 调 verify；
2. 解析 `result[0].face_matches[0].similarity`；
3. 与 G2 标定阈值比较出结论；平台只存 similarity、结论与依据摘要，不存图/向量；
4. 单帧不结论，连续帧保守判定由业务编排层实现，**永不自动改 `party_identity.status`**。

### 2.9 故障排查指引

| 症状 | 根因与处置 |
|---|---|
| core 起不来，日志 `ModuleNotFoundError: ...plugins."""` | compose 的 `${EXTRA_PLUGINS:-""}` 把引号当字面字符传进容器；默认值必须写 `${EXTRA_PLUGINS:-}`（已修，勿回退） |
| api/admin 反复重启，`UnknownHostException: compreface-postgres-db` | 只配了 `POSTGRES_HOST`；Spring 只认 `POSTGRES_URL`（compose 已改为拼接注入） |
| fe 反复重启，`"client_max_body_size" directive invalid value` | FE 内置 nginx 模板缺 `CLIENT_MAX_BODY_SIZE` 等变量（compose 已补齐） |
| 调用返回 `Maximum upload size exceeded ... (10)` | `MAX_FILE_SIZE` 写了裸数字（按字节解析）；改为带单位如 `10MB` |
| `/admin/*` 返回 `Missing header: x-api-key`（code 20） | FE nginx 上游 IP 过期（admin/api 容器重建过）；`docker restart compreface-fe` |
| detect 返回 code 10 `service not found` | 用了 VERIFY key 调 detection；确认 nginx 注入的是对应类型 key |
| verify 返回 code 31 `More than one face` | 源图含多张人脸；1:1 接口要求两图各恰好一张脸 |
| verify 返回 code 28 `No face is found` | 未检出人脸：图像太小/太糊/侧脸过度，或低于 `FACE_MIN_DET_SCORE` |
| verify 返回 code 26 `Service API key should be UUID` | nginx 注入的服务 key 不是 UUID（.env 未回填/被覆盖）；重建 nginx 后用 `docker exec compreface-nginx grep 'x-api-key "' /etc/nginx/conf.d/default.conf` 核对 |
| 建应用返回 500 `NonUniqueResultException: 2` | 库里有两个 OWNER；保留唯一 OWNER，其余改回 `'U'` |
| 建应用返回 code 9 `Action not allowed` | 当前用户不是 OWNER；且全局只能有一个 OWNER |
| 构建镜像时 pip 下载失败 | Docker daemon 走了死代理；见 §2.1 处置，或确认 Dockerfile 内已用清华 PyPI 源 |
| 登录 UI 报 `Bad credentials` | 账号密码不符（首轮随机密码未留存）；用已留档的 OWNER 账号，或注册新号并库内提权（注意唯一 OWNER） |

### 2.10 安全与合规边界（部署层已固化的约束）

- **1:N 红线**：nginx 白名单仅放行 detection/verification，`recognition/*`、`subjects/*` 404；
  平台不因本部署产生任何人脸底库。
- **双层密钥**：业务侧只见外层 `API_KEY`；CompreFace 服务 key 仅存于 `.env` 与 nginx 配置，
  可独立轮换。`.env` 已被 `.gitignore` 排除，禁止入库。
- **属性类插件全禁**：core 镜像已置空 `EXTRA_PLUGINS`，不产出年龄/性别/口罩/姿态等属性。
- **无向量持久化**：1:1 比对由两图 embedding 在内存完成；数据库仅存账号、应用/服务、统计。
- **卷留存与删除**：无内置 PG 卷；数据在宿主 `compreface` 库，删除走数据删除审批并登记时间/操作人。
- **日志红线**：禁止图像 base64 长串与证件照 URL 全串入日志；外层 nginx 不记录请求体。

---

## 附：目录与脚本索引

| 路径 | 说明 |
|---|---|
| `docker-compose.yml` | 5 服务编排（core/admin/api/fe/nginx），外部宿主 PG |
| `.env.example` → `.env` | 配置样例 → 实际配置（不入库） |
| `nginx/default.conf.template` | 对外网关：白名单 + 双 key 注入 |
| `build/core-build/` | 自定义 core 镜像构建上下文（yunet/sface 插件 + Dockerfile + EXTRA_PLUGINS 补丁） |
| `scripts/deploy.ps1` | 生成 .env、门禁校验、拉起、等健康 |
| `scripts/build-core.ps1` | 构建自定义 core 镜像 |
| `scripts/verify.ps1` | 9 项契约验证（本目录唯一可执行证明） |
| `scripts/status.ps1` / `stop.ps1` | 状态 / 停止 |
| `models/` | ONNX 权重（只读挂载，不入库） |
| `samples/` | 验证样例图（不入库） |
| `README.md` | 门禁登记与实测留档（V1–V9） |
