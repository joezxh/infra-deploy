-- ============================================================
-- ai_agent 表新增字段
-- 添加 template_id 和 agent_role 字段，支持 Agent 配置方案
-- ============================================================

ALTER TABLE `ai_agent` 
ADD COLUMN `template_id` BIGINT DEFAULT NULL COMMENT '关联配置模板 ID' AFTER `mcp_ids`,
ADD COLUMN `agent_role` VARCHAR(50) DEFAULT NULL COMMENT 'Harness 角色标识' AFTER `template_id`;

-- 添加索引
ALTER TABLE `ai_agent` ADD INDEX `idx_template_id` (`template_id`);