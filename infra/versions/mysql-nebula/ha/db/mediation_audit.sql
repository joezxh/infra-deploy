-- ============================================================
-- 矛盾纠纷调解平台 - 审计服务数据库初始化
-- 数据库名: mediation_audit
-- 服务端口: 8088
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 说明: 操作日志表，数据量大建议定期归档或分区表
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_audit`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_audit`;

-- ============================================================
-- 第一部分: 审计日志表
-- ============================================================
DROP TABLE IF EXISTS `audit_log`;
CREATE TABLE `audit_log` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `user_id` VARCHAR(32) DEFAULT NULL COMMENT '操作用户ID',
    `user_name` VARCHAR(50) DEFAULT NULL COMMENT '操作用户姓名',
    `user_role` VARCHAR(20) DEFAULT NULL COMMENT '用户角色',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '机构ID',
    `org_name` VARCHAR(100) DEFAULT NULL COMMENT '机构名称',
    `module` VARCHAR(50) DEFAULT NULL COMMENT '模块: USER-用户 CASE-案件 MEDIATION-调解 ORG-机构 DEVICE-设备',
    `action` VARCHAR(50) NOT NULL COMMENT '操作类型: CREATE-创建 UPDATE-更新 DELETE-删除 LOGIN-登录 LOGOUT-登出 SUBMIT-提交 APPROVE-审核 REJECT-驳回 SIGN-签署',
    `method` VARCHAR(200) DEFAULT NULL COMMENT '请求方法名',
    `request_uri` VARCHAR(500) DEFAULT NULL COMMENT '请求URI',
    `request_method` VARCHAR(10) DEFAULT NULL COMMENT 'HTTP方法: GET POST PUT DELETE',
    `request_params` TEXT DEFAULT NULL COMMENT '请求参数JSON',
    `request_body` TEXT DEFAULT NULL COMMENT '请求体JSON（截断至4KB）',
    `response_body` TEXT DEFAULT NULL COMMENT '响应体（截断至4KB）',
    `ip_address` VARCHAR(50) DEFAULT NULL COMMENT '客户端IP',
    `user_agent` VARCHAR(500) DEFAULT NULL COMMENT 'User-Agent',
    `device_type` VARCHAR(20) DEFAULT NULL COMMENT '设备类型: WEB-网页 APP-IOS APP-ANDROID H5',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '关联案件ID',
    `target_type` VARCHAR(50) DEFAULT NULL COMMENT '操作对象类型',
    `target_id` VARCHAR(32) DEFAULT NULL COMMENT '操作对象ID',
    `description` VARCHAR(500) DEFAULT NULL COMMENT '操作描述',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-失败 1-成功',
    `error_message` VARCHAR(500) DEFAULT NULL COMMENT '错误信息',
    `duration_ms` INT(11) DEFAULT NULL COMMENT '响应耗时毫秒',
    `trace_id` VARCHAR(64) DEFAULT NULL COMMENT '链路追踪ID',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_user` (`user_id`),
    KEY `idx_module` (`module`),
    KEY `idx_action` (`action`),
    KEY `idx_case` (`case_id`),
    KEY `idx_org` (`org_id`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_target` (`target_type`, `target_id`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='审计日志表';

-- ============================================================
-- 第二部分: 操作类型字典（可选，用于统计分析）
-- ============================================================
DROP TABLE IF EXISTS `audit_action_dict`;
CREATE TABLE `audit_action_dict` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `module` VARCHAR(50) NOT NULL COMMENT '模块',
    `action` VARCHAR(50) NOT NULL COMMENT '操作类型',
    `action_name` VARCHAR(100) NOT NULL COMMENT '操作名称',
    `action_level` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '风险等级: 0-普通 1-敏感 2-高危',
    `log_request` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否记录请求体: 0-否 1-是',
    `log_response` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否记录响应体: 0-否 1-是',
    `remark` VARCHAR(200) DEFAULT NULL COMMENT '备注',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_module_action` (`module`, `action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='审计操作类型字典';

-- ============================================================
-- 第三部分: 测试数据
-- ============================================================

INSERT INTO `audit_action_dict` (`id`, `module`, `action`, `action_name`, `action_level`, `log_request`, `log_response`) VALUES
('AD0010000000000000001', 'USER', 'LOGIN', '用户登录', 0, 0, 0),
('AD0010000000000000002', 'USER', 'LOGOUT', '用户登出', 0, 0, 0),
('AD0010000000000000003', 'CASE', 'CREATE', '创建案件', 1, 1, 0),
('AD0010000000000000004', 'CASE', 'UPDATE', '修改案件', 1, 1, 0),
('AD0010000000000000005', 'CASE', 'ASSIGN', '分配案件', 1, 1, 0),
('AD0010000000000000006', 'MEDIATION', 'START', '开始调解', 1, 0, 0),
('AD0010000000000000007', 'MEDIATION', 'SIGN_PROTOCOL', '签署协议', 2, 0, 1),
('AD0010000000000000008', 'ORG', 'CREATE', '创建机构', 2, 1, 0),
('AD0010000000000000009', 'DEVICE', 'BIND', '绑定设备', 0, 0, 0),
('AD0010000000000000010', 'DEVICE', 'UNBIND', '解绑设备', 1, 0, 0);

INSERT INTO `audit_log` (`id`, `user_id`, `user_name`, `user_role`, `org_id`, `module`, `action`, `request_uri`, `request_method`, `status`, `duration_ms`) VALUES
('AL0010000000000000001', '1000000000000000002', '张三调解员', 'MEDIATOR', '2000000000000000001', 'CASE', 'ASSIGN', '/case/assign', 'POST', 1, 85),
('AL0010000000000000002', '1000000000000000003', '李四', 'INDIVIDUAL', NULL, 'CASE', 'CREATE', '/case/register', 'POST', 1, 230),
('AL0010000000000000003', '1000000000000000001', '系统管理员', 'ADMIN', '2000000000000000001', 'USER', 'LOGIN', '/auth/login', 'POST', 1, 120),
('AL0010000000000000004', '4000000000000000001', '张三调解员', 'MEDIATOR', '2000000000000000001', 'MEDIATION', 'SIGN_PROTOCOL', '/mediation/protocol/sign', 'POST', 1, 560);

-- ============================================================
-- 完成
-- ============================================================
