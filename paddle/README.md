# PaddleOCR 一体化部署（PP-OCRv6，容器化）

本地一键部署 PP-OCRv6 超轻量文本识别服务，统一经 Nginx 反代 + API Key 鉴权对外暴露。
CPU 推理、零显存占用，可直接跑在边缘/笔记本设备。

> 说明：本方案仅包含 **PP-OCRv6 文本识别**。原计划的 PaddleOCR-VL-1.6 文档解析因
> 本地 GPU 驱动兼容性问题（vllm/torch 与 CUDA 12.8 冲突、native 后端在多线程下卡死）
> 暂未纳入；如需文档解析可参考文末「扩展」一节另行评估。

## 一、架构

| 服务 | 镜像 | 算力 | 内部端口 | 对外路径 |
|---|---|---|---|---|
| PP-OCRv6 文本识别 | `pp-ocrv6:1.0`（`pp-ocrv6/` 构建） | CPU（零显存） | 8000 | `/ocr/v6/*` |
| Nginx 反代鉴权 | `nginx:1.27-alpine` | - | 80 | 唯一对外入口 |

```
调用方 --80 + X-API-Key--> Nginx --/ocr/v6--> pp-ocrv6   (CPU)
```

PP-OCRv6 权重在**构建期预热并烘焙进镜像**（约 177MB），运行期不再联网下载；
OCR 容器只绑定 `127.0.0.1`，Nginx 是唯一对外入口。

## 二、快速开始（一键）

```powershell
cd d:\work\mediation_platform\mediation-deploy\paddle
.\scripts\deploy.ps1            # 生成 .env(随机 API_KEY) -> 构建镜像 -> 启动 -> 等待健康
.\scripts\verify.ps1            # 冒烟测试：鉴权 401、OCR 文本识别
```

其他命令：

```powershell
.\scripts\status.ps1                                 # 容器状态 + 直连健康 + 资源占用
.\scripts\status.ps1 -Logs pp-ocrv6                  # 跟踪日志
.\scripts\stop.ps1                                   # 停止（保留镜像与 .env）
.\scripts\stop.ps1 -Volumes                          # 停止并清理卷
```

## 三、接口

均需请求头 `X-API-Key: <.env 中的 API_KEY>`，缺失或错误返回 `401`。

### PP-OCRv6

```bash
curl -H "X-API-Key: $KEY" -F image=@samples/test-ocr.png \
     http://localhost/ocr/v6/ocr
```

```json
{
  "status": "success",
  "data": [{"text": "纯臻营养护发素\n0.993600\n..."}],
  "lines": [{"text": "纯臻营养护发素", "score": 0.99995, "box": [52, 4, 160, 20]}],
  "count": 34
}
```

- `data[0].text` 为按行拼接的全文，兼容既有 Java `PaddleOcrClient` 契约；
- `lines` 为逐行明细（文本 / 置信度 / 检测框）；
- `/ocr/v6/health` 健康检查（同样需鉴权）；`/api/ocr` 是 `/ocr` 的别名。

## 四、配置（.env）

首次运行 `deploy.ps1` 会从 `.env.example` 生成 `.env` 并写入随机 `API_KEY`。关键项：

| 变量 | 默认 | 说明 |
|---|---|---|
| `API_KEY` | 随机 40 位 | 调用凭证，务必替换/保管 |
| `NGINX_HTTP_PORT` | `80` | 对外端口（被占用就改，例如 `8081`） |
| `OCRV6_PORT` | `8011` | 仅绑 `127.0.0.1`，不可绕过 Nginx 直连 |
| `OCR_ENABLE_MKLDNN` | `false` | **不要改成 true**，见故障排查 1 |
| `OCR_CPU_THREADS` | `10` | CPU 推理线程数 |

## 五、故障排查（已踩过的坑）

### 1. PP-OCRv6 在 CPU 上崩溃（必现）

