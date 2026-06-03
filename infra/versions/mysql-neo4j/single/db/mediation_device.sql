-- ============================================================
-- 矛盾纠纷调解平台 - 设备服务数据库初始化
-- 数据库名: mediation_device
-- 服务端口: 8086
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_device`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_device`;

-- ============================================================
-- 第一部分: 设备表
-- ============================================================
DROP TABLE IF EXISTS `device`;
CREATE TABLE `device` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `device_code` VARCHAR(100) NOT NULL COMMENT '设备编码（SN号）',
    `device_type` VARCHAR(30) NOT NULL COMMENT '设备类型: ROKID_GLASS-智能眼镜 RECORDING_PEN-录音笔 TABLET-平板',
    `device_name` VARCHAR(100) DEFAULT NULL COMMENT '设备名称',
    `device_model` VARCHAR(100) DEFAULT NULL COMMENT '设备型号',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '所属机构ID',
    `org_name` VARCHAR(100) DEFAULT NULL COMMENT '所属机构名称',
    `bind_user_id` VARCHAR(32) DEFAULT NULL COMMENT '绑定用户ID',
    `bind_user_name` VARCHAR(50) DEFAULT NULL COMMENT '绑定用户姓名',
    `bind_time` DATETIME DEFAULT NULL COMMENT '绑定时间',
    `status` VARCHAR(20) NOT NULL DEFAULT 'OFFLINE' COMMENT '状态: ONLINE-在线 OFFLINE-离线 MAINTENANCE-维护中',
    `last_heartbeat` DATETIME DEFAULT NULL COMMENT '最后心跳时间',
    `firmware_version` VARCHAR(50) DEFAULT NULL COMMENT '固件版本',
    `config_data` JSON DEFAULT NULL COMMENT '设备配置JSON',
    `location_lat` DECIMAL(10,7) DEFAULT NULL COMMENT '当前位置纬度',
    `location_lng` DECIMAL(10,7) DEFAULT NULL COMMENT '当前位置经度',
    `location_address` VARCHAR(200) DEFAULT NULL COMMENT '当前位置地址',
    `battery_level` INT(3) DEFAULT NULL COMMENT '电池电量百分比 0-100',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_device_code` (`device_code`),
    KEY `idx_type` (`device_type`),
    KEY `idx_org` (`org_id`),
    KEY `idx_bind_user` (`bind_user_id`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='设备表';

-- ============================================================
-- 第二部分: 外出调解记录表
-- ============================================================
DROP TABLE IF EXISTS `mediation_visit`;
CREATE TABLE `mediation_visit` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '案件ID',
    `mediator_id` VARCHAR(32) NOT NULL COMMENT '调解员ID',
    `mediator_name` VARCHAR(50) DEFAULT NULL COMMENT '调解员姓名',
    `visit_address` VARCHAR(200) DEFAULT NULL COMMENT '外出地址',
    `visit_time` DATETIME DEFAULT NULL COMMENT '计划外出时间',
    `arrival_time` DATETIME DEFAULT NULL COMMENT '到达时间',
    `leave_time` DATETIME DEFAULT NULL COMMENT '离开时间',
    `device_id` VARCHAR(32) DEFAULT NULL COMMENT '使用设备ID',
    `visit_purpose` VARCHAR(100) DEFAULT NULL COMMENT '外出目的',
    `visit_result` VARCHAR(50) DEFAULT NULL COMMENT '外出结果: COMPLETED-完成 CANCELLED-取消 PARTIAL-部分完成',
    `notes` TEXT DEFAULT NULL COMMENT '备注',
    `longitude` DECIMAL(10,7) DEFAULT NULL COMMENT '经度',
    `latitude` DECIMAL(10,7) DEFAULT NULL COMMENT '纬度',
    `distance_km` DECIMAL(8,2) DEFAULT NULL COMMENT '离目标距离(公里)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_case` (`case_id`),
    KEY `idx_mediator` (`mediator_id`),
    KEY `idx_visit_time` (`visit_time`),
    KEY `idx_status` (`visit_result`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='外出调解记录表';

-- ============================================================
-- 第三部分: 设备数据表
-- ============================================================
DROP TABLE IF EXISTS `device_data`;
CREATE TABLE `device_data` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `device_id` VARCHAR(32) NOT NULL COMMENT '设备ID',
    `data_type` VARCHAR(30) NOT NULL COMMENT '数据类型: VIDEO-视频 AUDIO-音频 LOCATION-定位 HEARTBEAT-心跳 COMMAND-指令',
    `data_content` TEXT DEFAULT NULL COMMENT '数据内容JSON',
    `file_url` VARCHAR(500) DEFAULT NULL COMMENT '文件URL（视频/音频）',
    `location_lat` DECIMAL(10,7) DEFAULT NULL COMMENT '纬度',
    `location_lng` DECIMAL(10,7) DEFAULT NULL COMMENT '经度',
    `location_address` VARCHAR(200) DEFAULT NULL COMMENT '地址',
    `record_time` DATETIME DEFAULT NULL COMMENT '记录时间',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '关联案件ID',
    `visit_id` VARCHAR(32) DEFAULT NULL COMMENT '关联外出记录ID',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_device` (`device_id`),
    KEY `idx_data_type` (`data_type`),
    KEY `idx_case` (`case_id`),
    KEY `idx_record_time` (`record_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='设备数据表';

-- ============================================================
-- 第四部分: 测试数据
-- ============================================================

INSERT INTO `device` (`id`, `device_code`, `device_type`, `device_name`, `device_model`, `org_id`, `org_name`, `bind_user_id`, `bind_user_name`, `status`, `firmware_version`) VALUES
('DV0010000000000000001', 'RK-2024-0001', 'ROKID_GLASS', 'Rokid Glass MAX 2', 'Rokid Glass MAX 2 Pro', '2000000000000000001', '杭州市上城区人民调解委员会', '4000000000000000001', '张三调解员', 'OFFLINE', 'v3.2.1'),
('DV0010000000000000002', 'RP-2024-0001', 'RECORDING_PEN', '科大讯飞录音笔', 'SR502', '2000000000000000001', '杭州市上城区人民调解委员会', '4000000000000000001', '张三调解员', 'OFFLINE', 'v1.8.0'),
('DV0010000000000000003', 'TB-2024-0001', 'TABLET', '华为MatePad', 'MatePad Pro 11', '2000000000000000002', '西湖区商事调解中心', NULL, NULL, 'OFFLINE', 'HarmonyOS 4.0');

INSERT INTO `mediation_visit` (`id`, `case_id`, `mediator_id`, `mediator_name`, `visit_address`, `visit_time`, `arrival_time`, `leave_time`, `visit_result`, `longitude`, `latitude`) VALUES
('VS0010000000000000001', 'CASE0010000000000001', '4000000000000000001', '张三调解员', '杭州市上城区某某街道123号', DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY), 'COMPLETED', 120.1534, 30.2741);

-- ============================================================
-- 完成
-- ============================================================
