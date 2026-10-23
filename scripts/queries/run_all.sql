-- ============================================================
-- run_all.sql
-- Runs all eight analytical questions and prints the results.
--
-- Run connected to sales_dw (as analyst_user or postgres):
--   psql -U analyst_user -d sales_dw -f scripts/queries/run_all.sql
-- ============================================================

\echo ''
\echo '============================================================'
\echo '  ANALYTICAL QUESTIONS — sales-data-warehouse'
\echo '============================================================'

-- ------------------------------------------------------------
\echo ''
\echo '=== Q1. Monthly & yearly total sales (latest 12 months) ==='
SELECT year, month, month_name, order_lines, net_revenue, profit
FROM warehouse.vw_monthly_sales
ORDER BY year DESC, month DESC
LIMIT 12;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q2a. Top 10 products by net revenue ==='
SELECT revenue_rank, product_id, product_name, category,
       units_sold, net_revenue, profit, pct_of_total_revenue
FROM warehouse.vw_product_performance
WHERE revenue_rank <= 10
ORDER BY revenue_rank;

\echo ''
\echo '=== Q2b. Bottom 10 products by net revenue ==='
SELECT revenue_rank, product_id, product_name, category,
       units_sold, net_revenue, profit
FROM warehouse.vw_product_performance
ORDER BY revenue_rank DESC
LIMIT 10;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q3. Branch performance vs. average ==='
SELECT revenue_rank, branch_name, city, net_revenue,
       diff_from_avg, pct_vs_avg
FROM warehouse.vw_branch_performance
ORDER BY revenue_rank;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q4. Top 10 customers by purchase ==='
SELECT revenue_rank, customer_id, name, city,
       order_lines, net_revenue, profit
FROM warehouse.vw_top_customers
WHERE revenue_rank <= 10
ORDER BY revenue_rank;

\echo ''
\echo '--- (companion) Unknown-customer sales ---'
SELECT * FROM warehouse.vw_unknown_sales;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q5. Sales growth: MoM and YoY (latest 12 months) ==='
SELECT year, month, month_name, net_revenue, mom_pct, yoy_pct
FROM warehouse.vw_monthly_growth
ORDER BY year DESC, month DESC
LIMIT 12;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q6. Most profitable categories ==='
SELECT profit_rank, category, order_lines, net_revenue, profit,
       profit_margin_pct, pct_of_total_profit
FROM warehouse.vw_profit_by_category
ORDER BY profit_rank;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q7a. Return rate by product (top 10, min 10 orders) ==='
SELECT product_id, product_name, category,
       order_lines, returned_orders, return_rate_pct
FROM warehouse.vw_return_rate_by_product
WHERE order_lines >= 10
ORDER BY return_rate_pct DESC
LIMIT 10;

\echo ''
\echo '=== Q7b. Return overview ==='
SELECT * FROM warehouse.vw_return_overview;

-- ------------------------------------------------------------
\echo ''
\echo '=== Q8. ETL quality (detection vs. catalog) ==='
SELECT * FROM warehouse.vw_etl_quality;

-- ------------------------------------------------------------
\echo ''
\echo '============================================================'
\echo '  END'
\echo '============================================================'
