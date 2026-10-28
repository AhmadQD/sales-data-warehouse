-- ============================================================
-- 11_create_watermark.sql
-- Creates the incremental load control table.
--
-- Design notes:
--   * One row per pipeline (e.g. 'staging_sales', 'fact_sales').
--   * last_loaded_key is TEXT — we use natural keys (order_id),
--     not surrogate keys, because surrogate keys change when raw
--     is reloaded (TRUNCATE ... RESTART IDENTITY).
--   * The warehouse reads this table at the start of every run,
--     and updates it at the end (in the same transaction).
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/11_create_watermark.sql
-- ============================================================

CREATE TABLE warehouse.etl_watermark (
    pipeline_name        TEXT         PRIMARY KEY,
    last_loaded_key      TEXT,                          -- e.g. 'O0099999'
    last_loaded_date     DATE,                          -- optional, for date-based pipelines
    last_run_at          TIMESTAMP    NOT NULL DEFAULT NOW(),
 rows_loaded_last_run    INTEGER      NOT NULL DEFAULT 0,
    total_rows_processed INTEGER      NOT NULL DEFAULT 0
);

ALTER TABLE warehouse.etl_watermark OWNER TO etl_user;

-- Initialize the two pipelines we will implement
INSERT INTO warehouse.etl_watermark
    (pipeline_name, last_loaded_key, last_loaded_date, rows_loaded_last_run, total_rows_processed)
VALUES
    ('staging_sales', NULL, NULL, 0, 0),
    ('fact_sales',    NULL, NULL, 0, 0);

-- ============================================================
-- Verify
-- ============================================================
\echo ''
\echo '=== etl_watermark initialized ==='
SELECT * FROM warehouse.etl_watermark ORDER BY pipeline_name;
