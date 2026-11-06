# SP-4 声学情感（SER）部署件

> **状态（2026-11-06）：代码层已交付、契约验证 5/5 通过，但上线门禁未全过。**
> 本目录已按 `mediation-docs/superpowers/specs/2026-11-04-acoustic-ser-design.md` §8.2 补齐
> 推理服务与编排；**离线依赖（9 个 wheel）与模型权重（1.81GB）已就位**，**镜像已构建、容器已 healthy 运行、`verify.ps1` 五段契约 5/5 通过**。
> 已实测回写：U1（generate 收 ndarray、`fs`/`sampling_rate` 均接受）/ U2（标签形如 `难过/sad`、实际输出 5 类 `{angry,happy,neutral,sad,unk}`、`unk` 已入拒分类）/ U3（⚠️ 此前"热~738ms、冷~995ms <1500ms"是 **3s 短音频/静音拒答路径**延迟，未跑模型；CPU 长音频实测 P95 3.97–40.05s 远超 1500ms → §8.4 延迟门禁 **CPU FAIL**；**GPU 分支 A（torch 2.7.1+cu128）预热后 P95 75–566ms → PASS**）/ U4（镜像 2.26GB、权重运行时只读挂载不烘焙、ready 充裕）。
> 已确认：模型商用许可——法务核实 ModelScope 权重许可证无需留档（2026-11-06）。已测：§8.4 延迟门禁 **CPU 分支 FAIL / GPU 分支 A PASS**（CPU P95 3.97–40.05s 远超 1500ms；GPU cu128 预热后 P95 75–566ms，见 U3/§8.4）；资源挤占：CPU 分支 SER 峰值 723% CPU（待部署机同机复测）、**GPU 分支 2 并发显存峰值 4796MB / 12227MB（余量 60.8%）、SER CPU 峰值 102.7%、225/225 请求 HTTP 200、同机 CompreFace 未受挤占**；无静默降级本件层面 PASS（停 SER→504 无 calm，Java 侧待验）。仍待测：U5（真实会议方言/交叠人检）、人检一致率 ≥70%（需真人听记对照，已备 `e2e-smoke.ps1`）。
> GPU 分支 A PoC 已完成（2026-11-07）：`Dockerfile.gpu` 最终为 **torch 2.7.1+cu128**（⚠️ 2.6.0+cu124 在 RTX 5070 Ti / Blackwell sm_120 上报 `no kernel image is available`，全量推理 500，已修正）；`docker-compose.gpu.yml` 独立 project `ser-gpu`、GPU 变量写死、nvidia device reservation、端口 8022/8023。镜像 `emotion2vec:gpu-cu128`（6.71GB）已构建、容器 healthy、真实 matmul 校验 `KERNEL_OK`；`latency_bench_gpu.ps1` 20 次/段 → **预热后** 10s P95=75ms、30s=260ms、60s=566ms（**PASS**，较 CPU 快 47–67×）；冷启动首轮 10s P95=2659ms（模型加载 ~60s + CUDA warmup 2.66s）仍 FAIL，须以启动预热/就绪探针消除。GPU 容器当前为 PoC 验证态，开关仍 `false`、未接入业务链路。
> 开关仍 `false`：`MEETING_SER_ENABLED` / `MEETING_SER_POC_PASSED` / `MEETING_G3_SER=false`、`SER_PROVIDER=none`；在 §8.4 全部门禁通过之前（模型商用许可已法务确认无需留档），**不得接入业务链路**。GPU 分支已完成延迟与资源两项 PoC，**仍不构成上线许可**。仍待测：U5（真实会议方言/交叠人检）、人检一致率 ≥70%（需真人）、部署机与 OCR 同机且 OCR 忙碌时的挤占复测、Java 侧 `available=false` 聚合、真实会议录音延迟复核、GPU 与同机其他 GPU 服务共存时的算力争抢（本机 2 并发 GPU util 已打满 100%）。已实测项已回填下表，未实测项仍标 `待测`。

