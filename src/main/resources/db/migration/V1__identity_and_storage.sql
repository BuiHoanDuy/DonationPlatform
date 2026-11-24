-- V1: nền tảng + Identity + Storage
CREATE EXTENSION IF NOT EXISTS unaccent;   -- tìm kiếm tiếng Việt không dấu

-- ---------------------------------------------------------------------
-- Hàm dùng chung
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- NHÓM IDENTITY
-- =====================================================================
CREATE TABLE users (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id           UUID         NOT NULL DEFAULT gen_random_uuid(),
    email               VARCHAR(255) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    full_name           VARCHAR(150) NOT NULL,
    phone               VARCHAR(20),
    avatar_file_id      BIGINT,                              -- FK thêm sau khi có bảng files
    status              VARCHAR(30)  NOT NULL DEFAULT 'PENDING_VERIFICATION',
    email_verified_at   TIMESTAMPTZ,
    failed_login_count  INT          NOT NULL DEFAULT 0,
    locked_until        TIMESTAMPTZ,
    last_login_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    version             BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT uq_users_public_id UNIQUE (public_id),
    CONSTRAINT ck_users_status CHECK (status IN ('PENDING_VERIFICATION','ACTIVE','LOCKED','DELETED')),
    CONSTRAINT ck_users_failed_login CHECK (failed_login_count >= 0)
);
-- BR-ID-1: email duy nhất, không phân biệt hoa thường
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));

CREATE TABLE roles (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(30) NOT NULL,
    description VARCHAR(200),
    CONSTRAINT uq_roles_name UNIQUE (name),
    CONSTRAINT ck_roles_name CHECK (name IN ('USER','ORGANIZER','ADMIN'))
);

CREATE TABLE user_roles (
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    role_id     BIGINT      NOT NULL REFERENCES roles(id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    assigned_by BIGINT      REFERENCES users(id),
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE refresh_tokens (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        BIGINT       NOT NULL REFERENCES users(id),
    token_hash     VARCHAR(128) NOT NULL,                    -- SHA-256 của token
    expires_at     TIMESTAMPTZ  NOT NULL,
    revoked_at     TIMESTAMPTZ,
    replaced_by_id BIGINT       REFERENCES refresh_tokens(id), -- rotation, phát hiện tái sử dụng
    user_agent     VARCHAR(300),
    ip_address     VARCHAR(45),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash)
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens (user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens (expires_at);   -- job dọn token

CREATE TABLE verification_tokens (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT       NOT NULL REFERENCES users(id),
    token_hash  VARCHAR(128) NOT NULL,
    type        VARCHAR(20)  NOT NULL,
    expires_at  TIMESTAMPTZ  NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_verification_tokens_hash UNIQUE (token_hash),
    CONSTRAINT ck_verification_tokens_type CHECK (type IN ('EMAIL_VERIFY','PASSWORD_RESET'))
);
CREATE INDEX idx_verification_tokens_user ON verification_tokens (user_id, type);

-- =====================================================================
-- NHÓM STORAGE (files) — tạo sớm vì nhiều bảng tham chiếu
-- =====================================================================
CREATE TABLE files (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id       UUID         NOT NULL DEFAULT gen_random_uuid(),
    uploaded_by     BIGINT       REFERENCES users(id),
    original_name   VARCHAR(255) NOT NULL,
    stored_name     VARCHAR(100) NOT NULL,                   -- UUID, không dùng tên người dùng đặt
    content_type    VARCHAR(100) NOT NULL,
    size_bytes      BIGINT       NOT NULL,
    storage_type    VARCHAR(10)  NOT NULL DEFAULT 'LOCAL',
    storage_path    VARCHAR(500) NOT NULL,
    visibility      VARCHAR(10)  NOT NULL DEFAULT 'PUBLIC',
    ref_type        VARCHAR(30),
    ref_id          BIGINT,
    checksum_sha256 VARCHAR(64),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT uq_files_public_id UNIQUE (public_id),
    CONSTRAINT ck_files_size CHECK (size_bytes > 0 AND size_bytes <= 5242880),   -- BR-EX-3: ≤ 5MB, không rỗng
    CONSTRAINT ck_files_storage_type CHECK (storage_type IN ('LOCAL','S3')),
    CONSTRAINT ck_files_visibility CHECK (visibility IN ('PUBLIC','PRIVATE')),
    CONSTRAINT ck_files_ref_type CHECK (ref_type IS NULL OR ref_type IN
        ('AVATAR','CAMPAIGN_COVER','CAMPAIGN_IMAGE','CAMPAIGN_UPDATE','EXPENSE_PROOF',
         'ORGANIZER_DOC','TRANSFER_PROOF','CERTIFICATE'))
);
CREATE INDEX idx_files_ref ON files (ref_type, ref_id);
CREATE INDEX idx_files_uploaded_by ON files (uploaded_by);

ALTER TABLE users
    ADD CONSTRAINT fk_users_avatar_file FOREIGN KEY (avatar_file_id) REFERENCES files(id);

