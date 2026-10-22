-- ============================================================
-- 05_create_staging_tables.sql
-- Creates the staging layer: cleaned, validated, typed data.
--
-- Design principles:
--   * Typed columns (DATE, INTEGER, NUMERIC) — no more TEXT.
--   * Natural keys preserved (customer_id, product_id, branch_id)
--     so the warehouse loader can map them to surrogate keys.
--   * Rows that cannot be cleaned go to staging.rejected_rows.
--   * staging is a snapshot: each ETL run TRUNCATEs and reloads.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/05_create_staging_tables.sql
-- ============================================================

-- 1. Customers (cleaned)
CREATE TABLE staging.customers_clean (
    customer_id  INTEGER PRIMARY KEY,
    name         TEXT    NOT NULL,
    city         TEXT
);

-- 2. Products (cleaned)
CREATE TABLE staging.products_clean (
    product_id   INTEGER PRIMARY KEY,
    product_name TEXT    NOT NULL,
    category     TEXT    NOT NULL,
    unit_cost    NUMERIC(10,2) NOT NULL CHECK (unit_cost >= 0)
);

-- 3. Branches (cleaned)
CREATE TABLE staging.branches_clean (
    branch_id    TEXT PRIMARY KEY,   -- trimmed, lowercased
    branch_name  TEXT NOT NULL,
    city         TEXT
);

-- 4. Sales (cleaned)
--    order_date is DATE (not TEXT).
--    customer_id is nullable (missing_customer_id stays, mapped later to Unknown).
--    discount defaults to 0 when missing.
CREATE TABLE staging.sales_clean (
    order_id     INTEGER      NOT NULL,
    order_date   DATE         NOT NULL,
    branch_id    TEXT         NOT NULL,
    customer_id  INTEGER      NULL,
    product_id   INTEGER      NOT NULL,
    quantity     INTEGER      NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount     NUMERIC(5,4)  NOT NULL DEFAULT 0 CHECK (discount >= 0 AND discount <= 1),
    PRIMARY KEY (order_id)   -- assumes one line per order in this dataset
);

CREATE INDEX idx_sales_clean_date     ON staging.sales_clean(order_date);
CREATE INDEX idx_sales_clean_product  ON staging.sales_clean(product_id);
CREATE INDEX idx_sales_clean_customer ON staging.sales_clean(customer_id);
CREATE INDEX idx_sales_clean_branch   ON staging.sales_clean(branch_id);

-- 5. Returns (cleaned)
CREATE TABLE staging.returns_clean (
    return_id    INTEGER PRIMARY KEY,
    order_id     INTEGER NOT NULL,
    return_date  DATE    NOT NULL,
    reason       TEXT
);

CREATE INDEX idx_returns_clean_order ON staging.returns_clean(order_id);

-- 6. Rejected rows (audit trail for every dropped row)
CREATE TABLE staging.rejected_rows (
    rejected_id    BIGSERIAL    PRIMARY KEY,
    source_table   TEXT         NOT NULL,   -- e.g. 'raw.sales_raw'
    source_row_id  BIGINT,                  -- raw._row_id
    reason         TEXT         NOT NULL,
    raw_data       TEXT,
    rejected_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rejected_source ON staging.rejected_rows(source_table);

-- ============================================================
-- 7. Ownership and sequence grants
-- ============================================================

ALTER TABLE staging.customers_clean  OWNER TO etl_user;
ALTER TABLE staging.products_clean   OWNER TO etl_user;
ALTER TABLE staging.branches_clean   OWNER TO etl_user;
ALTER TABLE staging.sales_clean      OWNER TO etl_user;
ALTER TABLE staging.returns_clean    OWNER TO etl_user;
ALTER TABLE staging.rejected_rows    OWNER TO etl_user;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA staging TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging
    GRANT USAGE, SELECT ON SEQUENCES TO etl_user;
    