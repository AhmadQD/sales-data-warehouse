-- ============================================================
-- 15_fix_etl_quality_view.sql
-- Reads the LATEST etl_runs row, plus a targeted query against
-- raw.sales_raw for dirty_branch_id (catalog defines 2,000 as
-- "injected" rows: trailing space or lowercase letters).
-- ============================================================

DROP VIEW IF EXISTS warehouse.vw_etl_quality CASCADE;

CREATE OR REPLACE VIEW warehouse.vw_etl_quality AS
WITH latest AS (
    SELECT *
    FROM staging.etl_runs
    WHERE pipeline_name = 'staging_sales'
    ORDER BY run_at DESC
    LIMIT 1
),
observed AS (
    SELECT 'mixed_date_format'        AS error_type,
           (SELECT normalized_date FROM latest)             AS observed_count
    UNION ALL
    SELECT 'missing_customer_id',
           (SELECT nulled_customer_id FROM latest)
    UNION ALL
    SELECT 'dirty_branch_id',
           (SELECT COUNT(*) FROM raw.sales_raw
            WHERE branch_id <> TRIM(branch_id)
               OR branch_id <> UPPER(branch_id))
    UNION ALL
    SELECT 'negative_quantity',
           (SELECT rejected_negative_quantity FROM latest)
    UNION ALL
    SELECT 'missing_discount',
           (SELECT normalized_discount FROM latest)
    UNION ALL
    SELECT 'duplicate_row',
           (SELECT duplicates_removed FROM latest)
)
SELECT
    c.error_type,
    c.injected_count::int                         AS expected,
    COALESCE(o.observed_count, 0)                 AS observed,
    (COALESCE(o.observed_count, 0) = c.injected_count::int) AS match
FROM raw.error_catalog_raw c
JOIN observed o ON c.error_type = o.error_type
ORDER BY c.error_type;

GRANT SELECT ON warehouse.vw_etl_quality TO analyst_user;

\echo ''
\echo '=== ETL quality (after fix) ==='
SELECT * FROM warehouse.vw_etl_quality;
