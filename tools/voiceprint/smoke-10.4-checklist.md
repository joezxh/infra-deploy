# SP-6 §10.4 九步冒烟清单（G0 通过后在集成环境执行）

> 纪律：本清单是**人工执行记录**，每步勾选须附证据（响应片段 / SQL 结果 / 日志 grep 输出）。
> 任何一步失败即停止后续步骤；不得带病推进，更不得用样例数据冒充真机证据。

| 步骤 | 动作 | 通过判据 | 证据位置 | 结果 |
|---|---|---|---|---|
| 1 | G0-a/b/c/d 四项取证 | `g0-probe.ps1` 报告四项全「通过」（-AfterRebuild 须在容器重建后重跑） | `g0-report-*.md` | ☐ |
| 2 | 执行 V3.58 → V3.59 → V3.60 | 菜单 9508–9511 防呆通过、超管授权生效 | psql：`SELECT id,name FROM uaa_menu WHERE id BETWEEN 9508 AND 9511` | ☐ |
| 3 | `voiceprint.enabled=false` 调 `/capability` | `available=false` 且 `reason` 非空（零探活外呼） | `GET /admin-api/ai/voiceprint/capability` 响应 | ☐ |
| 4 | 写入有效同意 → 3 段注册 | 模板表仅 1 行、容器/服务端无音频文件 | `SELECT count(*) FROM ai_voiceprint_template WHERE deleted=FALSE` | ☐ |
| 5 | 签发口令，本人实时朗读 | `VP_MATCHED` 且 `durationMs ≤2000` | 核验响应 + SQL-7 | ☐ |
| 6 | 关 `voiceprint.enabled` 重灌同段 | **零新增核验记录、零外呼**（用例㉕回归） | 前后 `count(*) FROM ai_voiceprint_verify_record` 相同 | ☐ |
| 7 | 播注册音频重放 | `CHALLENGE_FAILED` 且无 embedding 访问日志 | 137 网关访问日志 grep | ☐ |
| 8 | 撤回同意 | 模板表零行、`GET /template/status` → `hasBase=false` | psql + 响应 | ☐ |
| 9 | 三项巡检 | 容器音频文件数 0；日志音频/base64 命中 0；非结论态 `confidence IS NOT NULL` 行数 0 | `docker exec` find + 日志 grep + `inspection.sql` SQL-1 | ☐ |

## 快捷命令

```powershell
# 步骤 1
./tools/voiceprint/g0-probe.ps1 -ApiKey '<real-key>' -AfterRebuild

# 步骤 2（已在本工作区对 192.168.100.80 执行过，重放应幂等 NOTICE）
docker run --rm -v "${PWD}/mediation-ai/docs/sql:/sql:ro" -e PGPASSWORD='<pwd>' postgres:15-alpine `
  psql -h <host> -U postgres -d mediation_db -v ON_ERROR_STOP=1 `
  -f /sql/V3.58__voiceprint_tables.sql -f /sql/V3.59__voiceprint_consent_and_menu.sql -f /sql/V3.60__verify_record_voiceprint.sql

# 步骤 3 / 5 / 8：经网关或直连 8086，带 Bearer token 与 tenant-id 头

# 步骤 9 巡检
docker run --rm -v "${PWD}/mediation-deploy/tools/voiceprint:/sql:ro" -e PGPASSWORD='<pwd>' postgres:15-alpine `
  psql -h <host> -U postgres -d mediation_db -f /sql/inspection.sql
```

全部通过后：由管理员按 §10.5 复核指标，**人工**置位 `VOICEPRINT_POC_PASSED`（G3 留档齐备为前置），
脚本与开发会话不得代置。