## 目录

| 文件 | 作用 |
|---|---|
| `docker-compose.yml` | `emotion2vec`（模型容器，宿主 `127.0.0.1:8021`，不挂音频卷）＋ `ser-nginx`（对外 `8020`，`X-API-Key` 鉴权）；含 `build:` 上下文，可从本仓直接构建 |
| `emotion2vec/app.py` | §8.2.5 推理服务：`/health` ＋ `/v1/audio/emotion`（multipart），惰性加载、单并发门、静音与 `other/unknown/unk` 拒答；U2 实测标签形如 `难过/sad`，取 `/` 后英文段映射 |
| `emotion2vec/Dockerfile` | §8.2.2：离线 `wheels/` 优先装依赖、权重**不烘焙**（改运行时只读挂载 `models/`→`/models`，实测 1.81GB 撑镜像） |
| `emotion2vec/requirements.txt` | §8.2.3 版本清单（见下方「版本清单」） |
| `emotion2vec/wheels/` | 离线 wheel 已投放（9 个：torch 181MB CPU 版 + torchaudio + numpy/fastapi/uvicorn/python-multipart/soundfile 0.13.1/funasr/modelscope；日志与 `.err` 为下载辅助，勿随镜像提交） |
| `models/` | 模型权重目录（已下载 `iic/emotion2vec_plus_large` 约 **1.81GB**，运行时只读挂载到 `/models`；**不进镜像、应在 .gitignore 中排除**） |
| `download_model.py` | 权重下载辅助脚本（依赖 `pip install modelscope`；仅部署准备用，可删） |
| `nginx/default.conf.template` | §8.2.6：对外 `/ser/*` 剥前缀后转容器同名路径；`/ser-nginx-health` 免鉴权探针 |
| `.env.example` | 无明文默认值的环境变量样例 |
| `scripts/deploy.ps1` | 首次生成 `.env` 与随机 40 位 `API_KEY`、构建启动、等健康（900s） |
| `scripts/status.ps1` | 探活 ＋ `docker stats --no-stream`（分支 B 下判断 SER 是否挤占 OCR CPU 的唯一手段） |
| `scripts/verify.ps1` | 五段契约验证：nginx 探针 / `labels_supported` / 无 key 401 / 真 wav 五值 / 3s 静音拒答 |
| `scripts/stop.ps1` | 停止（`-Volumes` 开关），默认无命名卷 |
| `scripts/e2e-smoke.ps1` | §8.4 人检一致率**离线取数**工具：批量 wav → CSV（emotion/confidence/latency）供真人听记对照（`-WavDir` / `-OutCsv` / `-BaseUrl`）；本机无 LiveKit/JWT，不实现七步实时拉流，**待真实会议片段执行**。CPU 走 8020/ser、GPU 走 8023/ser（`-BaseUrl http://127.0.0.1:8023/ser`） |
| `emotion2vec/Dockerfile.gpu` | GPU 分支 A：`torch 2.7.1+cu128`（Blackwell sm_120 必需），阿里云 `pytorch-wheels/cu128` flat 镜像以 `--find-links` 安装，tuna 作主 index 兜底其余依赖；镜像 `emotion2vec:gpu-cu128`（6.71GB，权重仍只读挂载不烘焙） |
| `docker-compose.gpu.yml` | GPU 编排：独立 project `ser-gpu`（与 CPU 编排隔离）、GPU 变量写死不读 `.env`、nvidia device reservation、`SER_DEVICE=cuda:0`、端口 8022/8023 |
| `scripts/latency_bench.ps1` | CPU 分支延迟取证（10/30/60s 各 20 次 → P50/P95） |
| `scripts/latency_bench_gpu.ps1` | GPU 分支延迟取证（走 8023/ser；wav 文件名带 PID 防并发抢写；错误响应立即中止，杜绝假数据） |
| `scripts/resource_bench.ps1` | CPU 分支资源挤占取证（2 并发 + `docker stats` 采样） |
| `scripts/resource_bench_gpu.ps1` | GPU 分支资源门禁取证（2 并发 60s 负载 + `nvidia-smi` 显存/利用率 + `docker stats` + 容器内 `torch.cuda.mem_get_info`；输出 `gpu_resource_bench.log`） |
| `scripts/gpu_poc_pipeline.ps1` | GPU PoC 流水线：等镜像 → 起服务 → **真实 matmul** 校验 CUDA kernel → 跑延迟对比 |

