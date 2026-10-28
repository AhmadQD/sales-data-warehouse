-- ============================================================
-- 12_master_test_runner.sql
-- Runs all acceptance tests in one command and prints a final verdict.
--
-- Sections:
--   1. Staging tests (10)
--   2. Fact tests (8)
--   3. Final summary
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/12_master_test_runner.sql
--
-- Exit criteria for production CI: every test must return PASS.
-- ============================================================

\echo ''
\echo '============================================================'
\echo '  MASTER TEST RUNNER — sales-data-warehouse'
\echo '============================================================'
\echo ''

-- ------------------------------------------------------------
-- Collect all tests into a single results table
-- ------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.test_results;
CREATE TEMP TABLE test_results (
    section    TEXT,
    test_name  TEXT,
    result     TEXT,
    detail     TEXT
);

-- ============================================================
-- Section 1: staging
-- ============================================================
INSERT INTO test_results
SELECT 'staging', 'T01 sales_clean matches fact_sales',
       CASE WHEN (SELECT COUNT(*) FROM staging.sales_clean) = (SELECT COUNT(*) FROM warehouse.fact_sales)
            THEN 'PASS' ELSE 'FAIL' END,
       (SELECT COUNT(*) FROM staging.sales_clean)::text;

INSERT INTO test_results
SELECT 'staging', 'T02 rejected sales rows = 500',
       CASE WHEN COUNT(*) = 500 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.rejected_rows
WHERE source_table = 'raw.sales_raw';

INSERT INTO test_results
SELECT 'staging', 'T03 no duplicate order_id',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM (SELECT order_id FROM staging.sales_clean GROUP BY order_id HAVING COUNT(*) > 1) d;

INSERT INTO test_results
SELECT 'staging', 'T04 all quantity > 0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean WHERE quantity <= 0;

INSERT INTO test_results
SELECT 'staging', 'T05 all unit_price >= 0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean WHERE unit_price < 0;

INSERT INTO test_results
SELECT 'staging', 'T06 all discount in [0,1]',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean WHERE discount < 0 OR discount > 1;

INSERT INTO test_results
SELECT 'staging', 'T07 all branch_id lowercase',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean WHERE branch_id <> LOWER(branch_id);


INSERT INTO test_results
SELECT 'fact', 'F06b net = gross * (1 - discount)',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales
WHERE ABS(net_amount - ROUND(gross_amount * (1 - discount), 2)) > 0.01;

INSERT INTO test_results
SELECT 'fact', 'F06c cost = quantity * dim_product.unit_cost',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales f
JOIN warehouse.dim_product p ON f.product_key = p.product_key
WHERE f.cost_amount <> ROUND(f.quantity * p.unit_cost, 2);



INSERT INTO test_results
SELECT 'fact', 'F06d discount = 0 implies net = gross',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales
WHERE discount = 0 AND net_amount <> gross_amount;

INSERT INTO test_results
SELECT 'fact', 'F06e discount = 1 implies net = 0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales
WHERE discount = 1 AND net_amount <> 0;





INSERT INTO test_results
SELECT 'staging', 'T08 no orphan customer_id',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean s
LEFT JOIN staging.customers_clean c ON s.customer_id = c.customer_id
WHERE s.customer_id IS NOT NULL AND c.customer_id IS NULL;


INSERT INTO test_results
SELECT 'fact', 'F09 fact keys match staging order_ids',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM (
    SELECT order_id FROM staging.sales_clean
    EXCEPT
    SELECT order_id FROM warehouse.fact_sales
) d;


INSERT INTO test_results
SELECT 'staging', 'T09 no orphan product_id',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean s
LEFT JOIN staging.products_clean p ON s.product_id = p.product_id
WHERE p.product_id IS NULL;


INSERT INTO test_results
SELECT 'fact', 'F10 no duplicate order_id in fact (idempotency)',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM (
    SELECT order_id FROM warehouse.fact_sales
    GROUP BY order_id HAVING COUNT(*) > 1
) d;


INSERT INTO test_results
SELECT 'staging', 'T10 no orphan branch_id',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM staging.sales_clean s
LEFT JOIN staging.branches_clean b ON s.branch_id = b.branch_id
WHERE b.branch_id IS NULL;

-- ============================================================
-- Section 2: fact_sales
-- ============================================================
INSERT INTO test_results
SELECT 'fact', 'F01 row count matches staging sales_clean',
       CASE WHEN COUNT(*) = (SELECT COUNT(*) FROM staging.sales_clean)
            THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales;

INSERT INTO test_results
SELECT 'fact', 'F02 no orphan date_key',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales f
LEFT JOIN warehouse.dim_date d ON f.date_key = d.date_key
WHERE d.date_key IS NULL;

INSERT INTO test_results
SELECT 'fact', 'F03 no orphan customer_key',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales f
LEFT JOIN warehouse.dim_customer c ON f.customer_key = c.customer_key
WHERE c.customer_key IS NULL;

INSERT INTO test_results
SELECT 'fact', 'F04 no orphan product_key',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales f
LEFT JOIN warehouse.dim_product p ON f.product_key = p.product_key
WHERE p.product_key IS NULL;

INSERT INTO test_results
SELECT 'fact', 'F05 no orphan branch_key',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales f
LEFT JOIN warehouse.dim_branch b ON f.branch_key = b.branch_key
WHERE b.branch_key IS NULL;

INSERT INTO test_results
SELECT 'fact', 'F06 gross = quantity * unit_price',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales
WHERE gross_amount <> ROUND(quantity * unit_price, 2);

INSERT INTO test_results
SELECT 'fact', 'F07 profit = net - cost',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM warehouse.fact_sales
WHERE profit_amount <> ROUND(net_amount - cost_amount, 2);

INSERT INTO test_results
SELECT 'fact', 'F08 no duplicate order_id in fact',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text
FROM (SELECT order_id FROM warehouse.fact_sales GROUP BY order_id HAVING COUNT(*) > 1) d;

-- ============================================================
-- Print results by section
-- ============================================================
\echo '--- STAGING ---'
SELECT test_name, result, detail
FROM test_results WHERE section = 'staging'
ORDER BY test_name;

\echo ''
\echo '--- WAREHOUSE ---'
SELECT test_name, result, detail
FROM test_results WHERE section = 'fact'
ORDER BY test_name;

-- ============================================================
-- Final verdict
-- ============================================================
\echo ''
\echo '--- SUMMARY ---'
SELECT
    COUNT(*)                                       AS total_tests,
    COUNT(*) FILTER (WHERE result = 'PASS')        AS passed,
    COUNT(*) FILTER (WHERE result = 'FAIL')        AS failed,
    CASE
        WHEN COUNT(*) FILTER (WHERE result = 'FAIL') = 0
        THEN 'ALL PASS'
        ELSE 'FAIL'
    END                                            AS verdict
FROM test_results;

-- ============================================================
-- Fail the transaction (and psql exit code) if any test failed.
-- This ensures GitHub Actions marks the workflow as failed.
-- ============================================================
DO $$
DECLARE
    failed_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM pg_temp.test_results
    WHERE result = 'FAIL';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'MASTER TEST RUNNER FAILED: % test(s) failed', failed_count;
    END IF;
END $$;

DROP TABLE pg_temp.test_results;

