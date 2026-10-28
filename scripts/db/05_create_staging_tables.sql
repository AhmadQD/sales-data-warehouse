-- ============================================================
-- 05_create_staging_tables.sql
-- Creates the staging layer: cleaned, validated, typed data.
--
-- Design principles:
-- * Typed columns (DATE, INTEGER, NUMERIC) — no more TEXT.
-- * Natural keys preserved as TEXT (customer_id, product_id,
-- branch_id, order_id, return_id) so the warehouse loader can
-- map them to surrogate keys.
-- * Rows that cannot be cleaned go to staging.rejected_rows.
-- * staging is a snapshot: each ETL run TRUNCATEs and reloads.
--
-- Run connected to sales_dw:
-- psql -U postgres -d sales_dw -f scripts/db/05_create_staging_tables.sql
-- ============================================================

-- 1. Customers (cleaned)
CREATE TABLE staging.customers_clean (
customer_id TEXT PRIMARY KEY,
name TEXT NOT NULL,
city TEXT
);

-- 2. Products (cleaned)
CREATE TABLE staging.products_clean (
product_id TEXT PRIMARY KEY,
product_name TEXT NOT NULL,
category TEXT NOT NULL,
unit_cost NUMERIC(10,2) NOT NULL CHECK (unit_cost >= 0)
);

-- 3. Branches (cleaned)
CREATE TABLE staging.branches_clean (
branch_id TEXT PRIMARY KEY,
branch_name TEXT NOT NULL,
city TEXT
);

-- 4. Sales (cleaned)
CREATE TABLE staging.sales_clean (
order_id TEXT PRIMARY KEY,
order_date DATE NOT NULL,
branch_id TEXT NOT NULL,
customer_id TEXT NULL,
product_id TEXT NOT NULL,
quantity INTEGER NOT NULL CHECK (quantity > 0),
unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
discount NUMERIC(5,4) NOT NULL DEFAULT 0 CHECK (discount >= 0 AND discount <= 1)
);

CREATE INDEX idx_sales_clean_date ON staging.sales_clean(order_date);
CREATE INDEX idx_sales_clean_product ON staging.sales_clean(product_id);
CREATE INDEX idx_sales_clean_customer ON staging.sales_clean(customer_id);
CREATE INDEX idx_sales_clean_branch ON staging.sales_clean(branch_id);

-- 5. Returns (cleaned)
CREATE TABLE staging.returns_clean (
return_id TEXT PRIMARY KEY,
order_id TEXT NOT NULL,
return_date DATE NOT NULL,
reason TEXT
);

CREATE INDEX idx_returns_clean_order ON staging.returns_clean(order_id);

-- 6. Rejected rows (audit trail for every dropped row)
CREATE TABLE staging.rejected_rows (
    rejected_id    BIGSERIAL    PRIMARY KEY,
    run_id         BIGINT       NOT NULL,
    source_table   TEXT         NOT NULL,
    source_row_id  BIGINT,
    reason         TEXT         NOT NULL,
    raw_data       TEXT,
    rejected_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rejected_run ON staging.rejected_rows(run_id);

CREATE INDEX idx_rejected_source ON staging.rejected_rows(source_table);

-- 7. Orphan returns (returns with no matching order in sales_clean)
CREATE TABLE staging.orphan_returns (
orphan_id BIGSERIAL PRIMARY KEY,
return_id TEXT NOT NULL,
order_id TEXT NOT NULL,
detected_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 8. ETL stats (legacy — kept for compatibility with 12_master_test_runner)
CREATE TABLE staging.etl_stats (
stat_id BIGSERIAL PRIMARY KEY,
run_at TIMESTAMP NOT NULL DEFAULT NOW(),
source_table TEXT NOT NULL,
metric TEXT NOT NULL,
value INTEGER NOT NULL
);

CREATE INDEX idx_etl_stats_run ON staging.etl_stats(run_at);
CREATE INDEX idx_etl_stats_metric ON staging.etl_stats(metric);

-- 9. ETL runs (append-only audit log, used by vw_etl_quality)
CREATE TABLE staging.etl_runs (
run_id BIGSERIAL PRIMARY KEY,
pipeline_name TEXT NOT NULL,
run_at TIMESTAMP NOT NULL DEFAULT NOW(),
rows_read INTEGER NOT NULL,
rows_kept INTEGER NOT NULL,
rejected_negative_quantity INTEGER NOT NULL DEFAULT 0,
rejected_bad_date INTEGER NOT NULL DEFAULT 0,
rejected_other INTEGER NOT NULL DEFAULT 0,
duplicates_removed INTEGER NOT NULL DEFAULT 0,
normalized_branch_id INTEGER NOT NULL DEFAULT 0,
normalized_date INTEGER NOT NULL DEFAULT 0,
normalized_discount INTEGER NOT NULL DEFAULT 0,
nulled_customer_id INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_etl_runs_pipeline ON staging.etl_runs(pipeline_name, run_at DESC);

-- ============================================================
-- Ownership and sequence grants
-- ============================================================

ALTER TABLE staging.customers_clean OWNER TO etl_user;
ALTER TABLE staging.products_clean OWNER TO etl_user;
ALTER TABLE staging.branches_clean OWNER TO etl_user;
ALTER TABLE staging.sales_clean OWNER TO etl_user;
ALTER TABLE staging.returns_clean OWNER TO etl_user;
ALTER TABLE staging.rejected_rows OWNER TO etl_user;
ALTER TABLE staging.orphan_returns OWNER TO etl_user;
ALTER TABLE staging.etl_stats OWNER TO etl_user;
ALTER TABLE staging.etl_runs OWNER TO etl_user;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA staging TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging
GRANT USAGE, SELECT ON SEQUENCES TO etl_user;