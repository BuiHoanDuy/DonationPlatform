-- V4: Volunteer
-- =====================================================================
-- NHÓM VOLUNTEER
-- =====================================================================
CREATE TABLE volunteer_positions (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id    BIGINT       NOT NULL REFERENCES campaigns(id),
    title          VARCHAR(150) NOT NULL,
    description    TEXT,
    requirements   VARCHAR(500),
    quantity       INT          NOT NULL,
    approved_count INT          NOT NULL DEFAULT 0,
    start_time     TIMESTAMPTZ  NOT NULL,
    end_time       TIMESTAMPTZ  NOT NULL,
    location       VARCHAR(300),
    status         VARCHAR(20)  NOT NULL DEFAULT 'OPEN',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version        BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT ck_vol_positions_quantity CHECK (quantity > 0),
    CONSTRAINT ck_vol_positions_approved CHECK (approved_count >= 0 AND approved_count <= quantity),  -- BR-VL-3
    CONSTRAINT ck_vol_positions_time CHECK (end_time > start_time),
    CONSTRAINT ck_vol_positions_status CHECK (status IN ('OPEN','FULL','CLOSED'))
);
CREATE INDEX idx_vol_positions_campaign ON volunteer_positions (campaign_id);
CREATE INDEX idx_vol_positions_time ON volunteer_positions (start_time);   -- job nhắc lịch

CREATE TABLE volunteer_registrations (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    position_id         BIGINT       NOT NULL REFERENCES volunteer_positions(id),
    user_id             BIGINT       NOT NULL REFERENCES users(id),
    contact_phone       VARCHAR(20)  NOT NULL,
    introduction        VARCHAR(500),
    status              VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    reject_reason       VARCHAR(300),
    reviewed_by         BIGINT       REFERENCES users(id),
    reviewed_at         TIMESTAMPTZ,
    checked_in_at       TIMESTAMPTZ,
    volunteer_hours     NUMERIC(5,2),
    late_cancelled      BOOLEAN      NOT NULL DEFAULT FALSE,        -- hủy muộn < 24h (BR-VL-4)
    certificate_file_id BIGINT       REFERENCES files(id),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version             BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT ck_vol_reg_status CHECK (status IN ('PENDING','APPROVED','REJECTED','CANCELLED','ATTENDED','ABSENT')),
    CONSTRAINT ck_vol_reg_hours CHECK (volunteer_hours IS NULL OR volunteer_hours >= 0),
    CONSTRAINT ck_vol_reg_reject CHECK (status <> 'REJECTED' OR reject_reason IS NOT NULL)
);
CREATE INDEX idx_vol_reg_position ON volunteer_registrations (position_id, status);
CREATE INDEX idx_vol_reg_user ON volunteer_registrations (user_id);
-- BR-VL-1: 1 người chỉ đăng ký 1 lần/vị trí (được đăng ký lại sau khi đã hủy/bị từ chối)
CREATE UNIQUE INDEX uq_vol_reg_active ON volunteer_registrations (position_id, user_id)
    WHERE status NOT IN ('CANCELLED','REJECTED');

