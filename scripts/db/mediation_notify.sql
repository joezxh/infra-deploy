-- ============================================================
-- 矛盾纠纷调解平台 - 通知服务数据库初始化
-- 数据库名: mediation_notify
-- 服务端口: 8089
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_notify`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_notify`;

-- ============================================================
-- 第一部分: 通知记录表
-- ============================================================
DROP TABLE IF EXISTS `notify_record`;
CREATE TABLE `notify_record` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `notify_type` VARCHAR(20) NOT NULL COMMENT '通知类型: SMS-短信 EMAIL-邮件 IN_APP-站内信 PUSH-APP-APP推送 WECHAT-微信',
    `recipient_id` VARCHAR(32) DEFAULT NULL COMMENT '接收人ID',
    `recipient_name` VARCHAR(50) DEFAULT NULL COMMENT '接收人姓名',
    `recipient_phone` VARCHAR(20) DEFAULT NULL COMMENT '接收手机号',
    `recipient_email` VARCHAR(100) DEFAULT NULL COMMENT '接收邮箱',
    `recipient_openid` VARCHAR(100) DEFAULT NULL COMMENT '微信OpenID',
    `title` VARCHAR(200) DEFAULT NULL COMMENT '标题',
    `content` TEXT DEFAULT NULL COMMENT '通知内容',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '关联案件ID',
    `case_no` VARCHAR(50) DEFAULT NULL COMMENT '案件编号',
    `template_code` VARCHAR(50) DEFAULT NULL COMMENT '短信模板CODE',
    `template_params` TEXT DEFAULT NULL COMMENT '模板参数JSON',
    `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '状态: PENDING-待发送 SENDING-发送中 SUCCESS-成功 FAILED-失败 CANCELLED-取消',
    `send_time` DATETIME DEFAULT NULL COMMENT '实际发送时间',
    `fail_reason` VARCHAR(500) DEFAULT NULL COMMENT '失败原因',
    `retry_count` INT(3) NOT NULL DEFAULT 0 COMMENT '重试次数',
    `max_retry` INT(3) NOT NULL DEFAULT 3 COMMENT '最大重试次数',
    `third_party_msg_id` VARCHAR(100) DEFAULT NULL COMMENT '第三方消息ID（阿里云/腾讯云）',
    `fee` DECIMAL(10,4) DEFAULT NULL COMMENT '短信费用（元）',
    `priority` TINYINT(2) NOT NULL DEFAULT 5 COMMENT '优先级 1-10，数字越小优先级越高',
    `schedule_time` DATETIME DEFAULT NULL COMMENT '定时发送时间',
    `read_status` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '阅读状态: 0-未读 1-已读（仅站内信）',
    `read_time` DATETIME DEFAULT NULL COMMENT '阅读时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_recipient` (`recipient_id`),
    KEY `idx_type` (`notify_type`),
    KEY `idx_status` (`status`),
    KEY `idx_case` (`case_id`),
    KEY `idx_schedule_time` (`schedule_time`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_priority_status` (`priority`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='通知记录表';

-- ============================================================
-- 第二部分: 通知模板表
-- ============================================================
DROP TABLE IF EXISTS `notify_template`;
CREATE TABLE `notify_template` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `template_code` VARCHAR(50) NOT NULL COMMENT '模板编码',
    `template_name` VARCHAR(100) NOT NULL COMMENT '模板名称',
    `notify_type` VARCHAR(20) NOT NULL COMMENT '适用渠道: SMS-短信 EMAIL-邮件 IN_APP-站内信',
    `content_template` TEXT NOT NULL COMMENT '内容模板，支持变量占位符 ${var}',
    `variables` VARCHAR(500) DEFAULT NULL COMMENT '变量列表，JSON数组',
    `scene` VARCHAR(50) DEFAULT NULL COMMENT '使用场景: CASE_ASSIGN-案件分配 CASE_UPDATE-案件状态变更 MEDIATION_INVITE-调解邀请 PROTOCOL_SIGN-协议签署 NOTICE_PUBLISH-公告发布',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    `remark` VARCHAR(200) DEFAULT NULL COMMENT '备注',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_template_code` (`template_code`),
    KEY `idx_type` (`notify_type`),
    KEY `idx_scene` (`scene`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='通知模板表';

-- ============================================================
-- 第三部分: 通知渠道配置表
-- ============================================================
DROP TABLE IF EXISTS `notify_channel`;
CREATE TABLE `notify_channel` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `channel_type` VARCHAR(20) NOT NULL COMMENT '渠道类型: SMS_ALIYUN-阿里云短信 SMS_TENCENT-腾讯云短信 EMAIL_SMTP-SMTP邮件 PUSH_JIGUANG-极光推送 WECHAT_OFFICIAL-微信服务号',
    `channel_name` VARCHAR(100) NOT NULL COMMENT '渠道名称',
    `is_enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用: 0-禁用 1-启用',
    `config_data` JSON DEFAULT NULL COMMENT '配置参数JSON（密钥、签名等敏感）',
    `daily_limit` INT(11) DEFAULT NULL COMMENT '日发送上限',
    `monthly_limit` INT(11) DEFAULT NULL COMMENT '月发送上限',
    `daily_used` INT(11) NOT NULL DEFAULT 0 COMMENT '当日已用',
    `monthly_used` INT(11) NOT NULL DEFAULT 0 COMMENT '当月已用',
    `cost_per_unit` DECIMAL(10,4) DEFAULT NULL COMMENT '单位成本（元）',
    `remark` VARCHAR(200) DEFAULT NULL COMMENT '备注',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_type` (`channel_type`),
    KEY `idx_enabled` (`is_enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='通知渠道配置表';

-- ============================================================
-- 第四部分: 测试数据
-- ============================================================

-- 通知模板
INSERT INTO `notify_template` (`id`, `template_code`, `template_name`, `notify_type`, `content_template`, `variables`, `scene`, `status`) VALUES
('NT0010000000000000001', 'CASE_ASSIGN_SMS', '案件分配通知', 'SMS', '【调解平台】您好，您有一件新案件等待处理。案件编号：${caseNo}，纠纷类型：${disputeType}。请及时登录平台处理。', '["caseNo","disputeType"]', 'CASE_ASSIGN', 1),
('NT0010000000000000002', 'CASE_ASSIGN_MSG', '案件分配站内信', 'IN_APP', '您有一件新案件等待处理。案件编号：${caseNo}，纠纷类型：${disputeType}，申请人：${applicantName}。请及时处理。', '["caseNo","disputeType","applicantName"]', 'CASE_ASSIGN', 1),
('NT0010000000000000003', 'MEDIATION_INVITE_SMS', '调解邀请通知', 'SMS', '【调解平台】调解邀请：您被邀请参加案件编号${caseNo}的调解，时间：${scheduleTime}，地点：${address}。如有疑问请联系调解员。', '["caseNo","scheduleTime","address"]', 'MEDIATION_INVITE', 1),
('NT0010000000000000004', 'PROTOCOL_SIGN_MSG', '协议签署通知', 'IN_APP', '调解协议已生成，请尽快签署。案件编号：${caseNo}，协议内容：${protocolSummary}。', '["caseNo","protocolSummary"]', 'PROTOCOL_SIGN', 1),
('NT0010000000000000005', 'SYSTEM_NOTICE', '系统公告', 'IN_APP', '${content}', '["content"]', NULL, 1);

-- 通知渠道
INSERT INTO `notify_channel` (`id`, `channel_type`, `channel_name`, `is_enabled`, `daily_limit`, `monthly_limit`, `cost_per_unit`) VALUES
('NC0010000000000000001', 'SMS_ALIYUN', '阿里云短信', 1, 10000, 300000, 0.045),
('NC0010000000000000002', 'EMAIL_SMTP', 'SMTP邮件', 1, 5000, 150000, 0.00),
('NC0010000000000000003', 'PUSH_JIGUANG', '极光推送', 0, 50000, 1500000, 0.00);

-- 通知记录
INSERT INTO `notify_record` (`id`, `notify_type`, `recipient_id`, `recipient_name`, `recipient_phone`, `title`, `content`, `case_id`, `status`, `send_time`) VALUES
('NR0010000000000000001', 'SMS', '4000000000000000001', '张三调解员', '13800138001', '新案件分配通知', '您有一件新案件等待处理。案件编号：CASE001，纠纷类型：合同纠纷。', 'CASE0010000000000001', 'SUCCESS', NOW()),
('NR0010000000000000002', 'IN_APP', '4000000000000000001', '张三调解员', NULL, '调解协议签署通知', '调解协议已生成，请尽快签署。案件编号：CASE001。', 'CASE0010000000000001', 'SUCCESS', NOW());

-- ============================================================
-- 完成
-- ============================================================
