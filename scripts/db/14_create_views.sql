-- ============================================================
-- 14_create_views.sql
-- Analytical views for questions 5-8.
--
--   Q5. Sales growth vs. previous period (month-over-month + YoY)
--   Q6. Most profitable categories
--   Q7. Return rate per product
--   Q8. ETL quality report (corrections + rejections per load)
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/14_create_views.sql
-- ============================================================

-- ------------------------------------------------------------
-- Q5. Monthly growth vs. previous month and same month last year
-- Uses vw_monthly_sales as the base.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_monthly_growth AS
WITH base AS (
    SELECT
        year,
        month,
        month_name,
        net_revenue,
        profit,
        MAKE_DATE(year, month, 1) AS month_start
    FROM warehouse.vw_monthly_sales
)
SELECT
    year,
    month,
    month_name,
    net_revenue,
    LAG(net_revenue) OVER (ORDER BY month_start)              AS prev_month_revenue,
    ROUND(net_revenue - LAG(net_revenue) OVER (ORDER BY month_start), 2) AS mom_change,
    ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY month_start))
                 / NULLIF(LAG(net_revenue) OVER (ORDER BY month_start), 0), 2) AS mom_pct,
    LAG(net_revenue, 12) OVER (ORDER BY month_start)          AS same_month_last_year,
    ROUND(100.0 * (net_revenue - LAG(net_revenue, 12) OVER (ORDER BY month_start))
                 / NULLIF(LAG(net_revenue, 12) OVER (ORDER BY month_start), 0), 2) AS yoy_pct
FROM base
ORDER BY year, month;

GRANT SELECT ON warehouse.vw_monthly_growth TO analyst_user;

-- ------------------------------------------------------------
-- Q6. Most profitable categories
-- Aggregated by category from dim_product, with margin.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_profit_by_category AS
WITH agg AS (
    SELECT
        p.category,
        COUNT(*)                                    AS order_lines,
        SUM(f.quantity)                             AS units_sold,
        ROUND(SUM(f.net_amount), 2)                 AS net_revenue,
        ROUND(SUM(f.cost_amount), 2)                AS total_cost,
        ROUND(SUM(f.profit_amount), 2)              AS profit
    FROM warehouse.fact_sales f
    JOIN warehouse.dim_product p ON f.product_key = p.product_key
    GROUP BY p.category
)
SELECT
    RANK() OVER (ORDER BY profit DESC) AS profit_rank,
    category,
    order_lines,
    units_sold,
    net_revenue,
    total_cost,
    profit,
    ROUND(100.0 * profit / NULLIF(net_revenue, 0), 2) AS profit_margin_pct,
    ROUND(100.0 * profit / NULLIF(SUM(profit) OVER (), 0), 2) AS pct_of_total_profit
FROM agg
ORDER BY profit_rank;

GRANT SELECT ON warehouse.vw_profit_by_category TO analyst_user;

-- ------------------------------------------------------------
-- Q7. Return rate per product
-- Uses staging.returns_clean + staging.sales_clean (order_id join).
-- Orphan returns are excluded from the per-product rate but
-- counted in vw_return_overview below.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_return_rate_by_product AS
WITH product_sales AS (
    SELECT
        s.product_id,
        COUNT(*)                AS order_lines,
        SUM(s.quantity)         AS units_sold
    FROM staging.sales_clean s
    GROUP BY s.product_id
),
product_returns AS (
    SELECT
        s.product_id,
        COUNT(*)                AS returned_orders
    FROM staging.returns_clean r
    JOIN staging.sales_clean s ON r.order_id = s.order_id
    GROUP BY s.product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.category,
    ps.order_lines,
    ps.units_sold,
    COALESCE(pr.returned_orders, 0)                                    AS returned_orders,
    ROUND(100.0 * COALESCE(pr.returned_orders, 0) / NULLIF(ps.order_lines, 0), 2) AS return_rate_pct
FROM product_sales ps
JOIN warehouse.dim_product p ON ps.product_id = p.product_id
LEFT JOIN product_returns pr ON ps.product_id = pr.product_id
ORDER BY return_rate_pct DESC, returned_orders DESC;

GRANT SELECT ON warehouse.vw_return_rate_by_product TO analyst_user;

-- Companion: global return overview (incl. orphan returns)
CREATE OR REPLACE VIEW warehouse.vw_return_overview AS
SELECT
    (SELECT COUNT(*) FROM staging.sales_clean)      AS total_sales,
    (SELECT COUNT(*) FROM staging.returns_clean)    AS total_returns,
    (SELECT COUNT(*) FROM staging.orphan_returns)   AS orphan_returns,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM staging.returns_clean)
              / NULLIF((SELECT COUNT(*) FROM staging.sales_clean), 0), 2
    )                                                AS global_return_rate_pct;

GRANT SELECT ON warehouse.vw_return_overview TO analyst_user;

-- ------------------------------------------------------------
-- Q8. ETL quality report
-- Reads staging.etl_stats and exposes detection vs. catalog.
-- The detailed comparison lives in scripts/etl/quality_report.py;
-- this view provides the raw numbers for BI tools.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_etl_quality AS
WITH observed AS (
    SELECT
        'mixed_date_format'       AS error_type,
        (SELECT value FROM staging.etl_stats
         WHERE source_table='raw.sales_raw' AND metric='normalized_date') AS observed_count
    UNION ALL
    SELECT 'missing_customer_id',
        (SELECT value FROM staging.etl_stats
         WHERE source_table='raw.sales_raw' AND metric='nulled_customer_id')
    UNION ALL
    SELECT 'dirty_branch_id',
        (SELECT value FROM staging.etl_stats
         WHERE source_table='raw.sales_raw' AND metric='normalized_branch_id')
    UNION ALL
    SELECT 'negative_quantity',
        (SELECT value FROM staging.etl_stats
         WHERE source_table='raw.sales_raw' AND metric='rejected_negative_quantity')
    UNION ALL
    SELECT 'missing_discount',
        (SELECT value FROM staging.etl_stats
         WHERE source_table='raw.sales_raw' AND metric='normalized_discount')
    UNION ALL
    SELECT 'duplicate_row',
        (SELECT value FROM staging.etl_stats
         WHERE source_table='raw.sales_raw' AND metric='duplicates_removed')
)
SELECT
    c.error_type,
    c.injected_count::int                AS expected,
    o.observed_count                     AS observed,
    (o.observed_count = c.injected_count::int) AS match
FROM raw.error_catalog_raw c
JOIN observed o ON c.error_type = o.error_type
ORDER BY c.error_type;

GRANT SELECT ON warehouse.vw_etl_quality TO analyst_user;

-- ============================================================
-- Verify
-- ============================================================
\echo ''
\echo '=== Q5 sample: latest 5 months with growth ==='
SELECT year, month, month_name, net_revenue, mom_pct, yoy_pct
FROM warehouse.vw_monthly_growth
ORDER BY year DESC, month DESC
LIMIT 5;

\echo ''
\echo '=== Q6: profit by category ==='
SELECT * FROM warehouse.vw_profit_by_category;

\echo ''
\echo '=== Q7 sample: top 5 products by return rate (min 10 orders) ==='
SELECT product_id, product_name, order_lines, returned_orders, return_rate_pct
FROM warehouse.vw_return_rate_by_product
WHERE order_lines >= 10
ORDER BY return_rate_pct DESC
LIMIT 5;

\echo ''
\echo '=== Q7 overview ==='
SELECT * FROM warehouse.vw_return_overview;

\echo ''
\echo '=== Q8: ETL quality ==='
SELECT * FROM warehouse.vw_etl_quality;
