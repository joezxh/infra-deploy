-- ============================================================
-- 矛盾纠纷调解平台 - 视频服务数据库初始化
-- 数据库名: mediation_video
-- 服务端口: 8085
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 说明: 视频录制文件存储在MinIO，本库仅存元数据
-- 日期: 2026-05-25
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mediation_video`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_video`;

-- ============================================================
-- 第一部分: 视频调解室表
-- ============================================================
DROP TABLE IF EXISTS `video_room`;
CREATE TABLE `video_room` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `room_no` VARCHAR(50) NOT NULL COMMENT '房间号',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '关联案件ID',
    `room_type` VARCHAR(20) NOT NULL DEFAULT 'PRIVATE' COMMENT '房间类型: PRIVATE-私密群聊 CONFERENCE-会议 BROADCAST-直播',
    `room_name` VARCHAR(100) DEFAULT NULL COMMENT '房间名称',
    `max_participants` INT(3) NOT NULL DEFAULT 10 COMMENT '最大参与人数',
    `status` VARCHAR(20) NOT NULL DEFAULT 'IDLE' COMMENT '状态: IDLE-空闲 ACTIVE-进行中 ENDED-已结束 CANCELLED-已取消',
    `host_user_id` VARCHAR(32) NOT NULL COMMENT '主持人/调解员ID',
    `start_time` DATETIME DEFAULT NULL COMMENT '开始时间',
    `end_time` DATETIME DEFAULT NULL COMMENT '结束时间',
    `record_enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否开启录制: 0-关闭 1-开启',
    `srs_room_id` VARCHAR(100) DEFAULT NULL COMMENT 'SRS媒体服务器房间ID',
    `webrtc_config` JSON DEFAULT NULL COMMENT 'WebRTC配置JSON',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记: 0-未删除 1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_room_no` (`room_no`),
    KEY `idx_case` (`case_id`),
    KEY `idx_status` (`status`),
    KEY `idx_host` (`host_user_id`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='视频调解室表';

-- ============================================================
-- 第二部分: 视频参与者表
-- ============================================================
DROP TABLE IF EXISTS `video_participant`;
CREATE TABLE `video_participant` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `room_id` VARCHAR(32) NOT NULL COMMENT '房间ID',
    `user_id` VARCHAR(32) NOT NULL COMMENT '用户ID',
    `user_name` VARCHAR(50) DEFAULT NULL COMMENT '用户姓名',
    `user_role` VARCHAR(20) NOT NULL COMMENT '角色: MEDIATOR-调解员 APPLICANT-申请人 RESPONDENT-被申请人 OBSERVER-观察员',
    `join_time` DATETIME DEFAULT NULL COMMENT '加入时间',
    `leave_time` DATETIME DEFAULT NULL COMMENT '离开时间',
    `duration_seconds` INT(11) NOT NULL DEFAULT 0 COMMENT '参会时长秒数',
    `audio_enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '音频开关: 0-关闭 1-开启',
    `video_enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '视频开关: 0-关闭 1-开启',
    `connection_quality` VARCHAR(10) DEFAULT 'GOOD' COMMENT '连接质量: GOOD-良好 FAIR-一般 POOR-差',
    `ip_address` VARCHAR(50) DEFAULT NULL COMMENT 'IP地址',
    `device_info` VARCHAR(200) DEFAULT NULL COMMENT '设备信息',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_room` (`room_id`),
    KEY `idx_user` (`user_id`),
    KEY `idx_join_time` (`join_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='视频参与者表';

-- ============================================================
-- 第三部分: 视频录制记录表
-- ============================================================
DROP TABLE IF EXISTS `video_record`;
CREATE TABLE `video_record` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `room_id` VARCHAR(32) NOT NULL COMMENT '房间ID',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '案件ID',
    `file_name` VARCHAR(200) DEFAULT NULL COMMENT '文件名',
    `file_path` VARCHAR(500) DEFAULT NULL COMMENT '存储路径(MinIO/OSS/S3)',
    `file_size` BIGINT(20) DEFAULT NULL COMMENT '文件大小字节',
    `duration_seconds` INT(11) DEFAULT NULL COMMENT '录制时长秒',
    `record_type` VARCHAR(20) NOT NULL DEFAULT 'FULL' COMMENT '录制类型: FULL-全程 HIGHLIGHT-重点片段',
    `storage_type` VARCHAR(20) NOT NULL DEFAULT 'minio' COMMENT '存储类型: minio-对象存储 local-本地 oss-阿里云 s3-S3',
    `status` VARCHAR(20) NOT NULL DEFAULT 'RECORDING' COMMENT '状态: RECORDING-录制中 COMPLTED-已完成 FAILED-失败 DELETED-已删除',
    `download_url` VARCHAR(500) DEFAULT NULL COMMENT '下载URL',
    `thumbnail_url` VARCHAR(500) DEFAULT NULL COMMENT '缩略图URL',
    `start_time` DATETIME DEFAULT NULL COMMENT '录制开始时间',
    `end_time` DATETIME DEFAULT NULL COMMENT '录制结束时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_room` (`room_id`),
    KEY `idx_case` (`case_id`),
    KEY `idx_status` (`status`),
    KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='视频录制记录表';

-- ============================================================
-- 第四部分: 测试数据
-- ============================================================

INSERT INTO `video_room` (`id`, `room_no`, `case_id`, `room_type`, `room_name`, `host_user_id`, `status`, `record_enabled`) VALUES
('VR0010000000000000001', 'VR100001', 'CASE0010000000000001', 'PRIVATE', '张三与李四合同纠纷调解室', '4000000000000000001', 'ENDED', 1),
('VR0010000000000000002', 'VR100002', 'CASE0010000000002', 'PRIVATE', '王五劳动争议调解室', '4000000000000000001', 'ACTIVE', 1);

INSERT INTO `video_participant` (`id`, `room_id`, `user_id`, `user_name`, `user_role`, `join_time`, `duration_seconds`) VALUES
('VP0010000000000000001', 'VR0010000000000000001', '4000000000000000001', '张三调解员', 'MEDIATOR', NOW(), 1800),
('VP0010000000000000002', 'VR0010000000000000001', '1000000000000000003', '李四', 'RESPONDENT', NOW(), 1750);

-- ============================================================
-- 完成
-- ============================================================
