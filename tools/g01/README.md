# SP-3 真机取证工具包（G0 / G1 / G2）

本目录把设计文档 §7.10 登记的 R1–R3 三项**必须真人真机完成**的门禁任务，做成「采集 → 评测 → 出报告」的
可执行链路。现场人员按本 README 逐条执行即可产出可归档的结论，**无需改任何业务代码**。

> 纪律：本工具包只负责**采集与客观评测**。门禁是否通过由人工评审报告决定；
> 严禁用样例图、合成帧、脚本生成帧替代真机证据来置位门禁。

## 目录

| 文件 | 用途 |
|---|---|
| `collect.html` | 真机采集页：G1 会中帧（自动连拍）+ G2 标定样本（手动连拍），全部本地落盘 |
| `g0-check-log.ps1` | 解析 worker 的 `[track-observe]` 日志 → G0 判定（≥2 个参与方各发布视频轨） |
| `g1-eval-frames.ps1` | 真实帧 → CompreFace detect → 召回率/误报率报告（对照判据） |

---

## R1 · G0 双人真机日志实证

1. 现场两人用**真实摄像头**入会同一房间（确认媒体服务上的 worker 在运行）。
2. 导出 worker 日志（worker 所在机器执行）：

```bash
docker logs --since 30m <worker-container> > worker.log
# 或 journalctl / k8s: kubectl logs <pod> --since=30m > worker.log
```

3. 判定：

```powershell
.\g0-check-log.ps1 -LogPath .\worker.log -OutFile .\g0-report.md
```

**通过条件**：同一 room 内 ≥2 个不同 `identity` 各有 ≥1 条 `kind=KIND_VIDEO`。
不通过时脚本退出码为 3，且报告会写明「不得据此置位门禁」。

判据来源：worker 观测日志（`mediation-ai/deploy/livekit-worker/worker.py:123-126`）只打印
`room / identity / kind / sid`，**不含任何帧内容**，符合隐私红线。

---

## R2 · G1 真实会中帧召回率/误报率

### 采集

1. 用 Chrome/Edge 通过 `http://localhost` 或 https 打开采集页（File System Access API 需要安全上下文）：

```powershell
cd tools/g01
python -m http.server 8899      # 然后浏览器打开 http://localhost:8899/collect.html
```

2. 「选择目录…」选一个**本地空目录**（例如 `D:\evidence\g1-2026-11-xx`）。
3. 填「被采集者身份」（如 `participant-a`），点「开启摄像头」。
4. 点「开始每 3 秒连拍」，在提示框里输入 `期望 备注`：
   - `1 单人正面` / `1 侧脸` / `1 逆光` / `1 弱光` / `1 戴口罩` → 应检出人脸
   - `0 无人` → 不应检出人脸（**误报检验样本，务必采集**）
   - `2 两人同框` → 应检出 2 张脸
5. 累计 **≥20 段**真实会中帧，覆盖上述场景；两人分别采集（不同 identity 目录）。

落盘结构：

```
<根>/g1-frames/
├── labels.csv            # identity,file,ts,expect,note
├── participant-a/f_0001.jpg ...
└── participant-b/f_0001.jpg ...
```

### 评测

```powershell
.\g1-eval-frames.ps1 -FramesDir D:\evidence\g1-2026-11-xx\g1-frames `
    -LabelsPath D:\evidence\g1-2026-11-xx\g1-frames\labels.csv `
    -OutFile D:\evidence\g1-2026-11-xx\g1-report.md
```

**通过条件**：有效帧 ≥20 **且** 召回率 ≥85% **且** 误报率 ≤5%
（召回 = 应有人脸且检出 / 应有人脸总数；误报 = 应无人脸却检出 / 应无人脸总数）。

---

## R3 · G2 真实样本标定

### 采集

用 `collect.html` 切到「G2 标定样本采集」模式：

- 同一身份（同一 `identity`）更换光照 / 朝向 / 表情 / 距离，各拍 ≥10 张；
- 至少 2 名参与者；
- 落盘结构：`calibration/positive/<person_id>/s_0001.jpg`；
- **不同人**的样本另放 `calibration/negative/<person_id>/`。

> **分组必须人工确认**：文件名后缀不代表同一人（实测官方样例 `005_A` 与 `001_A` 仅 0.21、
> `007_B` 与 `008_B` 仅 0.083，均为不同人）。

### 标定

```powershell
# 从本目录（mediation-deploy/tools/g01）出发；<Evidence> 为现场采集目录
..\compreface\scripts\calibrate-threshold.ps1 `
    -CalibDir <Evidence>\calibration `
    -ApiBase 'http://192.168.110.169:8050/face/api/v1/verification/verify'
```

工具输出**原图域 + 帧域**两套分布（阈值必须按帧域，原图域会系统性高估）、
FAR/FRR 扫描、Youden J 最优与样本量门槛判定，并写出 Markdown 报告。

**通过条件**：正/负有效配对各 ≥20 组，且存在同时满足 FAR ≤0.001 与 FRR ≤0.05 的阈值。
达标后由管理员**显式**设置 `MEETING_FACE_SIMILARITY_THRESHOLD`（脚本不代劳），并复跑 G1/G2 报告。

---

## 隐私与留存

- 采集页**纯本地落盘、不上传**；帧不进入任何服务、不入数据库、不进日志。
- 取证目录属临时证据：报告归档后按留存策略处置原始帧（建议评审通过后删除原图，仅保留报告与脱敏截图）。
- 涉及当事人肖像的样本须有明确授权；采集前告知用途与保留期限。

## 常见问题

| 症状 | 处置 |
|---|---|
| 采集页提示不支持目录选择 | 用 Chrome/Edge，且通过 `http://localhost` 或 https 打开（file:// 不可用） |
| 摄像头打不开 | 非安全上下文或未授权；用 localhost + 允许摄像头权限 |
| G0 报「未发现 track-observe 行」 | worker 未运行 / 未连上 LiveKit / 无人入会开摄像头；先确认 worker 日志有 `[worker]` 启动行 |
| G1 全部判为跳过 | `labels.csv` 的 `file` 列与实际文件名不一致，或 `expect` 列缺失（需 5 列） |
| G1 召回为 0 | 检查帧是否真的有人脸；逆光/弱光/侧脸是主要漏检场景，需补采 |