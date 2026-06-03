-- ============================================================
-- ai_agent_config 表
-- Agent 配置详情表
-- ============================================================
CREATE TABLE IF NOT EXISTS `ai_agent_config` (
    `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '编号',
    `agent_id` BIGINT NOT NULL COMMENT '关联 Agent ID',
    `template_id` BIGINT DEFAULT NULL COMMENT '关联模板 ID',
    `config_group` VARCHAR(20) NOT NULL COMMENT '配置分组（FEED_FORWARD/EXECUTION/CONSTRAINT）',
    `config_key` VARCHAR(50) NOT NULL COMMENT '配置项键名',
    `config_value` VARCHAR(1000) DEFAULT NULL COMMENT '配置项值',
    `override_flag` BIT(1) NOT NULL DEFAULT b'0' COMMENT '是否覆盖模板值',
    `tenant_id` BIGINT NOT NULL COMMENT '租户编号',
    `creator` VARCHAR(64) DEFAULT '' COMMENT '创建者',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updater` VARCHAR(64) DEFAULT '' COMMENT '更新者',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` BIT(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_agent_id` (`agent_id`),
    KEY `idx_template_id` (`template_id`),
    KEY `idx_config_group` (`config_group`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 配置详情表';