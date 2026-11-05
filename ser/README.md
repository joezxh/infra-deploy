# SP-4 声学情感（SER）部署件

> **状态：骨架，未实测。** 本目录只提供编排与验证脚本，不含模型权重、未运行过容器、未与真实会议房间联调。
> `MEETING_SER_ENABLED` 与 `MEETING_SER_POC_PASSED` 默认均为 `false`；U1–U5 全部回写并人工确认前，
> 不允许把 `MEETING_G3_SER` 置位，也不允许 worker 打开 `ser` 快照开关。

## 目录

| 文件 | 作用 |
|---|---|
| `docker-compose.yml` | `ser-core`（模型 core，内部 8021，不挂音频卷）+ `ser-nginx`（对外 8020，`X-API-Key`） |
| `nginx/default.conf.template` | 只暴露 `/health` 与 `/v1/ser`；无 key 返回 401 |
| `.env.example` | 无明文默认值的环境变量样例 |
| `scripts/{deploy,status,stop,verify}.ps1` | 部署 / 诊断 / 停止 / 契约验证 |

## 契约（待实测核实）

- `POST /v1/ser` → `{emotion, confidence, model, labels_supported}`；`emotion` 必须是
  `calm/anxious/agitated/anger/threat` 之一；未知标签由 `ser_provider.normalize_label` 抛错，不降级为 `calm`。
- 3s 静音段必须返回 409/502，**不得**返回 200 `calm`。
- `labels_supported` 必须与映射表逐项一致，否则 `1_040_064_004`。
- 只保留 `X-API-Key` 鉴权；端口 `8020/8021`，与 OCR `8011`、CompreFace `8050/8051` 不冲突。

## U1–U5 PoC 取证模板（实施时回填实测值，不得预填）

| 项 | 判据 | 实测结果 |
|---|---|---|
| U1 | 3 段录音各 20 次，P95 ≤ 1500ms | 待测 |
| U2 | CPU 不饿死同机 OCR | 待测 |
| U3 | 影子 2 场真人检一致率 ≥ 70% | 待测 |
| U4 | 关闭服务后 `available=false` 且无新增 `ser` 告警行 | 待测 |
| U5 | 3s 静音返回 409/502；`labels_supported` 与映射表一致 | 待测 |

## 隐私与边界

- 音频、频谱、中间向量一律不落盘、不挂卷；请求体只在内存中转 WAV。
- 声学证据**永不单独构成 danger**；结论文案统一「疑似…请人工确认」，不作情绪定性。
- 服务端 `ser` 开关为唯一权威；Java 侧第二次守卫在开关关闭时强制把 `ser_*` 三列写 `NULL`。
