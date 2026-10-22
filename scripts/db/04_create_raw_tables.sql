-- ============================================================
-- 04_create_raw_tables.sql
-- Creates the landing zone (raw schema) for source data.
--
-- Design principles:
-- * All source columns are TEXT — no parsing, no validation.
-- Cleaning happens in staging, never here.
-- * Every row carries metadata: _row_id, _loaded_at, _source_file.
-- * Two support tables: raw.load_log, raw.load_errors.
--
-- Run connected to sales_dw:
-- psql -U postgres -d sales_dw -f scripts/db/04_create_raw_tables.sql
-- ============================================================

-- 1. Sales (source: data/raw/sales.csv)
CREATE TABLE raw.sales_raw (
_row_id BIGSERIAL PRIMARY KEY,
_loaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
_source_file TEXT NOT NULL,
order_id TEXT,
order_date TEXT,
branch_id TEXT,
customer_id TEXT,
product_id TEXT,
quantity TEXT,
unit_price TEXT,
discount TEXT
);

-- 2. Returns (source: data/raw/returns.csv)
CREATE TABLE raw.returns_raw (
_row_id BIGSERIAL PRIMARY KEY,
_loaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
_source_file TEXT NOT NULL,
return_id TEXT,
order_id TEXT,
return_date TEXT,
reason TEXT
);

-- 3. Products (source: data/raw/products.xlsx)
CREATE TABLE raw.products_raw (
_row_id BIGSERIAL PRIMARY KEY,
_loaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
_source_file TEXT NOT NULL,
product_id TEXT,
product_name TEXT,
category TEXT,
unit_cost TEXT
);

-- 4. Customers (source: data/raw/customers.json)
CREATE TABLE raw.customers_raw (
_row_id BIGSERIAL PRIMARY KEY,
_loaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
_source_file TEXT NOT NULL,
customer_id TEXT,
name TEXT,
city TEXT
);

-- 5. Branches (source: data/raw/branches.json)
CREATE TABLE raw.branches_raw (
_row_id BIGSERIAL PRIMARY KEY,
_loaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
_source_file TEXT NOT NULL,
branch_id TEXT,
branch_name TEXT,
city TEXT
);

-- 6. Error catalog (source: data/raw/error_catalog.csv)
-- Reference data used to measure ETL accuracy (question 8).
CREATE TABLE raw.error_catalog_raw (
    _row_id        BIGSERIAL    PRIMARY KEY,
    _loaded_at     TIMESTAMP    NOT NULL DEFAULT NOW(),
    _source_file   TEXT         NOT NULL,
    error_type     TEXT,
    injected_count TEXT,
    description    TEXT
);

-- 7. Load log — one row per load attempt (file-level metadata)
CREATE TABLE raw.load_log (
load_id BIGSERIAL PRIMARY KEY,
source_file TEXT NOT NULL,
target_table TEXT NOT NULL,
started_at TIMESTAMP NOT NULL DEFAULT NOW(),
finished_at TIMESTAMP,
rows_read INTEGER,
rows_loaded INTEGER,
rows_failed INTEGER,
status TEXT NOT NULL DEFAULT 'running'
CHECK (status IN ('running','success','failed')),
error_message TEXT
);

-- 8. Load errors — row-level failures (for auditability)
CREATE TABLE raw.load_errors (
error_id BIGSERIAL PRIMARY KEY,
load_id BIGINT NOT NULL REFERENCES raw.load_log(load_id),
source_file TEXT NOT NULL,
row_number INTEGER,
raw_data TEXT,
error_message TEXT NOT NULL,
created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 9. Indexes for common lookups
CREATE INDEX idx_sales_raw_order_id ON raw.sales_raw(order_id);
CREATE INDEX idx_returns_raw_order_id ON raw.returns_raw(order_id);
CREATE INDEX idx_load_log_source ON raw.load_log(source_file);
CREATE INDEX idx_load_errors_load_id ON raw.load_errors(load_id);


-- ============================================================
-- 10. Ownership and sequence grants
--     The ETL user must own the tables (for TRUNCATE ... RESTART IDENTITY)
--     and must have USAGE on the sequences behind BIGSERIAL columns.
-- ============================================================

ALTER TABLE raw.sales_raw          OWNER TO etl_user;
ALTER TABLE raw.returns_raw        OWNER TO etl_user;
ALTER TABLE raw.products_raw       OWNER TO etl_user;
ALTER TABLE raw.customers_raw      OWNER TO etl_user;
ALTER TABLE raw.branches_raw       OWNER TO etl_user;
ALTER TABLE raw.error_catalog_raw  OWNER TO etl_user;
ALTER TABLE raw.load_log           OWNER TO etl_user;
ALTER TABLE raw.load_errors        OWNER TO etl_user;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA raw TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw
    GRANT USAGE, SELECT ON SEQUENCES TO etl_user;
    