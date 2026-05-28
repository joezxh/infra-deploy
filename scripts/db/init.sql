-- ============================================================
-- 矛盾纠纷调解平台 - 数据库初始化脚本
-- 数据库名: mediation_db
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 作者: Mediation Platform Team
-- 日期: 2026-05-25
-- ============================================================

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS `mediation_db`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `mediation_db`;

-- ============================================================
-- 第一部分: 认证服务表 (mediation-uaa)
-- ============================================================

-- 系统用户表
DROP TABLE IF EXISTS `sys_user`;
CREATE TABLE `sys_user` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID（雪花算法）',
    `username` VARCHAR(50) NOT NULL COMMENT '用户名（登录账号）',
    `password` VARCHAR(255) NOT NULL COMMENT '密码（BCrypt加密）',
    `user_type` VARCHAR(20) NOT NULL DEFAULT 'INDIVIDUAL' COMMENT '用户类型：INDIVIDUAL-个人、ENTERPRISE-企业、MEDIATOR-调解员、ADMIN-管理员',
    `mobile` VARCHAR(20) DEFAULT NULL COMMENT '手机号',
    `email` VARCHAR(100) DEFAULT NULL COMMENT '邮箱',
    `real_name` VARCHAR(50) DEFAULT NULL COMMENT '真实姓名',
    `avatar` VARCHAR(500) DEFAULT NULL COMMENT '头像URL',
    `cert_level` VARCHAR(20) NOT NULL DEFAULT 'UNCERTIFIED' COMMENT '认证等级：UNCERTIFIED-未认证、BASIC-基础认证、ADVANCED-高级认证、OFFICIAL-官方认证',
    `org_id` VARCHAR(32) DEFAULT NULL COMMENT '所属机构ID',
    `status` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '状态：0-正常、1-禁用、2-锁定',
    `last_login_time` DATETIME DEFAULT NULL COMMENT '最后登录时间',
    `last_login_ip` VARCHAR(50) DEFAULT NULL COMMENT '最后登录IP',
    `login_fail_count` INT(3) NOT NULL DEFAULT 0 COMMENT '连续登录失败次数',
    `lock_until` DATETIME DEFAULT NULL COMMENT '锁定截止时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除、1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_username` (`username`),
    UNIQUE KEY `uk_mobile` (`mobile`),
    UNIQUE KEY `uk_email` (`email`),
    KEY `idx_org_id` (`org_id`),
    KEY `idx_user_type` (`user_type`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`),
    KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统用户表';

-- ============================================================
-- 第二部分: 用户服务表 (mediation-user)
-- ============================================================

-- 用户档案表（扩展用户信息）
DROP TABLE IF EXISTS `user_profile`;
CREATE TABLE `user_profile` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `user_id` VARCHAR(32) NOT NULL COMMENT '用户ID（关联sys_user）',
    `gender` VARCHAR(10) DEFAULT NULL COMMENT '性别：MALE、FEMALE、SECRET',
    `birth_date` DATE DEFAULT NULL COMMENT '出生日期',
    `region_code` VARCHAR(20) DEFAULT NULL COMMENT '行政区划代码',
    `region_name` VARCHAR(100) DEFAULT NULL COMMENT '行政区划名称',
    `address` VARCHAR(255) DEFAULT NULL COMMENT '详细地址',
    `occupation` VARCHAR(50) DEFAULT NULL COMMENT '职业',
    `company` VARCHAR(100) DEFAULT NULL COMMENT '工作单位',
    `bio` VARCHAR(500) DEFAULT NULL COMMENT '个人简介',
    `real_name` VARCHAR(50) DEFAULT NULL COMMENT '真实姓名（冗余，同步自sys_user）',
    `id_card` VARCHAR(18) DEFAULT NULL COMMENT '身份证号',
    `id_card_front` VARCHAR(500) DEFAULT NULL COMMENT '身份证正面图片URL',
    `id_card_back` VARCHAR(500) DEFAULT NULL COMMENT '身份证背面图片URL',
    `cert_status` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '认证状态：0-未认证、1-认证中、2-已认证、3-认证失败',
    `cert_fail_reason` VARCHAR(255) DEFAULT NULL COMMENT '认证失败原因',
    `cert_time` DATETIME DEFAULT NULL COMMENT '认证时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除、1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_id` (`user_id`),
    KEY `idx_region_code` (`region_code`),
    KEY `idx_cert_status` (`cert_status`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户档案表';

-- ============================================================
-- 第三部分: 机构服务表 (mediation-organization)
-- ============================================================

-- 调解机构表
DROP TABLE IF EXISTS `mediation_org`;
CREATE TABLE `mediation_org` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `name` VARCHAR(100) NOT NULL COMMENT '机构名称',
    `org_type` VARCHAR(20) NOT NULL COMMENT '机构类型：PEOPLE_MEDIATION-人民调解、COMMERCIAL-商事调解、INDUSTRY-行业调解、COURT-法院调解、OTHER-其他',
    `level` VARCHAR(20) NOT NULL COMMENT '级别：TOWNSHIP-乡镇/街道、COUNTY-区县、CITY-地市、PROVINCE-省',
    `region_code` VARCHAR(20) DEFAULT NULL COMMENT '行政区划代码',
    `region_name` VARCHAR(100) DEFAULT NULL COMMENT '行政区划名称',
    `address` VARCHAR(255) DEFAULT NULL COMMENT '机构地址',
    `contact_name` VARCHAR(50) DEFAULT NULL COMMENT '联系人姓名',
    `contact_phone` VARCHAR(20) DEFAULT NULL COMMENT '联系人电话',
    `contact_position` VARCHAR(50) DEFAULT NULL COMMENT '联系人职务',
    `credit_code` VARCHAR(50) DEFAULT NULL COMMENT '统一社会信用代码',
    `license_url` VARCHAR(500) DEFAULT NULL COMMENT '营业执照/资质证书URL',
    `description` TEXT DEFAULT NULL COMMENT '机构简介',
    `accept_scope` TEXT DEFAULT NULL COMMENT '受理范围（JSON数组）',
    `audit_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '审核状态：PENDING-待审核、APPROVED-已通过、REJECTED-已拒绝',
    `audit_remark` VARCHAR(500) DEFAULT NULL COMMENT '审核备注',
    `audit_time` DATETIME DEFAULT NULL COMMENT '审核时间',
    `auditor_id` VARCHAR(32) DEFAULT NULL COMMENT '审核人ID',
    `admin_user_id` VARCHAR(32) DEFAULT NULL COMMENT '管理员用户ID',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态：0-禁用、1-启用',
    `case_count` INT(11) NOT NULL DEFAULT 0 COMMENT '累计案件数',
    `success_count` INT(11) NOT NULL DEFAULT 0 COMMENT '成功调解数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除、1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_name` (`name`),
    UNIQUE KEY `uk_credit_code` (`credit_code`),
    KEY `idx_org_type` (`org_type`),
    KEY `idx_level` (`level`),
    KEY `idx_region_code` (`region_code`),
    KEY `idx_audit_status` (`audit_status`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`),
    KEY `idx_admin_user_id` (`admin_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='调解机构表';

-- 机构部门表
DROP TABLE IF EXISTS `org_department`;
CREATE TABLE `org_department` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `org_id` VARCHAR(32) NOT NULL COMMENT '机构ID',
    `parent_id` VARCHAR(32) NOT NULL DEFAULT '0' COMMENT '父部门ID，0表示根部门',
    `dept_name` VARCHAR(100) NOT NULL COMMENT '部门名称',
    `dept_code` VARCHAR(50) DEFAULT NULL COMMENT '部门编码',
    `dept_level` INT(3) NOT NULL DEFAULT 1 COMMENT '部门层级（1=一级部门）',
    `sort_order` INT(5) NOT NULL DEFAULT 0 COMMENT '排序号',
    `leader_id` VARCHAR(32) DEFAULT NULL COMMENT '部门负责人ID',
    `leader_name` VARCHAR(50) DEFAULT NULL COMMENT '部门负责人姓名',
    `phone` VARCHAR(20) DEFAULT NULL COMMENT '部门电话',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态：0-禁用、1-启用',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除、1-已删除',
    PRIMARY KEY (`id`),
    KEY `idx_org_id` (`org_id`),
    KEY `idx_parent_id` (`parent_id`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='机构部门表';

-- 调解员表
DROP TABLE IF EXISTS `mediator`;
CREATE TABLE `mediator` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `user_id` VARCHAR(32) NOT NULL COMMENT '关联用户ID',
    `org_id` VARCHAR(32) NOT NULL COMMENT '所属机构ID',
    `dept_id` VARCHAR(32) DEFAULT NULL COMMENT '所属部门ID',
    `employee_no` VARCHAR(50) DEFAULT NULL COMMENT '员工编号',
    `real_name` VARCHAR(50) NOT NULL COMMENT '真实姓名',
    `gender` VARCHAR(10) DEFAULT NULL COMMENT '性别',
    `mobile` VARCHAR(20) DEFAULT NULL COMMENT '手机号',
    `avatar` VARCHAR(500) DEFAULT NULL COMMENT '头像URL',
    `mediator_type` VARCHAR(20) NOT NULL DEFAULT 'FULL_TIME' COMMENT '调解员类型：FULL_TIME-专职、PART_TIME-兼职、TEMPORARY-临时',
    `expertise` JSON DEFAULT NULL COMMENT '擅长领域（JSON数组，如["CONTRACT","FAMILY"]）',
    `work_years` INT(3) DEFAULT NULL COMMENT '工作年限',
    `cert_no` VARCHAR(50) DEFAULT NULL COMMENT '调解员证书编号',
    `cert_url` VARCHAR(500) DEFAULT NULL COMMENT '调解员证书图片URL',
    `bio` VARCHAR(500) DEFAULT NULL COMMENT '个人简介',
    `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '状态：0-禁用、1-启用',
    `audit_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '审核状态：PENDING-待审核、APPROVED-已通过、REJECTED-已拒绝',
    `audit_remark` VARCHAR(255) DEFAULT NULL COMMENT '审核备注',
    `audit_time` DATETIME DEFAULT NULL COMMENT '审核时间',
    `case_limit` INT(5) NOT NULL DEFAULT 10 COMMENT '案件上限',
    `current_cases` INT(5) NOT NULL DEFAULT 0 COMMENT '当前案件数',
    `rating` DECIMAL(3,2) DEFAULT NULL COMMENT '评分（0-5分）',
    `rating_count` INT(11) NOT NULL DEFAULT 0 COMMENT '评价次数',
    `success_count` INT(11) NOT NULL DEFAULT 0 COMMENT '成功调解数',
    `total_cases` INT(11) NOT NULL DEFAULT 0 COMMENT '累计调解数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除、1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_id` (`user_id`),
    UNIQUE KEY `uk_employee_no` (`employee_no`),
    KEY `idx_org_id` (`org_id`),
    KEY `idx_dept_id` (`dept_id`),
    KEY `idx_mediator_type` (`mediator_type`),
    KEY `idx_audit_status` (`audit_status`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='调解员表';

-- ============================================================
-- 第四部分: 案件服务表 (mediation-case)
-- ============================================================

-- 案件信息表
DROP TABLE IF EXISTS `case_info`;
CREATE TABLE `case_info` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_no` VARCHAR(50) NOT NULL COMMENT '案件编号',
    `case_source` VARCHAR(20) NOT NULL DEFAULT 'SELF' COMMENT '案件来源：SELF-自主提交、DISPATCH-派发、TRANSFER-协同转入、APPOINTMENT-预约',
    `dispatch_no` VARCHAR(50) DEFAULT NULL COMMENT '派发编号（来自综治中心）',
    `case_type` VARCHAR(30) NOT NULL COMMENT '纠纷大类',
    `dispute_type` VARCHAR(50) DEFAULT NULL COMMENT '纠纷小类',
    `case_status` VARCHAR(30) NOT NULL DEFAULT 'PENDING' COMMENT '案件状态',
    `claim_amount` DECIMAL(15,2) DEFAULT NULL COMMENT '标的金额（元）',
    `urgency_level` VARCHAR(20) NOT NULL DEFAULT 'MEDIUM' COMMENT '紧急程度：LOW-一般、MEDIUM-较急、HIGH-紧急、URGENT-特别紧急',
    `applicant_id` VARCHAR(32) NOT NULL COMMENT '申请人ID',
    `applicant_name` VARCHAR(50) NOT NULL COMMENT '申请人姓名',
    `applicant_phone` VARCHAR(20) DEFAULT NULL COMMENT '申请人电话',
    `applicant_id_card` VARCHAR(18) DEFAULT NULL COMMENT '申请人身份证号',
    `respondent_name` VARCHAR(50) DEFAULT NULL COMMENT '被申请人姓名',
    `respondent_phone` VARCHAR(20) DEFAULT NULL COMMENT '被申请人电话',
    `respondent_id_card` VARCHAR(18) DEFAULT NULL COMMENT '被申请人身份证号',
    `brief_description` VARCHAR(500) NOT NULL COMMENT '纠纷简述',
    `detailed_description` TEXT DEFAULT NULL COMMENT '详细描述',
    `evidence_urls` JSON DEFAULT NULL COMMENT '证据材料URL列表（JSON数组）',
    `expected_mediation_type` VARCHAR(20) DEFAULT NULL COMMENT '期望调解方式：ONLINE-在线、OFFLINE-线下',
    `accept_org_id` VARCHAR(32) DEFAULT NULL COMMENT '受理机构ID',
    `accept_org_name` VARCHAR(100) DEFAULT NULL COMMENT '受理机构名称',
    `mediator_id` VARCHAR(32) DEFAULT NULL COMMENT '调解员ID',
    `mediator_name` VARCHAR(50) DEFAULT NULL COMMENT '调解员姓名',
    `assign_type` VARCHAR(20) DEFAULT NULL COMMENT '分配方式：AUTO-系统分配、MANUAL-手动指定',
    `assign_time` DATETIME DEFAULT NULL COMMENT '分配时间',
    `assign_by` VARCHAR(32) DEFAULT NULL COMMENT '分配人ID',
    `sign_deadline` DATETIME DEFAULT NULL COMMENT '签收截止时间',
    `sign_time` DATETIME DEFAULT NULL COMMENT '实际签收时间',
    `accept_time` DATETIME DEFAULT NULL COMMENT '受理时间',
    `start_time` DATETIME DEFAULT NULL COMMENT '开始调解时间',
    `end_time` DATETIME DEFAULT NULL COMMENT '结束调解时间',
    `close_time` DATETIME DEFAULT NULL COMMENT '结案时间',
    `close_type` VARCHAR(20) DEFAULT NULL COMMENT '结案方式：SUCCESS-调解成功、FAILED-调解失败、RETURNED-退回、WITHDRAWN-撤回',
    `mediation_result` TEXT DEFAULT NULL COMMENT '调解结果/协议摘要',
    `protocol_id` VARCHAR(32) DEFAULT NULL COMMENT '关联协议ID',
    `case_fee` DECIMAL(10,2) DEFAULT NULL COMMENT '案件费用（元）',
    `region_code` VARCHAR(20) DEFAULT NULL COMMENT '案件发生地区划代码',
    `region_name` VARCHAR(100) DEFAULT NULL COMMENT '案件发生地区划名称',
    `dispatch_org_id` VARCHAR(32) DEFAULT NULL COMMENT '派发机构ID（来自综治中心）',
    `dispatch_org_name` VARCHAR(100) DEFAULT NULL COMMENT '派发机构名称',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除、1-已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_case_no` (`case_no`),
    UNIQUE KEY `uk_dispatch_no` (`dispatch_no`),
    KEY `idx_case_source` (`case_source`),
    KEY `idx_case_type` (`case_type`),
    KEY `idx_case_status` (`case_status`),
    KEY `idx_urgency_level` (`urgency_level`),
    KEY `idx_applicant_id` (`applicant_id`),
    KEY `idx_mediator_id` (`mediator_id`),
    KEY `idx_accept_org_id` (`accept_org_id`),
    KEY `idx_region_code` (`region_code`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='案件信息表';

-- 案件分配记录表
DROP TABLE IF EXISTS `case_assign_log`;
CREATE TABLE `case_assign_log` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '案件ID',
    `from_org_id` VARCHAR(32) DEFAULT NULL COMMENT '原机构ID',
    `from_org_name` VARCHAR(100) DEFAULT NULL COMMENT '原机构名称',
    `to_org_id` VARCHAR(32) DEFAULT NULL COMMENT '目标机构ID',
    `to_org_name` VARCHAR(100) DEFAULT NULL COMMENT '目标机构名称',
    `to_mediator_id` VARCHAR(32) DEFAULT NULL COMMENT '目标调解员ID',
    `to_mediator_name` VARCHAR(50) DEFAULT NULL COMMENT '目标调解员姓名',
    `assign_type` VARCHAR(20) NOT NULL COMMENT '分配方式：AUTO-系统、MANUAL-手动',
    `assign_reason` VARCHAR(255) DEFAULT NULL COMMENT '分配原因/备注',
    `assign_by` VARCHAR(32) DEFAULT NULL COMMENT '分配操作人ID',
    `assign_by_name` VARCHAR(50) DEFAULT NULL COMMENT '分配操作人姓名',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '分配时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记',
    PRIMARY KEY (`id`),
    KEY `idx_case_id` (`case_id`),
    KEY `idx_to_org_id` (`to_org_id`),
    KEY `idx_to_mediator_id` (`to_mediator_id`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='案件分配记录表';

-- 案件操作日志表
DROP TABLE IF EXISTS `case_operation_log`;
CREATE TABLE `case_operation_log` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '案件ID',
    `operator_id` VARCHAR(32) DEFAULT NULL COMMENT '操作人ID',
    `operator_name` VARCHAR(50) DEFAULT NULL COMMENT '操作人姓名',
    `operator_type` VARCHAR(20) DEFAULT NULL COMMENT '操作人类型：PARTY-当事人、MEDIATOR-调解员、ADMIN-管理员、SYSTEM-系统',
    `operation` VARCHAR(50) NOT NULL COMMENT '操作类型',
    `content` VARCHAR(500) DEFAULT NULL COMMENT '操作内容详情',
    `before_status` VARCHAR(30) DEFAULT NULL COMMENT '操作前状态',
    `after_status` VARCHAR(30) DEFAULT NULL COMMENT '操作后状态',
    `ip_address` VARCHAR(50) DEFAULT NULL COMMENT '操作IP地址',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记',
    PRIMARY KEY (`id`),
    KEY `idx_case_id` (`case_id`),
    KEY `idx_operator_id` (`operator_id`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='案件操作日志表';

-- ============================================================
-- 第五部分: 调解服务表 (mediation-mediation)
-- ============================================================

-- 调解会话表
DROP TABLE IF EXISTS `mediation_session`;
CREATE TABLE `mediation_session` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '关联案件ID',
    `room_name` VARCHAR(100) DEFAULT NULL COMMENT '调解室名称',
    `mediation_type` VARCHAR(20) NOT NULL DEFAULT 'TEXT' COMMENT '调解类型：TEXT-文字、VIDEO-视频',
    `status` VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS' COMMENT '会话状态：IN_PROGRESS-进行中、ENDED-已结束',
    `start_time` DATETIME NOT NULL COMMENT '开始时间',
    `end_time` DATETIME DEFAULT NULL COMMENT '结束时间',
    `total_messages` INT(11) NOT NULL DEFAULT 0 COMMENT '消息总数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_case_id` (`case_id`),
    KEY `idx_status` (`status`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='调解会话表';

-- 调解消息表
DROP TABLE IF EXISTS `mediation_message`;
CREATE TABLE `mediation_message` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `session_id` VARCHAR(32) NOT NULL COMMENT '调解会话ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '案件ID',
    `sender_id` VARCHAR(32) NOT NULL COMMENT '发送者ID',
    `sender_name` VARCHAR(50) NOT NULL COMMENT '发送者姓名',
    `sender_type` VARCHAR(20) NOT NULL COMMENT '发送者类型：PARTY_APPLICANT-申请人、PARTY_RESPONDENT-被申请人、MEDIATOR-调解员、SYSTEM-系统',
    `message_type` VARCHAR(20) NOT NULL DEFAULT 'TEXT' COMMENT '消息类型：TEXT-文字、IMAGE-图片、FILE-文件、AUDIO-语音',
    `content` TEXT DEFAULT NULL COMMENT '消息内容',
    `attachment_url` VARCHAR(500) DEFAULT NULL COMMENT '附件URL',
    `read_status` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '已读状态：0-未读、1-已读',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '发送时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记',
    PRIMARY KEY (`id`),
    KEY `idx_session_id` (`session_id`),
    KEY `idx_case_id` (`case_id`),
    KEY `idx_sender_id` (`sender_id`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='调解消息表';

-- 调解协议表
DROP TABLE IF EXISTS `mediation_protocol`;
CREATE TABLE `mediation_protocol` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `case_id` VARCHAR(32) NOT NULL COMMENT '关联案件ID',
    `protocol_no` VARCHAR(50) DEFAULT NULL COMMENT '协议编号',
    `title` VARCHAR(200) NOT NULL COMMENT '协议标题',
    `content` TEXT DEFAULT NULL COMMENT '协议正文内容（富文本/HTML）',
    `status` VARCHAR(20) NOT NULL DEFAULT 'DRAFT' COMMENT '协议状态：DRAFT-草稿、PENDING-待签署、SIGNED-已签署、ARCHIVED-已归档',
    `applicant_sign` VARCHAR(500) DEFAULT NULL COMMENT '申请人签章（Base64/URL）',
    `applicant_sign_time` DATETIME DEFAULT NULL COMMENT '申请人签署时间',
    `respondent_sign` VARCHAR(500) DEFAULT NULL COMMENT '被申请人签章',
    `respondent_sign_time` DATETIME DEFAULT NULL COMMENT '被申请人签署时间',
    `mediator_sign` VARCHAR(500) DEFAULT NULL COMMENT '调解员签章',
    `mediator_sign_time` DATETIME DEFAULT NULL COMMENT '调解员签署时间',
    `sign_deadline` DATETIME DEFAULT NULL COMMENT '签署截止时间',
    `signed_time` DATETIME DEFAULT NULL COMMENT '全部签署完成时间',
    `file_url` VARCHAR(500) DEFAULT NULL COMMENT '协议文件URL（签署后生成的PDF等）',
    `create_by` VARCHAR(32) DEFAULT NULL COMMENT '创建人ID',
    `create_by_name` VARCHAR(50) DEFAULT NULL COMMENT '创建人姓名',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记',
    PRIMARY KEY (`id`),
    KEY `idx_case_id` (`case_id`),
    KEY `idx_status` (`status`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='调解协议表';

-- ============================================================
-- 第六部分: 派发对接服务表 (mediation-dispatch)
-- ============================================================

-- 派发案件表（综治中心对接）
DROP TABLE IF EXISTS `dispatch_case`;
CREATE TABLE `dispatch_case` (
    `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
    `dispatch_no` VARCHAR(50) NOT NULL COMMENT '派发编号',
    `source_system` VARCHAR(50) DEFAULT NULL COMMENT '来源系统',
    `source_case_no` VARCHAR(50) DEFAULT NULL COMMENT '原综治中心案件编号',
    `dispatch_org_id` VARCHAR(32) DEFAULT NULL COMMENT '派发机构ID',
    `dispatch_org_name` VARCHAR(100) DEFAULT NULL COMMENT '派发机构名称',
    `accept_org_id` VARCHAR(32) DEFAULT NULL COMMENT '受理机构ID',
    `accept_org_name` VARCHAR(100) DEFAULT NULL COMMENT '受理机构名称',
    `case_type` VARCHAR(30) DEFAULT NULL COMMENT '案件类型',
    `dispute_type` VARCHAR(50) DEFAULT NULL COMMENT '纠纷类型',
    `claim_amount` DECIMAL(15,2) DEFAULT NULL COMMENT '标的金额',
    `urgency_level` VARCHAR(20) DEFAULT 'MEDIUM' COMMENT '紧急程度',
    `applicant_name` VARCHAR(50) DEFAULT NULL COMMENT '申请人姓名',
    `applicant_phone` VARCHAR(20) DEFAULT NULL COMMENT '申请人电话',
    `respondent_name` VARCHAR(50) DEFAULT NULL COMMENT '被申请人姓名',
    `respondent_phone` VARCHAR(20) DEFAULT NULL COMMENT '被申请人电话',
    `brief_description` VARCHAR(500) DEFAULT NULL COMMENT '纠纷简述',
    `detailed_description` TEXT DEFAULT NULL COMMENT '详细描述',
    `evidence_urls` JSON DEFAULT NULL COMMENT '证据材料URL',
    `dispatch_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '派发状态：PENDING-待处理、RECEIVED-已接收',
    `sign_status` VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '签收状态：PENDING-待签收、SIGNED-已签收、RETURNED-已退回',
    `sign_deadline` DATETIME DEFAULT NULL COMMENT '签收截止时间',
    `sign_time` DATETIME DEFAULT NULL COMMENT '实际签收时间',
    `return_reason` VARCHAR(500) DEFAULT NULL COMMENT '退回原因',
    `return_time` DATETIME DEFAULT NULL COMMENT '退回时间',
    `return_by` VARCHAR(32) DEFAULT NULL COMMENT '退回操作人ID',
    `case_id` VARCHAR(32) DEFAULT NULL COMMENT '关联本地案件ID（签收后生成）',
    `remark` VARCHAR(500) DEFAULT NULL COMMENT '备注',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '删除标记',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_dispatch_no` (`dispatch_no`),
    UNIQUE KEY `uk_source_case_no` (`source_case_no`),
    KEY `idx_accept_org_id` (`accept_org_id`),
    KEY `idx_sign_status` (`sign_status`),
    KEY `idx_dispatch_status` (`dispatch_status`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='派发案件表（综治中心对接）';

-- ============================================================
-- 第七部分: 索引优化（可选，针对大数据量场景）
-- ============================================================

-- CREATE INDEX idx_case_info_create_time ON case_info (create_time DESC);
-- CREATE INDEX idx_case_info_applicant_time ON case_info (applicant_id, create_time DESC);
-- CREATE INDEX idx_mediation_message_session_time ON mediation_message (session_id, create_time ASC);

-- ============================================================
-- 第八部分: 测试数据
-- ============================================================

-- 插入测试管理员用户（密码: Admin@123456）
INSERT INTO `sys_user` (`id`, `username`, `password`, `user_type`, `mobile`, `real_name`, `cert_level`, `status`) VALUES
('1000000000000000001', 'admin', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iAt.znXi', 'ADMIN', '13800138000', '系统管理员', 'OFFICIAL', 0),
('1000000000000000002', 'mediator001', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iAt.znXi', 'MEDIATOR', '13800138001', '张三调解员', 'OFFICIAL', 0),
('1000000000000000003', 'user001', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iAt.znXi', 'INDIVIDUAL', '13800138002', '李四', 'BASIC', 0);

-- 插入测试调解机构
INSERT INTO `mediation_org` (`id`, `name`, `org_type`, `level`, `region_code`, `region_name`, `address`, `contact_name`, `contact_phone`, `audit_status`, `admin_user_id`, `status`) VALUES
('2000000000000000001', '杭州市上城区人民调解委员会', 'PEOPLE_MEDIATION', 'TOWNSHIP', '330102', '浙江省杭州市上城区', '杭州市上城区某街道', '王主任', '0571-88888888', 'APPROVED', '1000000000000000001', 1),
('2000000000000000002', '西湖区商事调解中心', 'COMMERCIAL', 'COUNTY', '330106', '浙江省杭州市西湖区', '杭州市西湖区某路', '李经理', '0571-87777777', 'APPROVED', '1000000000000000001', 1);

-- 插入测试部门
INSERT INTO `org_department` (`id`, `org_id`, `parent_id`, `dept_name`, `dept_level`, `sort_order`, `status`) VALUES
('3000000000000000001', '2000000000000000001', '0', '综合管理部', 1, 1, 1),
('3000000000000000002', '2000000000000000001', '0', '调解业务部', 1, 2, 1);

-- 插入测试调解员
INSERT INTO `mediator` (`id`, `user_id`, `org_id`, `dept_id`, `real_name`, `gender`, `mobile`, `mediator_type`, `expertise`, `work_years`, `audit_status`, `case_limit`, `status`) VALUES
('4000000000000000001', '1000000000000000002', '2000000000000000001', '3000000000000000002', '张三调解员', 'MALE', '13800138001', 'FULL_TIME', '["CONTRACT","PROPERTY","FAMILY"]', 5, 'APPROVED', 15, 1);

-- 插入测试用户档案
INSERT INTO `user_profile` (`id`, `user_id`, `gender`, `cert_status`) VALUES
('5000000000000000001', '1000000000000000001', 'MALE', 2),
('5000000000000000002', '1000000000000000002', 'MALE', 2),
('5000000000000000003', '1000000000000000003', 'MALE', 2);

-- ============================================================
-- 完成
-- ============================================================