## 契约（对齐 spec §4.2、§8.2.1、§8.2.5、§8.2.6、§10.4）

```
调用方 base-url = http://<host>:8020/ser      # nginx 前缀，/ser 由 nginx 剥掉
POST {base-url}/v1/audio/emotion              # multipart: file=seg.wav, sample_rate=16000, language=zh
  Header: X-API-Key: ***
  -> 200 {"emotion":"anger","confidence":0.68,"model":"<自报>","latencyMs":412,
          "rawLabel":"angry","scores":{...}}
  -> 400 音频非法 / 409 拒分类或静音 / 429 并发满 / 500 推理失败 / 502 返回体异常
GET  {base-url}/health                         # 需 X-API-Key
  -> {"status":"ok","gpu_available":false,"device":"cpu","model":"...",
      "ready":false,"persistence":false,"labels_supported":[...],"max_inflight":2}
GET  http://<host>:8020/ser-nginx-health      # 免鉴权，只证明网关活着
```

- `emotion` 只取五值 `calm/anxious/agitated/anger/threat`；未知标签一律非 2xx，worker 侧显式抛错，**不降级为 `calm`**。
- 官方 9 类 → 平台 5 类映射（§8.2.4）：`neutral/happy→calm`、`fearful/sad→anxious`、`surprised/disgusted→agitated`、`angry→anger`；`other/unknown` 与全静音一律拒答；**本 provider 永不产生 `threat`**（语义判断属 SP-2 文本侧）。
- 3s 全静音必须返回 409/502，**不得**返回 200 `calm`。
- 端口 `8020/8021` 与 OCR `8011`、CompreFace `8050/8051` 不冲突。

## 版本清单（§8.2.3：设计假定值，PoC 时按实际安装版本回写）

| 包 | 当前写法 | 状态 |
|---|---|---|
| `fastapi` / `uvicorn[standard]` / `python-multipart` / `numpy` | 与 `paddle/pp-ocrv6/requirements.txt` 逐字一致 | 已验证可装版本组（沿用 OCR 侧） |
| `soundfile` | `0.13.1` | **实测可用版**（`tuna` 源已无 `0.2.1`；`requirements.txt` 同步改为 `0.13.1`） |
| `funasr` / `modelscope` | `1.2.7` / `1.23.0` | **设计假定值**：仓内无版本记录，PoC 时以 `pip index versions` 实测取值为准并回写本表 |
| `torch` / `torchaudio` | CPU：`2.3.1`（离线 wheels，`Dockerfile`）；GPU：`2.7.1+cu128`（`Dockerfile.gpu`） | CPU 为设计假定值；**GPU 版本实测**：`2.6.0+cu124` 在 RTX 5070 Ti(sm_120) 上无 kernel、全量 500，**必须 `2.7.1+cu128`**；`funasr==1.2.7` / `modelscope==1.23.0` 与之共存无冲突 |

## U1–U5 待实测项（spec §8.2.9，禁止当作已知）

> 五项须在 G1 当场实测后把**真实结论**回填本表；未回写前 SP-4 不得上线。
> 注意：这五项是 §8.2.9 的**库行为与部署实测**，与 §8.4 的六条上线门禁是两组不同判据。

