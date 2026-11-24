-- V2: Organizer + Campaign
-- =====================================================================
-- NHÓM ORGANIZER
-- =====================================================================
CREATE TABLE organizer_profiles (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id           UUID         NOT NULL DEFAULT gen_random_uuid(),
    user_id             BIGINT       NOT NULL REFERENCES users(id),
    organization_name   VARCHAR(200) NOT NULL,
    organization_type   VARCHAR(30)  NOT NULL,
    description         TEXT,
    address             VARCHAR(300),
    representative_name VARCHAR(150) NOT NULL,
    contact_phone       VARCHAR(20)  NOT NULL,
    contact_email       VARCHAR(255),
    website_url         VARCHAR(300),
    status              VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    reject_reason       VARCHAR(500),
    reviewed_by         BIGINT       REFERENCES users(id),
    reviewed_at         TIMESTAMPTZ,
    trust_score         NUMERIC(4,2) NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version             BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT uq_organizer_public_id UNIQUE (public_id),
    CONSTRAINT uq_organizer_user UNIQUE (user_id),                       -- BR-OR-1
    CONSTRAINT ck_organizer_type CHECK (organization_type IN ('INDIVIDUAL','GROUP','SCHOOL','NGO','COMPANY')),
    CONSTRAINT ck_organizer_status CHECK (status IN ('PENDING','APPROVED','REJECTED','SUSPENDED')),
    CONSTRAINT ck_organizer_reject_reason CHECK (status <> 'REJECTED' OR reject_reason IS NOT NULL)  -- BR-OR-2
);
CREATE INDEX idx_organizer_status ON organizer_profiles (status);

