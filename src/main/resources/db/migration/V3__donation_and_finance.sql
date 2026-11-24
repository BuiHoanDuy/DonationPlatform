-- V3: Donation + Finance (sổ cái chỉ-thêm)
-- =====================================================================
-- NHÓM DONATION
-- =====================================================================
CREATE TABLE donations (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id      UUID         NOT NULL DEFAULT gen_random_uuid(),
    campaign_id    BIGINT       NOT NULL REFERENCES campaigns(id),
    user_id        BIGINT       REFERENCES users(id),            -- NULL nếu khách vãng lai
    donor_name     VARCHAR(150) NOT NULL,
    donor_email    VARCHAR(255) NOT NULL,
    amount         BIGINT       NOT NULL,
    message        VARCHAR(500),
    is_anonymous   BOOLEAN      NOT NULL DEFAULT FALSE,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    payment_method VARCHAR(30)  NOT NULL,
    paid_at        TIMESTAMPTZ,
    expires_at     TIMESTAMPTZ,                                  -- created_at + 15 phút
    receipt_no     VARCHAR(30),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version        BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT uq_donations_public_id UNIQUE (public_id),
    CONSTRAINT uq_donations_receipt UNIQUE (receipt_no),
    CONSTRAINT ck_donations_amount CHECK (amount BETWEEN 10000 AND 500000000),        -- BR-DN-1
    CONSTRAINT ck_donations_status CHECK (status IN ('PENDING','SUCCESS','FAILED','CANCELLED','EXPIRED','REFUNDED')),
    CONSTRAINT ck_donations_method CHECK (payment_method IN ('MOCK_GATEWAY','BANK_TRANSFER','VNPAY_SANDBOX','MOMO_SANDBOX')),
    CONSTRAINT ck_donations_success CHECK (status NOT IN ('SUCCESS','REFUNDED') OR (paid_at IS NOT NULL AND receipt_no IS NOT NULL))
);
CREATE INDEX idx_donations_campaign_paid ON donations (campaign_id, status, paid_at DESC);
CREATE INDEX idx_donations_user          ON donations (user_id, created_at DESC);
CREATE INDEX idx_donations_expiry        ON donations (status, expires_at);     -- job hủy giao dịch treo

CREATE TABLE payment_transactions (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id            BIGINT       NOT NULL REFERENCES donations(id),
    gateway                VARCHAR(30)  NOT NULL,
    transaction_ref        VARCHAR(100) NOT NULL,                -- khóa idempotency (BR-DN-4)
    gateway_transaction_no VARCHAR(100),
    amount                 BIGINT       NOT NULL,
    status                 VARCHAR(20)  NOT NULL DEFAULT 'INITIATED',
    raw_request            JSONB,
    raw_response           JSONB,
    error_code             VARCHAR(50),
    error_message          VARCHAR(500),
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_payment_transaction_ref UNIQUE (transaction_ref),
    CONSTRAINT ck_payment_gateway CHECK (gateway IN ('MOCK','VNPAY','MOMO','BANK_TRANSFER')),
    CONSTRAINT ck_payment_status CHECK (status IN ('INITIATED','SUCCESS','FAILED','REFUNDED')),
    CONSTRAINT ck_payment_amount CHECK (amount > 0)
);
CREATE INDEX idx_payment_transactions_donation ON payment_transactions (donation_id);

-- =====================================================================
-- NHÓM FINANCE
-- =====================================================================
CREATE TABLE expenses (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id    UUID         NOT NULL DEFAULT gen_random_uuid(),
    campaign_id  BIGINT       NOT NULL REFERENCES campaigns(id),
    created_by   BIGINT       NOT NULL REFERENCES users(id),
    category     VARCHAR(50)  NOT NULL,
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    amount       BIGINT       NOT NULL,
    expense_date DATE         NOT NULL,
    vendor_name  VARCHAR(200),
    status       VARCHAR(20)  NOT NULL DEFAULT 'PENDING_APPROVAL',
    reviewed_by  BIGINT       REFERENCES users(id),
    reviewed_at  TIMESTAMPTZ,
    reject_reason VARCHAR(500),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version      BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT uq_expenses_public_id UNIQUE (public_id),
    CONSTRAINT ck_expenses_amount CHECK (amount > 0),
    CONSTRAINT ck_expenses_category CHECK (category IN ('FOOD','TRANSPORT','MATERIAL','MEDICAL','EVENT','OTHER')),
    CONSTRAINT ck_expenses_status CHECK (status IN ('PENDING_APPROVAL','APPROVED','REJECTED')),
    CONSTRAINT ck_expenses_reject_reason CHECK (status <> 'REJECTED' OR reject_reason IS NOT NULL)
);
CREATE INDEX idx_expenses_campaign ON expenses (campaign_id, status);

