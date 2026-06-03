-- ============================================================
-- ai_agent_template 表
-- Agent 配置模板表
-- ============================================================
CREATE TABLE IF NOT EXISTS `ai_agent_template` (
    `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '编号',
    `name` VARCHAR(100) NOT NULL COMMENT '模板名称',
    `code` VARCHAR(100) NOT NULL COMMENT '模板编码',
    `description` VARCHAR(500) DEFAULT NULL COMMENT '模板描述',
    `agent_type` VARCHAR(50) DEFAULT NULL COMMENT 'Agent 类型',
    `status` INT NOT NULL DEFAULT 0 COMMENT '状态（0-启用，1-禁用）',
    `sort` INT DEFAULT 0 COMMENT '排序值',
    `tenant_id` BIGINT NOT NULL COMMENT '租户编号',
    `creator` VARCHAR(64) DEFAULT '' COMMENT '创建者',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updater` VARCHAR(64) DEFAULT '' COMMENT '更新者',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` BIT(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_code` (`code`, `tenant_id`),
    KEY `idx_agent_type` (`agent_type`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 配置模板表';