| # | 待实测项 | 为何不能先猜 | 实测结果 |
|---|---|---|---|
| U1 | `funasr.AutoModel.generate` 能否直接收 ndarray，参数名是 `fs` 还是 `sampling_rate` | 决定 §9 不落盘能否不借助 `/dev/shm`；属库版本行为，`app.py` 的调用签名须按实测校准 | **实测**（funasr 1.2.7）：`generate(input=ndarray, fs=rate, sampling_rate=rate)` 直接收 ndarray，无需 `/dev/shm`；`fs` 与 `sampling_rate` 均接受 |
| U2 | 返回体 `labels` 的字面量形态（裸字母 / 尖括号竖线包裹 / 带序号前缀） | `app.py::_norm()` 已容错三种形态，但实际形态需留档，否则映射表无法审计 | **实测**：真实标签形如 `难过/sad`（中文/英文）；实际输出标签集为 5 类 `{angry,happy,neutral,sad,unk}`（非设计 9 类）；`unk` 已加入 `REJECT`；`_norm` 取 `/` 后英文段 |
| U3 | 3s 音频在分支 B（CPU、`SER_TORCH_THREADS=8`）上的 P50/P95 延迟 | §8.3 的 `1500 ms` 是设计值，不是实测值 | **实测（修正）**：3s 短音频/静音拒答路径 热~738ms、冷~995ms（不跑模型）；**CPU 长音频真实推理**（`latency_bench.ps1` 20 次/段）：10s P50=2.88s/P95=3.97s、30s P50=12.84s/P95=14.34s、60s P50=36.39s/P95=40.05s，随长度**超线性**增长（≈3.6s/10s），CPU 分支 B 远不能满足 ≤1500ms。**GPU 分支 A 实测**（`latency_bench_gpu.ps1`，torch 2.7.1+cu128 / RTX 5070 Ti sm_120）：预热后 10s P50=61ms/P95=75ms、30s 236/260ms、60s 543/566ms，全部 ≤1500ms（较 CPU 快 47–67×）；冷启动首轮 10s P95=2659ms（首次请求模型加载 ~60s + CUDA warmup 2.66s）不达标，须启动预热。结论：1500ms 门禁在 CPU 分支不成立，在 GPU 分支（含预热）成立 |
| U4 | 权重烘焙后的镜像体积与首次 `ready` 耗时（`start_period: 120s` 是否够） | healthcheck 太短会反复重启，太长会掩盖真故障 | **实测（CPU）**：权重运行期只读挂载（不烘焙），镜像 2.26GB；模型懒加载于首次请求（~数秒），`start_period:120s` 充裕。**实测（GPU）**：镜像 `emotion2vec:gpu-cu128` 6.71GB，同样不烘焙权重；但 `healthy` 只证明 HTTP 活着，**首次真实推理另需 ~60s 加载模型 + CUDA 初始化**，`start_period` 不能覆盖这段，须在就绪探针里显式预热 |
| U5 | 中文调解方言、多人交叠下的标签有效性与人检一致率 | §8.4 人检门禁的实测数据归口 | 待测（需真实会议音频，阶段 3/4 真人） |

## §8.4 上线前置门禁（PoC，未过不得上线）

