-- ============================================================
-- 矛盾纠纷调解平台 - 统计服务数据库初始化
-- 数据库名: mediation_stats
-- 服务端口: 8087
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 说明: 统计数据定时从各业务库聚合，本库为预计算结果
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_stats`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_stats`;

-- ============================================================
-- 第一部分: 每日案件统计快照表
-- ============================================================
DROP TABLE IF EXISTS `daily_stats`;
CREATE TABLE `daily_stats` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `stat_date` DATE NOT NULL COMMENT '统计日期',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '机构ID',
    `org_name` VARCHAR(100) DEFAULT NULL COMMENT '机构名称',
    `region_code` VARCHAR(20) DEFAULT NULL COMMENT '地区编码',
    `region_name` VARCHAR(100) DEFAULT NULL COMMENT '地区名称',
    `new_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '新增案件数',
    `total_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '在办案件总数',
    `closed_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '结案数',
    `success_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '调解成功数',
    `failed_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '调解失败数',
    `returned_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '退回案件数',
    `withdrawn_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '撤回案件数',
    `avg_duration_days` DECIMAL(10,2) DEFAULT NULL COMMENT '平均调解天数',
    `success_rate` DECIMAL(5,2) DEFAULT NULL COMMENT '调解成功率百分比',
    `case_amount` DECIMAL(20,2) DEFAULT 0 COMMENT '涉案总金额（元）',
    `mediator_count` INT(11) NOT NULL DEFAULT 0 COMMENT '参与调解员人数',
    `video_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '视频调解案件数',
    `online_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '在线调解案件数',
    `field_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '外出调解案件数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_date_org` (`stat_date`, `org_id`),
    KEY `idx_stat_date` (`stat_date`),
    KEY `idx_org` (`org_id`),
    KEY `idx_region` (`region_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='每日案件统计快照表';

-- ============================================================
-- 第二部分: 调解员绩效表
-- ============================================================
DROP TABLE IF EXISTS `mediator_performance`;
CREATE TABLE `mediator_performance` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `mediator_id` VARCHAR(32) NOT NULL COMMENT '调解员ID',
    `mediator_name` VARCHAR(50) DEFAULT NULL COMMENT '调解员姓名',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '所属机构ID',
    `org_name` VARCHAR(100) DEFAULT NULL COMMENT '所属机构名称',
    `stat_month` VARCHAR(7) NOT NULL COMMENT '统计月份: YYYY-MM',
    `total_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '受理案件数',
    `closed_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '结案数',
    `success_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '成功数',
    `failed_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '失败数',
    `returned_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '退回数',
    `success_rate` DECIMAL(5,2) DEFAULT NULL COMMENT '成功率百分比',
    `avg_duration_days` DECIMAL(10,2) DEFAULT NULL COMMENT '平均调解天数',
    `avg_score` DECIMAL(3,1) DEFAULT 5.0 COMMENT '平均满意度评分(1-5分)',
    `rating_count` INT(11) NOT NULL DEFAULT 0 COMMENT '评价次数',
    `case_amount` DECIMAL(20,2) DEFAULT 0 COMMENT '涉案金额（元）',
    `video_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '视频调解数',
    `field_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '外出调解数',
    `ranking` INT(11) DEFAULT NULL COMMENT '本机构内排名',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_mediator_month` (`mediator_id`, `stat_month`),
    KEY `idx_mediator` (`mediator_id`),
    KEY `idx_org` (`org_id`),
    KEY `idx_month` (`stat_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='调解员绩效表';

-- ============================================================
-- 第三部分: 纠纷类型统计表
-- ============================================================
DROP TABLE IF EXISTS `dispute_type_stats`;
CREATE TABLE `dispute_type_stats` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `stat_date` DATE NOT NULL COMMENT '统计日期',
    `dispute_type` VARCHAR(50) NOT NULL COMMENT '纠纷类型',
    `dispute_type_name` VARCHAR(100) DEFAULT NULL COMMENT '纠纷类型名称',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '机构ID',
    `case_count` INT(11) NOT NULL DEFAULT 0 COMMENT '案件数',
    `success_count` INT(11) NOT NULL DEFAULT 0 COMMENT '成功数',
    `failed_count` INT(11) NOT NULL DEFAULT 0 COMMENT '失败数',
    `avg_amount` DECIMAL(15,2) DEFAULT NULL COMMENT '平均标的金额',
    `avg_duration_days` DECIMAL(10,2) DEFAULT NULL COMMENT '平均调解天数',
    `success_rate` DECIMAL(5,2) DEFAULT NULL COMMENT '成功率百分比',
    `占比` DECIMAL(5,2) DEFAULT NULL COMMENT '占比百分比',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_date_type_org` (`stat_date`, `dispute_type`, `org_id`),
    KEY `idx_date` (`stat_date`),
    KEY `idx_type` (`dispute_type`),
    KEY `idx_org` (`org_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='纠纷类型统计表';

-- ============================================================
-- 第四部分: 测试数据
-- ============================================================

-- 每日统计（近30天模拟）
INSERT INTO `daily_stats` (`id`, `stat_date`, `org_id`, `org_name`, `region_name`, `new_cases`, `total_cases`, `closed_cases`, `success_cases`, `failed_cases`, `avg_duration_days`, `success_rate`, `case_amount`, `mediator_count`, `video_cases`) VALUES
('DS0010000000000000001', DATE_SUB(CURDATE(), INTERVAL 1 DAY), '2000000000000000001', '杭州市上城区人民调解委员会', '浙江省杭州市上城区', 5, 32, 4, 3, 1, 7.5, 75.0, 85000.00, 8, 2),
('DS0010000000000000002', DATE_SUB(CURDATE(), INTERVAL 1 DAY), '2000000000000000002', '西湖区商事调解中心', '浙江省杭州市西湖区', 3, 18, 3, 3, 0, 5.0, 100.0, 120000.00, 5, 1),
('DS0010000000000000003', CURDATE(), '2000000000000000001', '杭州市上城区人民调解委员会', '浙江省杭州市上城区', 7, 35, 5, 4, 1, 6.0, 80.0, 95000.00, 8, 3);

-- 调解员绩效
INSERT INTO `mediator_performance` (`id`, `mediator_id`, `mediator_name`, `org_id`, `org_name`, `stat_month`, `total_cases`, `closed_cases`, `success_cases`, `success_rate`, `avg_duration_days`, `avg_score`, `rating_count`, `case_amount`) VALUES
('MP0010000000000000001', '4000000000000000001', '张三调解员', '2000000000000000001', '杭州市上城区人民调解委员会', DATE_FORMAT(CURDATE(), '%Y-%m'), 15, 12, 10, 83.3, 6.5, 4.8, 8, 150000.00);

-- ============================================================
-- 完成
-- ============================================================
