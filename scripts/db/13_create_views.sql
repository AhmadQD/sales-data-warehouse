-- ============================================================
-- 13_create_views.sql
-- Analytical views for questions 1-4.
--
--   Q1. Monthly & yearly total sales
--   Q2. Top 10 / bottom 10 products
--   Q3. Branch performance vs. each other
--   Q4. Top customers by purchase
--
-- Views live in warehouse and are granted to analyst_user.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/13_create_views.sql
-- ============================================================

-- ------------------------------------------------------------
-- Q1. Monthly & yearly total sales
-- One row per (year, month). Includes month_name and revenue.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_monthly_sales AS
SELECT
    d.year,
    d.month,
    d.month_name,
    COUNT(*)                              AS order_lines,
    SUM(f.quantity)                       AS total_quantity,
    ROUND(SUM(f.gross_amount), 2)         AS gross_revenue,
    ROUND(SUM(f.net_amount), 2)           AS net_revenue,
    ROUND(SUM(f.profit_amount), 2)        AS profit
FROM warehouse.fact_sales f
JOIN warehouse.dim_date   d ON f.date_key = d.date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;

GRANT SELECT ON warehouse.vw_monthly_sales TO analyst_user;

-- ------------------------------------------------------------
-- Q2. Top / bottom products
-- Ranked by net revenue. Consumers filter rank <= 10 or
-- rank > (total - 10) to get top/bottom 10.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_product_performance AS
WITH agg AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category,
        COUNT(*)                          AS order_lines,
        SUM(f.quantity)                   AS units_sold,
        ROUND(SUM(f.net_amount), 2)       AS net_revenue,
        ROUND(SUM(f.profit_amount), 2)    AS profit
    FROM warehouse.fact_sales f
    JOIN warehouse.dim_product p ON f.product_key = p.product_key
    GROUP BY p.product_id, p.product_name, p.category
)
SELECT
    RANK() OVER (ORDER BY net_revenue DESC) AS revenue_rank,
    product_id,
    product_name,
    category,
    order_lines,
    units_sold,
    net_revenue,
    profit,
    ROUND(100.0 * net_revenue
          / NULLIF(SUM(net_revenue) OVER (), 0), 2) AS pct_of_total_revenue
FROM agg
ORDER BY revenue_rank;

GRANT SELECT ON warehouse.vw_product_performance TO analyst_user;

-- ------------------------------------------------------------
-- Q3. Branch performance compared to each other
-- Includes each branch's revenue, the overall average, and
-- the difference from that average.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_branch_performance AS
WITH per_branch AS (
    SELECT
        b.branch_id,
        b.branch_name,
        b.city,
        COUNT(*)                          AS order_lines,
        ROUND(SUM(f.net_amount), 2)       AS net_revenue,
        ROUND(SUM(f.profit_amount), 2)    AS profit
    FROM warehouse.fact_sales f
    JOIN warehouse.dim_branch b ON f.branch_key = b.branch_key
    GROUP BY b.branch_id, b.branch_name, b.city
)
SELECT
    RANK() OVER (ORDER BY net_revenue DESC)         AS revenue_rank,
    branch_id,
    branch_name,
    city,
    order_lines,
    net_revenue,
    profit,
    ROUND(AVG(net_revenue) OVER (), 2)              AS avg_branch_revenue,
    ROUND(net_revenue - AVG(net_revenue) OVER (), 2) AS diff_from_avg,
    ROUND(100.0 * (net_revenue - AVG(net_revenue) OVER ())
                 / NULLIF(AVG(net_revenue) OVER (), 0), 2) AS pct_vs_avg
FROM per_branch
ORDER BY revenue_rank;

GRANT SELECT ON warehouse.vw_branch_performance TO analyst_user;

-- ------------------------------------------------------------
-- Q4. Top customers by purchase
-- Ranked by net revenue. Unknown customer is included (as a
-- signal, not an error — it reflects rows with missing id).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW warehouse.vw_top_customers AS
WITH agg AS (
    SELECT
        c.customer_id,
        c.name,
        c.city,
        COUNT(*)                          AS order_lines,
        SUM(f.quantity)                   AS units_bought,
        ROUND(SUM(f.net_amount), 2)       AS net_revenue,
        ROUND(SUM(f.profit_amount), 2)    AS profit
    FROM warehouse.fact_sales f
    JOIN warehouse.dim_customer c ON f.customer_key = c.customer_key
    WHERE c.customer_key <> 0
    GROUP BY c.customer_id, c.name, c.city
)
SELECT
    RANK() OVER (ORDER BY net_revenue DESC) AS revenue_rank,
    customer_id,
    name,
    city,
    order_lines,
    units_bought,
    net_revenue,
    profit
FROM agg
ORDER BY revenue_rank;

GRANT SELECT ON warehouse.vw_top_customers TO analyst_user;

-- Companion view: unknown-customer sales (for transparency)
CREATE OR REPLACE VIEW warehouse.vw_unknown_sales AS
SELECT
    COUNT(*)                          AS order_lines,
    SUM(f.quantity)                   AS units_sold,
    ROUND(SUM(f.gross_amount), 2)     AS gross_revenue,
    ROUND(SUM(f.net_amount), 2)       AS net_revenue,
    ROUND(SUM(f.profit_amount), 2)    AS profit
FROM warehouse.fact_sales f
JOIN warehouse.dim_customer c ON f.customer_key = c.customer_key
WHERE c.customer_key = 0;

GRANT SELECT ON warehouse.vw_unknown_sales TO analyst_user;
-- ============================================================
-- Verify
-- ============================================================
\echo ''
\echo '=== Q1 sample: monthly sales (first 3 months) ==='
SELECT * FROM warehouse.vw_monthly_sales ORDER BY year, month LIMIT 3;

\echo ''
\echo '=== Q2 sample: top 5 products by revenue ==='
SELECT * FROM warehouse.vw_product_performance WHERE revenue_rank <= 5;

\echo ''
\echo '=== Q3: all branches ==='
SELECT * FROM warehouse.vw_branch_performance;

\echo ''
\echo '=== Q4 sample: top 5 customers ==='
SELECT * FROM warehouse.vw_top_customers WHERE revenue_rank <= 5;
