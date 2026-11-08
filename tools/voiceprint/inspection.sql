-- =====================================================================
-- SP-6 §10.5 声纹巡检 SQL（设计文档 2026-11-04-voiceprint-verify-design.md 原样落地）
-- 用法：psql -h <host> -U postgres -d mediation_db -f inspection.sql
--       带参项（SQL-3/SQL-5）默认给出可直接跑的占位注释，按需替换后单独执行。
-- 验收口径：SQL-1/2/3 恒 0；SQL-4 零行；SQL-5 恒 0；SQL-6 两列恒 0；
--           SQL-7 文件验证 P95 ≤2000ms、注册 ≤3000ms、会中 ≤5000ms。
-- 纪律：巡检只读，不改任何数据；破零即按 §10.6 回退影子模式。
-- =====================================================================

-- SQL-1 非结论态不得带校准分值（期望 0）
SELECT count(*) AS non_conclusive_with_confidence
  FROM ai_voiceprint_verify_record
 WHERE deleted = FALSE AND verdict NOT IN ('VP_MATCHED','VP_MISMATCH')
   AND (confidence IS NOT NULL OR confidence_band IS NOT NULL);

-- SQL-2 疑似回放不得同时产出通过结论（期望 0）
SELECT count(*) AS spoof_but_matched
  FROM ai_voiceprint_verify_record
 WHERE deleted = FALSE AND spoof_signal IS NOT NULL AND verdict = 'VP_MATCHED';

-- SQL-3 停用期间假结论（期望 0；把时段换成实际关闭窗口）
-- SELECT count(*) AS verdict_during_off
--   FROM ai_voiceprint_verify_record
--  WHERE deleted = FALSE
--    AND create_time BETWEEN '2026-01-01 00:00:00' AND '2026-01-01 01:00:00'
--    AND verdict IN ('VP_MATCHED','VP_MISMATCH');

-- SQL-4 模板唯一性兜底（期望零行：每个 (tenant_id, party_id) ≤1 行）
SELECT tenant_id, party_id, count(*) AS dup_rows
  FROM ai_voiceprint_template
 WHERE deleted = FALSE
 GROUP BY tenant_id, party_id HAVING count(*) > 1;

-- SQL-5 撤回/失效后的向量残留（期望 0；按撤回清单逐 party 查）
-- SELECT count(*) AS revoked_leftover
--   FROM ai_voiceprint_template
--  WHERE deleted = FALSE AND party_id = 0 AND tenant_id = 1;

-- SQL-6 过期口令与过期模板残留（两列期望均 0）
SELECT (SELECT count(*) FROM ai_voiceprint_challenge
         WHERE expires_at < CURRENT_TIMESTAMP AND used_at IS NULL) AS stale_challenges,
       (SELECT count(*) FROM ai_voiceprint_template
         WHERE expires_at < CURRENT_TIMESTAMP AND deleted = FALSE) AS stale_templates;

-- SQL-7 端到端时延 P95（结论态口径；阈值：FILE ≤2000ms / REALTIME 按注册 ≤3000ms 会中 ≤5000ms）
SELECT input_form,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95_ms,
       count(*) AS samples
  FROM ai_voiceprint_verify_record
 WHERE deleted = FALSE AND verdict IN ('VP_MATCHED','VP_MISMATCH')
 GROUP BY input_form;

-- 附加：最近 24h 结论分布（巡检参考，非硬指标）
SELECT verdict, count(*) AS cnt
  FROM ai_voiceprint_verify_record
 WHERE deleted = FALSE AND create_time > CURRENT_TIMESTAMP - INTERVAL '24 hours'
 GROUP BY verdict ORDER BY cnt DESC;
