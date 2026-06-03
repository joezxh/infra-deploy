-- ============================================================
-- 矛盾纠纷调解平台 - 内容服务数据库初始化
-- 数据库名: mediation_content
-- 服务端口: 8083
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_content`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_content`;

-- ============================================================
-- 第一部分: 知识库分类表
-- ============================================================
DROP TABLE IF EXISTS `knowledge_category`;
CREATE TABLE `knowledge_category` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `parent_id` VARCHAR(32) DEFAULT NULL COMMENT '父分类ID',
    `category_name` VARCHAR(100) NOT NULL COMMENT '分类名称',
    `category_code` VARCHAR(50) DEFAULT NULL COMMENT '分类编码',
    `sort_order` INT(5) NOT NULL DEFAULT 0 COMMENT '排序号',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_parent` (`parent_id`),
    KEY `idx_code` (`category_code`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='知识库分类表';

-- ============================================================
-- 第二部分: 知识库文章表
-- ============================================================
DROP TABLE IF EXISTS `knowledge`;
CREATE TABLE `knowledge` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `category_id` VARCHAR(32) NOT NULL COMMENT '分类ID',
    `title` VARCHAR(200) NOT NULL COMMENT '标题',
    `content` TEXT DEFAULT NULL COMMENT '富文本内容',
    `summary` VARCHAR(500) DEFAULT NULL COMMENT '摘要',
    `tags` VARCHAR(500) DEFAULT NULL COMMENT '标签，逗号分隔',
    `author_id` VARCHAR(32) DEFAULT NULL COMMENT '作者ID',
    `author_name` VARCHAR(50) DEFAULT NULL COMMENT '作者姓名',
    `view_count` INT(11) NOT NULL DEFAULT 0 COMMENT '浏览次数',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-下架 1-上架',
    `publish_time` DATETIME DEFAULT NULL COMMENT '发布时间',
    `source` VARCHAR(100) DEFAULT NULL COMMENT '来源',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_category` (`category_id`),
    KEY `idx_status` (`status`),
    KEY `idx_publish_time` (`publish_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='知识库文章表';

-- ============================================================
-- 第三部分: 典型案例表
-- ============================================================
DROP TABLE IF EXISTS `case_show`;
CREATE TABLE `case_show` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_no` VARCHAR(50) NOT NULL COMMENT '案例编号（脱敏）',
    `case_title` VARCHAR(200) NOT NULL COMMENT '案例标题',
    `dispute_type` VARCHAR(50) DEFAULT NULL COMMENT '纠纷类型',
    `case_summary` TEXT DEFAULT NULL COMMENT '案例概述（脱敏处理）',
    `mediation_process` TEXT DEFAULT NULL COMMENT '调解过程（脱敏）',
    `mediation_result` VARCHAR(50) DEFAULT NULL COMMENT '调解结果',
    `key_points` TEXT DEFAULT NULL COMMENT '调解要点/启示，多条用分号分隔',
    `applicable_laws` VARCHAR(500) DEFAULT NULL COMMENT '适用法律法规，多条用分号分隔',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '发布机构ID',
    `org_name` VARCHAR(100) DEFAULT NULL COMMENT '发布机构名称',
    `is_anonymous` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否匿名展示',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-下架 1-上架',
    `publish_time` DATETIME DEFAULT NULL COMMENT '发布时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_dispute_type` (`dispute_type`),
    KEY `idx_status` (`status`),
    KEY `idx_publish_time` (`publish_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='典型案例表';

-- ============================================================
-- 第四部分: 公告表
-- ============================================================
DROP TABLE IF EXISTS `notice`;
CREATE TABLE `notice` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `notice_type` VARCHAR(20) NOT NULL COMMENT '类型: SYSTEM-系统 NOTICE-公告 POLICY-政策法规',
    `title` VARCHAR(200) NOT NULL COMMENT '标题',
    `content` TEXT DEFAULT NULL COMMENT '内容',
    `priority` TINYINT(2) NOT NULL DEFAULT 0 COMMENT '优先级: 0-普通 1-重要 2-紧急',
    `target_scope` VARCHAR(20) NOT NULL DEFAULT 'ALL' COMMENT '范围: ALL-全部 ORG-机构 MEDIATOR-调解员',
    `target_org_ids` TEXT DEFAULT NULL COMMENT '指定机构ID列表，JSON格式',
    `attachment_urls` TEXT DEFAULT NULL COMMENT '附件URL列表，JSON格式',
    `publish_time` DATETIME DEFAULT NULL COMMENT '发布时间',
    `expire_time` DATETIME DEFAULT NULL COMMENT '过期时间',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态: 0-下架 1-上架',
    `publisher_id` VARCHAR(32) DEFAULT NULL COMMENT '发布人ID',
    `publisher_name` VARCHAR(50) DEFAULT NULL COMMENT '发布人姓名',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_type` (`notice_type`),
    KEY `idx_priority` (`priority`),
    KEY `idx_publish_time` (`publish_time`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='公告表';

-- ============================================================
-- 第五部分: 测试数据
-- ============================================================

-- 知识库分类
INSERT INTO `knowledge_category` (`id`, `parent_id`, `category_name`, `category_code`, `sort_order`, `status`) VALUES
('KC0010000000000000001', NULL, '合同纠纷', 'CONTRACT', 1, 1),
('KC0010000000000000002', NULL, '劳动争议', 'LABOR', 2, 1),
('KC0010000000000000003', NULL, '婚姻家庭', 'FAMILY', 3, 1),
('KC0010000000000000004', NULL, '交通事故', 'TRAFFIC', 4, 1),
('KC0010000000000000005', NULL, '邻里纠纷', 'NEIGHBOR', 5, 1);

-- 典型案例
INSERT INTO `case_show` (`id`, `case_no`, `case_title`, `dispute_type`, `case_summary`, `mediation_process`, `mediation_result`, `key_points`, `applicable_laws`, `status`, `publish_time`) VALUES
('CS0010000000000000001', 'AL-2024-001', '某小区物业费纠纷调解案', 'PROPERTY', '业主与物业公司因物业费标准产生争议，经调解达成一致', '调解员组织双方现场调解，从合同条款和实际服务内容入手，引导双方互谅互让', '调解成功', '调解应从合同入手，明确双方权利义务', '《中华人民共和国民法典》第九百三十八条;《物业管理条例》', 1, NOW()),
('CS0010000000000000002', 'AL-2024-002', '劳动合同解除经济补偿金争议', 'LABOR', '劳动者与用人单位因解除劳动合同经济补偿金数额存在分歧', '调解员通过背靠背调解，分别与双方沟通，最终促成一致', '调解成功', '劳动争议应注重保护劳动者合法权益，同时考虑企业经营实际', '《中华人民共和国劳动合同法》第四十六条;《劳动争议调解仲裁法》', 1, NOW());

-- 公告
INSERT INTO `notice` (`id`, `notice_type`, `title`, `content`, `priority`, `target_scope`, `status`, `publish_time`) VALUES
('NT0010000000000000001', 'NOTICE', '关于开展2024年度调解工作的的通知', '各调解组织：为进一步做好矛盾纠纷排查化解工作，现就2024年度调解工作安排通知如下...', 1, 'ALL', 1, NOW()),
('NT0010000000000000002', 'POLICY', '《浙江省矛盾纠纷多元化解条例》', '浙江省第十三届人民代表大会常务委员会公告...', 0, 'ALL', 1, NOW());

-- ============================================================
-- 完成
-- ============================================================