| 门禁 | 判据 | 结论 |
|---|---|---|
| 延迟 | 3 段真实会议录音（10s/30s/60s）各跑 20 次，P95 ≤ 1500 ms | **CPU FAIL / GPU PASS（实测）**：CPU 分支 B（`latency_bench.ps1` 合成语音近似真实，20 次/段）10s P50=2.88s/P95=3.97s、30s 12.84/14.34s、60s 36.39/40.05s，随长度超线性增长，远超 1500ms。GPU 分支 A（`latency_bench_gpu.ps1`，`emotion2vec:gpu-cu128` / torch 2.7.1+cu128 / sm_120，20 次/段）**预热后** 10s P50=61ms/P95=75ms、30s 236/260ms、60s 543/566ms，**全部 ≤1500ms（PASS）**；但**含冷启动的首次 20 次** 10s P95=2659ms（FAIL，模型加载 ~60s + CUDA warmup 2.66s）。判据成立条件：必须上 GPU **且** 在就绪探针里完成预热（首请求不计入业务流量）。⚠️ 两段均用合成语音近似真实，真实会议录音/U5 方言与交叠复核仍待测 |
| 资源 | 峰值显存或 CPU 线程占用；分支 B 在 2 并发下不得使同机 OCR 的 `OCR_CPU_THREADS=10` 饥饿 | **CPU 分支：部分/待复测**：`resource_bench.ps1` 2 并发下 SER 峰值 CPU≈723%（≈7 核满载，单并发门串行），同机 CompreFace 始终 idle（0.4%）未受挤占；但本机无 pp-ocrv6 OCR 容器（在 192.168.40.30），**最终判定须部署机与 OCR 同机、OCR 忙碌时复测**。**GPU 分支 A：本机 PASS（2026-11-07 `resource_bench_gpu.ps1`）**：2 并发 60s wav 持续负载、30 点 `nvidia-smi` + `docker stats` 采样 → 显存峰值 **4796 / 12227 MB**（相对模型加载后基线 +2620 MB，余量 **7431 MB / 60.8%**）、GPU util 峰值 **100%**、mem util 峰值 42%、SER CPU 峰值 **102.7%**（≈1 核，对比 CPU 分支 723%）、容器内存 1.189GiB/6GiB、同机 CompreFace CPU 峰值 0.2% 未受挤占、**225/225 请求 HTTP 200 无失败**；device reservation 生效（容器内 `torch 2.7.1+cu128` 真实 matmul 通过）。⚠️ 限制：WSL2 下宿主 `nvidia-smi --query-compute-apps` 看不到容器 CUDA 进程（显示 `[Not Found]/[N/A]`），且容器内 `torch.cuda.mem_get_info()` 视图在 idle/loaded/cooled 三时刻恒为 1173MB、**不随负载变化**（vGPU 静态配额视图，不可用于测峰值），故 SER 显存以**宿主全局 `memory.used` 增量**计，基线 2176MB 含宿主 LM Studio/explorer 等；显存冷却后回落至 2186MB（≈基线，无泄漏）；四容器 `RestartCount=0` / `OOMKilled=false` / `ExitCode=0`，无异常重启。GPU util 100% 说明 2 并发已打满算力，**同机若另有 GPU 推理服务须复测算力争抢**；本机无 pp-ocrv6 OCR 容器，部署机最终判定仍待复测 |
| 标签有效性（人检） | 影子模式 2 场真实调解会，声学标签与人工听记一致率 ≥ 70% | 待测 |
| 无静默降级 | 关掉 SER 服务后 `available=false`，告警流无新增 `kind='ser'` 行（而非出现 `calm`） | **本件层面 PASS**：停 `emotion2vec` 后 nginx 返回 504、响应体不含 `calm`（未静默降级为 200 calm）；Java 侧 `available=false` 聚合与告警流无 `calm` 行需在调用方侧另验 |
| 拒分类行为 | 3s 全静音回 409/502，不得回 200 `calm` | **已通过**（`verify.ps1 [5/5]` 实跑：3s 静音返回 409） |
| 标签表一致性 | `/health` 的 `labels_supported` 与 §8.2.4 表格逐项比对 | **已通过**（`verify.ps1 [2/5]` 实跑：9 个官方标签均在 `labels_supported`） |
| 模型许可 | ModelScope 权重许可证与商用条款核实（法务确认） | **已确认**（2026-11-06 法务核实 ModelScope 权重许可证无需留档、无需额外商用授权，条款满足） |

## 部署步骤

