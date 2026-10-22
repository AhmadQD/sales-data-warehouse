-- ============================================================
-- 10_verify_fact_sales.sql
-- Acceptance tests for warehouse.fact_sales.
-- Every test returns PASS or FAIL.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/10_verify_fact_sales.sql
-- ============================================================

\echo ''
\echo '=== FACT_SALES ACCEPTANCE TESTS ==='
\echo ''

WITH tests AS (

    -- 1. row count
    SELECT
        'T01 row count = 99500' AS test_name,
        CASE WHEN COUNT(*) = 99500 THEN 'PASS' ELSE 'FAIL' END AS result,
        COUNT(*)::text AS detail
    FROM warehouse.fact_sales

    UNION ALL

    -- 2. no orphan date_key
    SELECT
        'T02 no orphan date_key',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM warehouse.fact_sales f
    LEFT JOIN warehouse.dim_date d ON f.date_key = d.date_key
    WHERE d.date_key IS NULL

    UNION ALL

    -- 3. no orphan customer_key
    SELECT
        'T03 no orphan customer_key',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM warehouse.fact_sales f
    LEFT JOIN warehouse.dim_customer c ON f.customer_key = c.customer_key
    WHERE c.customer_key IS NULL

    UNION ALL

    -- 4. no orphan product_key
    SELECT
        'T04 no orphan product_key',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM warehouse.fact_sales f
    LEFT JOIN warehouse.dim_product p ON f.product_key = p.product_key
    WHERE p.product_key IS NULL

    UNION ALL

    -- 5. no orphan branch_key
    SELECT
        'T05 no orphan branch_key',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM warehouse.fact_sales f
    LEFT JOIN warehouse.dim_branch b ON f.branch_key = b.branch_key
    WHERE b.branch_key IS NULL

    UNION ALL

    -- 6. gross_amount matches quantity * unit_price
    SELECT
        'T06 gross_amount = quantity * unit_price',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM warehouse.fact_sales
    WHERE gross_amount <> ROUND(quantity * unit_price, 2)

    UNION ALL

    -- 7. profit_amount matches net_amount - cost_amount
    SELECT
        'T07 profit_amount = net_amount - cost_amount',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text
    FROM warehouse.fact_sales
    WHERE profit_amount <> ROUND(net_amount - cost_amount, 2)

    UNION ALL

    -- 8. totals match expected values from the loader run
    SELECT
        'T08 totals match loader output',
        CASE
            WHEN ROUND(SUM(gross_amount), 2)  = 30775575.11
             AND ROUND(SUM(net_amount), 2)    = 29801719.88
             AND ROUND(SUM(cost_amount), 2)   = 22211630.95
             AND ROUND(SUM(profit_amount), 2) = 7590088.93
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        FORMAT('gross=%s net=%s cost=%s profit=%s',
               ROUND(SUM(gross_amount),2),
               ROUND(SUM(net_amount),2),
               ROUND(SUM(cost_amount),2),
               ROUND(SUM(profit_amount),2))
    FROM warehouse.fact_sales
)
SELECT test_name, result, detail
FROM tests
ORDER BY test_name;

\echo ''
\echo '=== Summary totals ==='
SELECT
    COUNT(*)                       AS rows_total,
    ROUND(SUM(gross_amount),  2)   AS gross_total,
    ROUND(SUM(net_amount),    2)   AS net_total,
    ROUND(SUM(cost_amount),   2)   AS cost_total,
    ROUND(SUM(profit_amount), 2)   AS profit_total
FROM warehouse.fact_sales;
