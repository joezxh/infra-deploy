# SP-6 声纹 G0 取证工具包

对应设计：`mediation-docs/superpowers/specs/2026-11-04-voiceprint-verify-design.md` §0.2 / §8，实施计划 Task 12。

本目录只做**取证与留档**，不实现 137 网关端点、不改平台配置、不置位 `VOICEPRINT_POC_PASSED`、不产出任何身份结论。

## 工具

| 文件 | 用途 |
|---|---|
| `g0-probe.ps1` | 生成 3s / 16k / mono / 16-bit WAV（临时文件用完即删），依次探测 G0-a 端点可达、capability、G0-d 无凭证拒绝、G0-c 8 路并发下 ASR 时延劣化；带 `-AfterRebuild` 复测 G0-b 端点持久化。输出 `g0-report-<时间戳>.md`。 |
| `g0-report-*.md` | 现场取证报告（由脚本生成，须人工归档到实施前置证据目录）。本会话已产出 `g0-report-20261106-035456.md`：G0-a 404、capability 404、G0 整体未通过。 |

```powershell
# 首次取证
./g0-probe.ps1 -ApiKey '<真实凭证>' -BaseUrl 'http://192.168.1.137:8765'

# 重建 137 容器后复测 G0-b
./g0-probe.ps1 -ApiKey '<真实凭证>' -AfterRebuild
```

判据：G0-a 返回 200 且 `embedding` 长度 == `dim` == `voice.gateway.embedding-dim`、含 `model` 与 `quality`；G0-b 重建后仍 200；G0-c 字幕满载并发 8 路时 ASR P95 劣化 ≤20% 且零 5xx；G0-d 裸请求返回 401/403。任一未通过即为 G0 整体未通过。

## 2026-11-06 实测登记（本会话取证，非推测）

| 探测 | 结果 | 结论 |
|---|---|---|
| `GET http://192.168.1.137:8765/v1/pool` | HTTP 200，`{"size":1,"in_use":0,"units":[...]}` | 网关主机可达，ASR/TTS 池在线 |
| `GET /v1/audio/embeddings/capability` | HTTP **404** | 能力探活端点不存在 |
| `POST /v1/audio/embeddings`（multipart `model`/`purpose`，无 file 的轻量探测） | HTTP **404** | **G0-a 未通过**：端点未投出 |
| `POST /v1/audio/transcriptions`（同样无 file 的对照探测） | HTTP 500 | 既有 ASR 端点存在（缺 file 的业务错误），与 404 形成对照 |
| G0-d 裸请求拒绝 | **无法取证**（端点不存在） | 不得记为通过 |
| G0-b 容器重建后仍 200 / G0-c 8 路并发 | **不适用**（前置 G0-a 未通过） | 不得记为通过 |

因此：`VOICEPRINT_POC_PASSED=false`、`voiceprint.g0-passed=false`、`voiceprint.enabled=false`；G1/G2/G3 亦未通过。
业务代码按 2026-11-06 用户指令以 **fail-closed 双开关**交付（默认零外呼），不是门禁通过的证据，也不得在生产启用。

## 门禁与遗留

- G0 四项证据齐备后，还须 G1（DET/EER 标定报告，FAR ≤1% / FRR ≤5%）、G2（≥2 场影子模式人检一致率 ≥70%）、G3（单独同意文本、模型权重商用许可、`embedding` 列静态加密工单、留存删除流程）依次通过。
- T3（平台持有声纹模板向量）与 T5（扩展 137、逆转「不调 137」）按 D6 需用户书面确认；本次用户指令按「风险接受与放行编码」登记，**不视为**取证材料已完成。
- 137 端点实现、模型权重分发、端点持久化与鉴权属跨仓任务（§11.1 移交表），不在本工作区交付。