CREATE TABLE expense_attachments (            -- quy tắc "≥ 1 chứng từ" và "≤ 10 file" kiểm ở service (BR-EX-3)
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    expense_id BIGINT      NOT NULL REFERENCES expenses(id),
    file_id    BIGINT      NOT NULL REFERENCES files(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_expense_attachment UNIQUE (expense_id, file_id)
);

-- Sổ cái: CHỈ THÊM. Dương = thu, âm = chi/hoàn.
CREATE TABLE ledger_entries (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id BIGINT       NOT NULL REFERENCES campaigns(id),
    entry_type  VARCHAR(20)  NOT NULL,
    amount      BIGINT       NOT NULL,
    donation_id BIGINT       REFERENCES donations(id),
    expense_id  BIGINT       REFERENCES expenses(id),
    description VARCHAR(300),
    created_by  BIGINT       REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_ledger_type CHECK (entry_type IN ('DONATION','REFUND','EXPENSE','ADJUSTMENT')),
    CONSTRAINT ck_ledger_nonzero CHECK (amount <> 0),
    CONSTRAINT ck_ledger_sign CHECK (
        (entry_type = 'DONATION'   AND amount > 0) OR
        (entry_type = 'REFUND'     AND amount < 0) OR
        (entry_type = 'EXPENSE'    AND amount < 0) OR
        (entry_type = 'ADJUSTMENT')),
    CONSTRAINT ck_ledger_source CHECK (
        (entry_type IN ('DONATION','REFUND') AND donation_id IS NOT NULL AND expense_id IS NULL) OR
        (entry_type = 'EXPENSE'              AND expense_id  IS NOT NULL AND donation_id IS NULL) OR
        (entry_type = 'ADJUSTMENT'           AND description IS NOT NULL))     -- điều chỉnh bắt buộc có lý do (BR-EX-2)
);
CREATE INDEX idx_ledger_campaign ON ledger_entries (campaign_id, created_at);
-- Mỗi donation chỉ có tối đa 1 bút toán DONATION và 1 REFUND; mỗi expense tối đa 1 bút toán EXPENSE
-- => duyệt/webhook lặp không ghi sổ hai lần.
CREATE UNIQUE INDEX uq_ledger_donation_once ON ledger_entries (donation_id, entry_type)
    WHERE entry_type IN ('DONATION','REFUND');
CREATE UNIQUE INDEX uq_ledger_expense_once ON ledger_entries (expense_id) WHERE entry_type = 'EXPENSE';

CREATE OR REPLACE FUNCTION forbid_ledger_modification() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'ledger_entries là sổ cái chỉ-thêm: không được % bản ghi', TG_OP
        USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ledger_no_update_delete
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW EXECUTE FUNCTION forbid_ledger_modification();
CREATE TRIGGER trg_ledger_no_truncate
    BEFORE TRUNCATE ON ledger_entries
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_ledger_modification();

CREATE TABLE disbursements (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id            BIGINT       NOT NULL REFERENCES campaigns(id),
    requested_by           BIGINT       NOT NULL REFERENCES users(id),
    amount                 BIGINT       NOT NULL,
    purpose                VARCHAR(500) NOT NULL,
    status                 VARCHAR(20)  NOT NULL DEFAULT 'REQUESTED',
    approved_by            BIGINT       REFERENCES users(id),
    approved_at            TIMESTAMPTZ,
    paid_at                TIMESTAMPTZ,
    bank_account_info      TEXT,                                  -- lưu dạng đã mã hóa ở tầng ứng dụng
    transfer_proof_file_id BIGINT       REFERENCES files(id),
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_disbursements_amount CHECK (amount > 0),
    CONSTRAINT ck_disbursements_status CHECK (status IN ('REQUESTED','APPROVED','REJECTED','PAID'))
);
CREATE INDEX idx_disbursements_campaign ON disbursements (campaign_id, status);

