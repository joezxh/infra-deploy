# SP-3 门禁置位留档

- 时间：2026-11-07 00:17:07
- 动作：enable（由 enable-face-poc.ps1 执行）
- 用户放行声明：2026-11-06「不考虑门禁，当前真人测试的门禁都通过」；2026-11-07「继续」
- 相似度阈值：**0.55**
- 阈值来源：D:\work\mediation_platform\mediation-deploy\compreface\samples\calibration\calibration-report-20261105-233120.md
- **阈值局限**：来源报告的样本量低于 G2 门槛（正/负各 ≥20 组），该数值仅供联调，正式生产须以真人 G2 报告数值替换

## 开关变更

| 变量 | 文件 | 置位后 |
|---|---|---|
| MEETING_FACE_POC_PASSED | compreface/.env | true |
| MEETING_G3_VIDEO | ai-server/.env | true |
| MEETING_FACE_ENABLED | ai-server/.env | true |
| MEETING_FACE_SIMILARITY_THRESHOLD | ai-server/.env | 0.55 |

## 留档清点（如实登记，不伪造）

- G0 双人真机日志报告：本工作区未见（用户声明真人测试已通过）
- G1 20 段真实帧召回报告：本工作区未见（用户声明真人测试已通过）
- 真人 G2 FAR/FRR 报告：本工作区未见；现有报告基于官方样例，样本量不足
- G3 四项留档：未提供（-G3EvidenceDir 未指向有效目录）
- V5/V8 巡检：见 README §7 与 verify.ps1 的 -CheckLatency / -CheckResidual 段

## 回滚

```powershell
.\scripts\enable-face-poc.ps1 -Action rollback
```

> 置位不解除红线：只做 1:1、禁 1:N、不建底库、帧不落盘、不改实名状态、
> FACE_MISMATCH 措辞固定「疑似不一致，请现场确认」；阈值未标定时仍恒 FACE_INSUFFICIENT。
