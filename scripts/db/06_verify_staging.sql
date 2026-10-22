-- ============================================================
-- 06_verify_staging.sql
-- Acceptance tests for the staging layer.
-- Each test returns a single row: (test_name, result, detail).
-- Expected result for every test: PASS.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/06_verify_staging.sql
-- ============================================================

\echo ''
\echo '=== STAGING ACCEPTANCE TESTS ==='
\echo ''

WITH tests AS (

    -- 1. sales_clean row count
    SELECT
        'T01 sales_clean row count = 99500' AS test_name,
        CASE WHEN COUNT(*) = 99500 THEN 'PASS' ELSE 'FAIL' END AS result,
        COUNT(*)::text AS detail
    FROM staging.sales_clean

    UNION ALL

    -- 2. rejected_rows (sales) count = 500
    SELECT
        'T02 rejected sales rows = 500',
        CASE WHEN COUNT(*) = 500 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.rejected_rows
    WHERE source_table = 'raw.sales_raw'

    UNION ALL

    -- 3. no duplicate order_id
    SELECT
        'T03 no duplicate order_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM (
        SELECT order_id FROM staging.sales_clean
        GROUP BY order_id HAVING COUNT(*) > 1
    ) d

    UNION ALL

    -- 4. all quantity > 0
    SELECT
        'T04 all quantity > 0',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean WHERE quantity <= 0

    UNION ALL

    -- 5. all unit_price >= 0
    SELECT
        'T05 all unit_price >= 0',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean WHERE unit_price < 0

    UNION ALL

    -- 6. all discount in [0,1]
    SELECT
        'T06 all discount in [0,1]',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean WHERE discount < 0 OR discount > 1

    UNION ALL

    -- 7. all branch_id lowercase
    SELECT
        'T07 all branch_id lowercase',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean WHERE branch_id <> LOWER(branch_id)

    UNION ALL

    -- 8. customer_id is NULL or exists in customers_clean
    SELECT
        'T08 no orphan customer_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean s
    LEFT JOIN staging.customers_clean c ON s.customer_id = c.customer_id
    WHERE s.customer_id IS NOT NULL AND c.customer_id IS NULL

    UNION ALL

    -- 9. product_id exists in products_clean
    SELECT
        'T09 no orphan product_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean s
    LEFT JOIN staging.products_clean p ON s.product_id = p.product_id
    WHERE p.product_id IS NULL

    UNION ALL

    -- 10. branch_id exists in branches_clean
    SELECT
        'T10 no orphan branch_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM staging.sales_clean s
    LEFT JOIN staging.branches_clean b ON s.branch_id = b.branch_id
    WHERE b.branch_id IS NULL
)
SELECT test_name, result, detail
FROM tests
ORDER BY test_name;