```powershell
Copy-Item .env.example .env      # 或让 deploy.ps1 首次自动生成含随机 API_KEY 的 .env
.\scripts\deploy.ps1             # build + up -d + 等 healthy（900s）
.\scripts\status.ps1             # 探活与资源占用
.\scripts\verify.ps1             # 五段契约验证
.\scripts\e2e-smoke.ps1 -Token <jwt> -RoomSid <room> -InternalToken <secret> -Psql "<psql 命令>"
```

`deploy.ps1` 生成的 `API_KEY` 同时写入 `.env` 的 `API_KEY` 与 `SER_API_KEY`；
调用方（`SER_GATEWAY_BASE_URL` / `meeting.ser.base-url`）必须配到 `http://<host>:8020/ser`。

### GPU 分支 A（PoC 验证态，未接入业务链路）

```powershell
docker build -f emotion2vec/Dockerfile.gpu -t emotion2vec:gpu-cu128 emotion2vec
docker compose -f docker-compose.gpu.yml up -d       # project ser-gpu，端口 8022/8023
.\scripts\gpu_poc_pipeline.ps1                       # 等镜像 → 起服务 → CUDA kernel 校验 → 延迟
.\scripts\latency_bench_gpu.ps1                      # 单独复测（预热后稳态）
.\scripts\resource_bench_gpu.ps1                    # 2 并发显存/GPU util/CPU 采样（30 点）
```

实测踩坑（勿重犯）：

1. **Blackwell sm_120 必须 cu128**：`torch 2.6.0+cu124` 的 `is_available()` 返回 True、设备名也对，但 kernel 列表仅 `sm_50…sm_90`，真实运算报 `no kernel image is available for execution on the device`，全量推理 500。故 CUDA 校验必须跑真实 `matmul`，不能只查 `is_available()`。
2. **GPU 编排必须与 CPU 编排隔离**：两文件同目录、共用 `.env` 与 compose project 名时，`.env` 的 `SER_IMAGE=emotion2vec:1.0` / `SER_DEVICE=cpu` / `SER_PORT=8021` / `SER_NGINX_PORT=8020` 会覆盖 GPU 默认值，导致镜像 tag 覆盖 CPU 镜像、容器跑 CPU、端口抢占 8021，且 `up` 会把 CPU 容器当 orphan 停掉。故 `docker-compose.gpu.yml` 用独立 `name: ser-gpu` 并把 GPU 变量写死。
3. **镜像源**：官方 `download.pytorch.org` 限速约 850 KB/s、`download-r2.pytorch.org` 仅约 100 KB/s（768MB 需 2 小时）；清华/阿里云的 PEP503 路径不存在。阿里云 `mirrors.aliyun.com/pytorch-wheels/cu128` 是 **flat 目录**（约 2.5 MB/s），必须用 `--find-links` 而非 `--index-url`；另加 `--extra-index-url tuna` 提供 `flit_core` 等构建依赖，否则 `typing-extensions` 源码包构建失败。
4. **冷启动必须预热**：容器 healthy 只证明 HTTP 活着，首请求含模型加载（~60s）+ CUDA warmup，10s 段 P95 会被拉到 2659ms。上线须在就绪探针里完成预热，首请求不计入业务流量。

## 隐私与边界（spec §9）

- 音频、频谱、中间向量一律不落盘、不挂卷；请求体只在内存中转 WAV；`app.py` 报 `persistence=false`。
  `verify.ps1` 生成的宿主临时 wav 仅用于取证，`finally` 删除，不进入容器与数据库。
- 声学证据**永不单独构成 `danger`**；与文本告警只补写不升级；结论文案统一「疑似…请主持人确认」，不作情绪定性。
- 服务端 `ser` 开关为唯一权威；Java 侧第二次守卫在开关关闭时强制把 `ser_*` 三列写 `NULL`。
- 关闭后最长 30s 仍在采集（快照轮询周期），须写进告知文案，不得隐瞒。
