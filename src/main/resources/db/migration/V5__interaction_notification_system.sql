-- V5: Interaction + Notification + System
-- =====================================================================
-- NHÓM INTERACTION
-- =====================================================================
CREATE TABLE comments (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id BIGINT        NOT NULL REFERENCES campaigns(id),
    user_id     BIGINT        NOT NULL REFERENCES users(id),
    parent_id   BIGINT        REFERENCES comments(id),            -- chỉ 1 cấp trả lời: kiểm ở service
    content     VARCHAR(1000) NOT NULL,
    status      VARCHAR(10)   NOT NULL DEFAULT 'VISIBLE',
    hidden_by   BIGINT        REFERENCES users(id),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ,
    CONSTRAINT ck_comments_status CHECK (status IN ('VISIBLE','HIDDEN')),
    CONSTRAINT ck_comments_content CHECK (length(btrim(content)) > 0)
);
CREATE INDEX idx_comments_campaign ON comments (campaign_id, created_at);
CREATE INDEX idx_comments_parent ON comments (parent_id);
CREATE INDEX idx_comments_user_time ON comments (user_id, created_at DESC);   -- rate limit 5 bình luận/phút

CREATE TABLE reports (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reporter_id     BIGINT        NOT NULL REFERENCES users(id),
    target_type     VARCHAR(20)   NOT NULL,
    target_id       BIGINT        NOT NULL,
    reason          VARCHAR(20)   NOT NULL,
    description     VARCHAR(1000),
    status          VARCHAR(20)   NOT NULL DEFAULT 'OPEN',
    resolved_by     BIGINT        REFERENCES users(id),
    resolution_note VARCHAR(1000),
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_reports_once UNIQUE (reporter_id, target_type, target_id),   -- chống báo cáo trùng
    CONSTRAINT ck_reports_target CHECK (target_type IN ('CAMPAIGN','COMMENT','USER')),
    CONSTRAINT ck_reports_reason CHECK (reason IN ('FRAUD','SPAM','INAPPROPRIATE','MISLEADING','OTHER')),
    CONSTRAINT ck_reports_status CHECK (status IN ('OPEN','RESOLVED','DISMISSED'))
);
CREATE INDEX idx_reports_target ON reports (target_type, target_id);        -- đếm số người báo cáo (BR-IN-3)
CREATE INDEX idx_reports_status ON reports (status, created_at);

-- =====================================================================
-- NHÓM NOTIFICATION
-- =====================================================================
CREATE TABLE notifications (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT       NOT NULL REFERENCES users(id),
    type       VARCHAR(50)  NOT NULL,
    title      VARCHAR(200) NOT NULL,
    content    VARCHAR(1000),
    link_url   VARCHAR(500),
    payload    JSONB,
    is_read    BOOLEAN      NOT NULL DEFAULT FALSE,
    read_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications (user_id, is_read, created_at DESC);

CREATE TABLE notification_preferences (
    user_id                    BIGINT  PRIMARY KEY REFERENCES users(id),
    email_campaign_updates     BOOLEAN NOT NULL DEFAULT TRUE,
    email_volunteer_reminders  BOOLEAN NOT NULL DEFAULT TRUE,
    email_donation_receipts    BOOLEAN NOT NULL DEFAULT TRUE,
    email_marketing            BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE outbox_events (                  -- Transactional Outbox
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    aggregate_type VARCHAR(50)  NOT NULL,
    aggregate_id   VARCHAR(50)  NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    retry_count    INT          NOT NULL DEFAULT 0,
    next_retry_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    sent_at        TIMESTAMPTZ,
    CONSTRAINT ck_outbox_status CHECK (status IN ('PENDING','SENT','FAILED')),
    CONSTRAINT ck_outbox_retry CHECK (retry_count >= 0)
);
CREATE INDEX idx_outbox_pending ON outbox_events (status, next_retry_at);

-- =====================================================================
-- NHÓM SYSTEM
-- =====================================================================
CREATE TABLE audit_logs (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id    BIGINT,                                          -- NULL nếu hệ thống thực hiện; không FK để log tồn tại độc lập
    actor_role  VARCHAR(30),
    action      VARCHAR(80)  NOT NULL,
    entity_type VARCHAR(50)  NOT NULL,
    entity_id   VARCHAR(50)  NOT NULL,
    old_value   JSONB,
    new_value   JSONB,
    ip_address  VARCHAR(45),
    user_agent  VARCHAR(300),
    request_id  VARCHAR(50),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_actor  ON audit_logs (actor_id, created_at DESC);

CREATE OR REPLACE FUNCTION forbid_audit_modification() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs là nhật ký chỉ-thêm: không được % bản ghi', TG_OP
        USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_no_update_delete
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION forbid_audit_modification();

-- Bảng chuẩn của thư viện ShedLock (Spring) — không đổi tên cột
CREATE TABLE shedlock (
    name       VARCHAR(64)  NOT NULL PRIMARY KEY,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL
);