```
NotImplementedError: (Unimplemented) ConvertPirAttribute2RuntimeAttribute
not support [pir::ArrayAttribute<pir::DoubleAttribute>]
  (at /paddle/paddle/fluid/framework/new_executor/instruction/onednn/onednn_instruction.cc:116)
```

paddlepaddle 3.3.0 CPU + oneDNN(PIR) 与 `PP-OCRv6_medium_det` 不兼容。
**修复**：构造 `PaddleOCR(enable_mkldnn=False)`（服务已默认关闭，由 `OCR_ENABLE_MKLDNN` 控制）。
注意 `FLAGS_use_mkldnn=0` 环境变量**无效**——paddlex 会显式传参覆盖。

### 2. OCR 结果解析为空

结果字段不在 `result[i].json` 顶层，而在 `result[i].json["res"]` 内
（`rec_texts` / `rec_scores` / `rec_boxes`）。按顶层取值会得到空文本。

### 3. 传入 `io.BytesIO(data)` 得到空结果

paddlex 管道最稳的输入是 **RGB numpy 数组**：服务内统一用 PIL 解码后 `np.array(img)` 再 predict。

### 4. 不要给 pp-ocrv6 挂载覆盖 `/root/.paddlex` 的卷

PP-OCRv6 权重在**构建期**已预热烘焙进镜像（`/root/.paddlex/official_models`，约 177MB）。
挂载空卷会遮住权重并触发重新下载。

### 5. 离线构建能力

`pp-ocrv6/wheels/paddlepaddle-3.3.0-*.whl` 为离线轮子；若删除该文件，
Dockerfile 会回退在线安装 `paddlepaddle==3.3.0`。其余依赖走清华 pip 源。

## 六、运维

```powershell
docker compose logs -f pp-ocrv6           # 单服务日志
docker compose restart pp-ocrv6           # 重启单个服务
docker compose ps                         # 状态（healthy/unhealthy）
docker compose down                       # 回滚：停掉并移除容器（镜像仍在，可随时再 up）
```

监控要点：

- `/nginx-health` 免鉴权存活探针（供外部探活）；
- 各容器自带 `healthcheck`，`docker compose ps` 可见 `healthy/unhealthy`；
- 资源：`docker stats` 观察 CPU/内存（`scripts\status.ps1` 已封装）。

## 七、版本清单（写死，便于复现）

| 组件 | 版本 |
|---|---|
| paddlepaddle (CPU) | 3.3.0（`pp-ocrv6/wheels/` 离线轮子） |
| paddleocr | 3.7.0 |
| paddlex[ocr-core] | 3.7.2 |
| FastAPI / uvicorn | 0.115.6 / 0.34.0 |
| PP-OCRv6 模型 | `PP-OCRv6_medium_det` + `PP-OCRv6_medium_rec`（合计 34.5M） |
| Nginx | 1.27-alpine |

构建上下文：`pp-ocrv6` 以自己的目录为上下文（避免每次把 wheel 卷进上下文）。

## 八、扩展：要不要加 PaddleOCR-VL-1.6？

本地实测两条官方路径均不顺畅，故本包未纳入：

- **native 后端**：`paddleocr` 在多线程内调用会卡死（GPU 占用 8GB、利用率 0%、不返回）；
- **vllm-server 后端**：当前显卡驱动最高支持 CUDA 12.8，而 `vllm>=0.11` 拉 `torch>=2.13+cu130`，
  导致 `torch.cuda.is_available()` 为 `False`；`vllm==0.10.x` 虽可用，但与 `paddlepaddle-gpu`
  争夺 `nvidia-cudnn-cu12` 版本，同镜像内 pip 会互相卸载替换使构建崩溃（需拆两个镜像）。
- 官方离线镜像仅发布在百度 CCR，本机实测单层反复重试、几乎无进度，`docker.m.daocloud.io`
  明确提示「不在白名单」，Docker Hub 也无此镜像。

若确有文档解析需求，建议：升级显卡驱动至支持 CUDA 13.x 后，采用 vllm-server 双镜像方案，
单独评估后再接入。