CREATE TABLE organizer_documents (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizer_id BIGINT      NOT NULL REFERENCES organizer_profiles(id),
    doc_type     VARCHAR(20) NOT NULL,
    file_id      BIGINT      NOT NULL REFERENCES files(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_organizer_doc_type CHECK (doc_type IN ('ID_CARD','LICENSE','OTHER'))
);
CREATE INDEX idx_organizer_documents_org ON organizer_documents (organizer_id);

-- =====================================================================
-- NHÓM CAMPAIGN
-- =====================================================================
CREATE TABLE categories (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(120) NOT NULL,
    description VARCHAR(300),
    icon        VARCHAR(50),
    sort_order  INT          NOT NULL DEFAULT 0,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_categories_name UNIQUE (name),
    CONSTRAINT uq_categories_slug UNIQUE (slug)
);

CREATE TABLE campaigns (
    id                        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id                 UUID         NOT NULL DEFAULT gen_random_uuid(),
    organizer_id              BIGINT       NOT NULL REFERENCES organizer_profiles(id),
    category_id               BIGINT       NOT NULL REFERENCES categories(id),
    title                     VARCHAR(200) NOT NULL,
    slug                      VARCHAR(250) NOT NULL,
    short_description         VARCHAR(500) NOT NULL,
    description               TEXT         NOT NULL,           -- HTML đã sanitize ở tầng ứng dụng
    type                      VARCHAR(20)  NOT NULL,
    status                    VARCHAR(30)  NOT NULL DEFAULT 'DRAFT',
    cover_file_id             BIGINT       REFERENCES files(id),
    province                  VARCHAR(100),
    address                   VARCHAR(300),
    latitude                  NUMERIC(9,6),
    longitude                 NUMERIC(9,6),
    goal_amount               BIGINT,
    raised_amount             BIGINT       NOT NULL DEFAULT 0,  -- denormalized, cập nhật cùng transaction với ledger
    donation_count            INT          NOT NULL DEFAULT 0,
    disbursed_amount          BIGINT       NOT NULL DEFAULT 0,
    beneficiary_info          TEXT,
    start_date                DATE         NOT NULL,
    end_date                  DATE         NOT NULL,
    is_featured               BOOLEAN      NOT NULL DEFAULT FALSE,
    view_count                BIGINT       NOT NULL DEFAULT 0,
    report_deadline           DATE,                              -- end_date + 30 ngày (BR-CP-9)
    final_report_submitted_at TIMESTAMPTZ,
    search_vector             TSVECTOR,
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at                TIMESTAMPTZ,
    version                   BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT uq_campaigns_public_id UNIQUE (public_id),
    CONSTRAINT uq_campaigns_slug UNIQUE (slug),
    CONSTRAINT ck_campaigns_type CHECK (type IN ('FUNDRAISING','VOLUNTEER','HYBRID')),
    CONSTRAINT ck_campaigns_status CHECK (status IN
        ('DRAFT','PENDING_REVIEW','APPROVED','REJECTED','ACTIVE','PAUSED','ENDED','CLOSED','SUSPENDED')),
    CONSTRAINT ck_campaigns_dates CHECK (end_date > start_date),                      -- BR-CP-2
    CONSTRAINT ck_campaigns_duration CHECK (end_date - start_date <= 180),            -- BR-CP-2
    CONSTRAINT ck_campaigns_goal CHECK (goal_amount IS NULL OR goal_amount >= 0),
    CONSTRAINT ck_campaigns_goal_min CHECK (type = 'VOLUNTEER' OR goal_amount >= 1000000),  -- BR-CP-3
    CONSTRAINT ck_campaigns_raised CHECK (raised_amount >= 0),
    CONSTRAINT ck_campaigns_disbursed CHECK (disbursed_amount >= 0),
    CONSTRAINT ck_campaigns_donation_count CHECK (donation_count >= 0)
);
CREATE INDEX idx_campaigns_status_end   ON campaigns (status, end_date);
CREATE INDEX idx_campaigns_category     ON campaigns (category_id, status);
CREATE INDEX idx_campaigns_province     ON campaigns (province, status);
CREATE INDEX idx_campaigns_organizer    ON campaigns (organizer_id);
CREATE INDEX idx_campaigns_featured     ON campaigns (is_featured, status);
CREATE INDEX idx_campaigns_search       ON campaigns USING GIN (search_vector);

-- Full-text search: bỏ dấu tiếng Việt + 'simple' (không stemming). Trọng số: tiêu đề A, mô tả ngắn B, địa điểm C.
CREATE OR REPLACE FUNCTION campaigns_search_vector_update() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('simple', unaccent(coalesce(NEW.title, ''))), 'A') ||
        setweight(to_tsvector('simple', unaccent(coalesce(NEW.short_description, ''))), 'B') ||
        setweight(to_tsvector('simple', unaccent(coalesce(NEW.province, '') || ' ' || coalesce(NEW.address, ''))), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_campaigns_search_vector
    BEFORE INSERT OR UPDATE OF title, short_description, province, address ON campaigns
    FOR EACH ROW EXECUTE FUNCTION campaigns_search_vector_update();

CREATE TABLE campaign_images (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id BIGINT      NOT NULL REFERENCES campaigns(id),
    file_id     BIGINT      NOT NULL REFERENCES files(id),
    caption     VARCHAR(300),
    sort_order  INT         NOT NULL DEFAULT 0
);
CREATE INDEX idx_campaign_images_campaign ON campaign_images (campaign_id);

CREATE TABLE campaign_updates (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id BIGINT       NOT NULL REFERENCES campaigns(id),
    author_id   BIGINT       NOT NULL REFERENCES users(id),
    title       VARCHAR(200) NOT NULL,
    content     TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_campaign_updates_campaign ON campaign_updates (campaign_id, created_at DESC);

CREATE TABLE campaign_reviews (               -- lịch sử kiểm duyệt
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id BIGINT      NOT NULL REFERENCES campaigns(id),
    reviewer_id BIGINT      NOT NULL REFERENCES users(id),
    decision    VARCHAR(20) NOT NULL,
    comment     VARCHAR(1000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_campaign_reviews_decision CHECK (decision IN ('APPROVED','REJECTED','CHANGES_REQUESTED')),
    CONSTRAINT ck_campaign_reviews_comment CHECK (decision = 'APPROVED' OR comment IS NOT NULL)  -- từ chối/yêu cầu sửa phải có lý do
);
CREATE INDEX idx_campaign_reviews_campaign ON campaign_reviews (campaign_id, created_at DESC);

CREATE TABLE campaign_follows (
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    campaign_id BIGINT      NOT NULL REFERENCES campaigns(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, campaign_id)
);
CREATE INDEX idx_campaign_follows_campaign ON campaign_follows (campaign_id);

