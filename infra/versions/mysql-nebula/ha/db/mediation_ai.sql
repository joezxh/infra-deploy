-- ============================================================
-- 矛盾纠纷调解平台 - AI服务数据库初始化
-- 数据库名: mediation_ai
-- 服务端口: 8084
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 说明: Neo4j存储知识图谱(bolt://localhost:7687)，pgvector存储向量(本库仅存元数据)
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_ai`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_ai`;

-- ============================================================
-- 第一部分: AI案例向量表
-- 说明: case_vector字段存储embedding向量(JSON格式)
--       生产环境推荐使用 PostgreSQL + pgvector 替代本表做向量检索
-- ============================================================
DROP TABLE IF EXISTS `legal_case`;
CREATE TABLE `legal_case` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_no` VARCHAR(50) NOT NULL COMMENT '案例编号',
    `dispute_type` VARCHAR(50) DEFAULT NULL COMMENT '纠纷类型',
    `case_title` VARCHAR(200) DEFAULT NULL COMMENT '案例标题',
    `case_summary` TEXT DEFAULT NULL COMMENT '案例摘要',
    `facts` TEXT DEFAULT NULL COMMENT '案件事实',
    `mediation_result` VARCHAR(50) DEFAULT NULL COMMENT '调解结果: SUCCESS-成功 FAILED-失败 RETURNED-退回 WITHDRAWN-撤回',
    `mediation_strategy` VARCHAR(500) DEFAULT NULL COMMENT '调解策略',
    `applicable_laws` VARCHAR(500) DEFAULT NULL COMMENT '适用法律，多条用分号分隔',
    `case_vector` VARCHAR(8000) DEFAULT NULL COMMENT '案例向量embedding(JSON格式)',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '所属机构',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_case_no` (`case_no`),
    KEY `idx_dispute_type` (`dispute_type`),
    KEY `idx_org` (`org_id`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI案例向量表';

-- ============================================================
-- 第二部分: AI调用记录表
-- ============================================================
DROP TABLE IF EXISTS `ai_call_log`;
CREATE TABLE `ai_call_log` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '关联案件ID',
    `user_id` VARCHAR(32) DEFAULT NULL COMMENT '调用用户ID',
    `module` VARCHAR(50) NOT NULL COMMENT '调用模块: KNOWLEDGE_GRAPH-知识图谱 STRATEGY_RECOMMEND-策略推荐 REAL_TIME_ASSIST-实时辅助 DOCUMENT_GENERATION-文书生成 LEGAL_CONSULT-法律咨询',
    `request_data` TEXT DEFAULT NULL COMMENT '请求数据JSON',
    `response_data` TEXT DEFAULT NULL COMMENT '响应数据JSON',
    `tokens_used` INT(11) DEFAULT NULL COMMENT '消耗token数',
    `latency_ms` INT(11) DEFAULT NULL COMMENT '响应耗时毫秒',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-失败 1-成功',
    `error_message` VARCHAR(500) DEFAULT NULL COMMENT '错误信息',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_case` (`case_id`),
    KEY `idx_user` (`user_id`),
    KEY `idx_module` (`module`),
    KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI调用日志表';

-- ============================================================
-- 第三部分: 风险预警记录表
-- ============================================================
DROP TABLE IF EXISTS `risk_warning`;
CREATE TABLE `risk_warning` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '案件ID',
    `user_id` VARCHAR(32) DEFAULT NULL COMMENT '关联用户ID',
    `risk_level` VARCHAR(20) NOT NULL COMMENT '风险等级: LOW-低 MEDIUM-中 HIGH-高 CRITICAL-紧急',
    `risk_score` DECIMAL(5,2) DEFAULT NULL COMMENT '风险评分 0-100',
    `warning_type` VARCHAR(50) DEFAULT NULL COMMENT '预警类型: EMOTION-情绪激化 RISK_PHRASE-敏感词 ABORTION-投诉上访',
    `warning_message` TEXT DEFAULT NULL COMMENT '预警消息',
    `context_data` TEXT DEFAULT NULL COMMENT '上下文JSON',
    `handled` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已处理: 0-未处理 1-已处理',
    `handler_id` VARCHAR(32) DEFAULT NULL COMMENT '处理人ID',
    `handle_time` DATETIME DEFAULT NULL COMMENT '处理时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_case` (`case_id`),
    KEY `idx_user` (`user_id`),
    KEY `idx_risk_level` (`risk_level`),
    KEY `idx_handled` (`handled`),
    KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='风险预警记录表';

-- ============================================================
-- 第四部分: 测试数据
-- ============================================================

INSERT INTO `legal_case` (`id`, `case_no`, `dispute_type`, `case_title`, `case_summary`, `mediation_result`, `mediation_strategy`, `applicable_laws`) VALUES
('LC0010000000000000001', 'AL-2024-001', 'PROPERTY', '物业费纠纷调解', '业主拖欠物业费2000元，物业公司多次催缴无果', 'SUCCESS', '从合同约定和服务实际质量双向切入，引导业主认可服务价值', '《民法典》第938条;《物业管理条例》'),
('LC0010000000000000002', 'AL-2024-002', 'LABOR', '劳动合同解除补偿', '员工工作3年后被辞退，单位拒绝支付经济补偿金', 'SUCCESS', '强调劳动合同法规定，引导单位依法履行义务', '《劳动合同法》第46条;《劳动争议调解仲裁法》'),
('LC0010000000000000003', 'AL-2024-003', 'FAMILY', '离婚财产分割', '夫妻离婚因房产分割产生争议，价值约200万元', 'SUCCESS', '从共有财产分割原则出发，兼顾双方实际贡献', '《民法典》第1087条;《婚姻家庭编司法解释》'),
('LC0010000000000000004', 'AL-2024-004', 'TRAFFIC', '交通事故损害赔偿', '行人被电动车撞伤，医疗费8000元，双方就赔偿金额分歧大', 'SUCCESS', '依据交通事故责任认定书，参照赔偿标准核算', '《道路交通安全法》第76条;《民法典》第1213条'),
('LC0010000000000000005', 'AL-2024-005', 'CONTRACT', '买卖合同货款纠纷', '买方拖欠货款5万元，卖方多次催要无果', 'SUCCESS', '核对合同约定和送货凭证，明确还款期限', '《民法典》第626条;《合同编通则解释》');

-- ============================================================
-- 完成
-- ============================================================
