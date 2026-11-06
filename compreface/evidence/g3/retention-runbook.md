# G3-3 管理库留存期 / 备份加密 / 撤回删除流程

> 现状事实：本部署**没有内置 Postgres 命名卷**，复用外部实例
> `192.168.100.80:5432/compreface`（账号 `postgres`，凭据在 `compreface/.env`，已忽略入库）。
> 因此「删除卷」不适用，删除对象是外部库中的管理数据与残留 subject 数据。

## 1. 数据面

| 数据 | 位置 | 说明 |
|---|---|---|
| 管理员账号、应用/服务、服务 key、调用统计 | 外部 PG `compreface`（liquibase 建表） | 平台管理数据，不含当事人生物特征 |
| 当事人人脸图像 / 向量 | **不存在** | 只走 1:1 verification，不建 subject；nginx 路径白名单拦截 recognition |
| 会中帧 / 证件照字节 | 仅请求内存 | 不落盘、不入库、不进日志 |
| 核验结论 | 当前收敛版**不落库** | 见 `2026-11-06-face-vision-analysis-effective-spec.md` §7 |

## 2. 留存期与备份（待运维确认填值）

| 项 | 建议 | 定版值 | 依据 |
|---|---|---|---|
| 管理数据与调用统计留存 | ≤180 天（与 `party.verify.retention-days` 对齐） | 待填 | 运维工单 |
| 备份频率 / 介质 | 每日 `pg_dump`，加密后放受限目录 | 待填 | 运维工单 |
| 备份加密 | AES-256 或受控磁盘加密，密钥放 `mediation-deploy/secrets/`（已忽略入库） | 待填 | 运维工单 |
| 备份保留期 | 与数据留存期一致，到期物理删除 | 待填 | 运维工单 |
| 备份恢复演练 | 每半年一次并留记录 | 待填 | 运维工单 |

## 3. 撤回同意后的删除流程

1. 接收到当事人撤回 → 登记工单（时间、操作人、原因、party 标识、审批人）。
2. 平台侧：无底库、无向量、无核验记录可删；确认 `ai_party_consent.revoked_at` 已置位，
   服务端 `FACE_COMPARE` 硬门立即拒绝后续外呼。
3. 服务侧：轮换/吊销该应用的服务 key；若曾误启用 recognition，删除对应 subject 与样例数据
   （须由 DBA 执行并留 SQL 与截图）。
4. 巡检：`.\scripts\verify.ps1 -CheckResidual` 断言 subject/embedding 相关表行数为 0，
   报告写入 `evidence/v8-residual.md`。
5. 台账登记：`| 时间 | 工单号 | 操作人 | 删除对象 | 结果 | 复核人 |`。

```sql
-- 巡检用（只读；具体表名以 information_schema 实查为准）
SELECT table_name FROM information_schema.tables
WHERE table_schema='public'
  AND (table_name ILIKE '%subject%' OR table_name ILIKE '%embedding%' OR table_name ILIKE '%face%');
```

## 4. 待填登记

- 运维工单号：____________　留存期定版：____________　备份加密方式：____________
- 撤回删除演练完成：☐　审批人：____________　日期：____________

> 未填工单号前，G3 第 3 项不算留档齐备。
