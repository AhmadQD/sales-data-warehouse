-- ============================================================
-- 09_create_fact_sales.sql
-- Creates warehouse.fact_sales (star schema fact table).
--
-- Grain: one row per sales line (order_id).
--
-- Design notes:
--   * order_id is a degenerate dimension (needed to link returns).
--   * Foreign keys to all four dimensions (enforced).
--   * Measures: quantity, unit_price, discount,
--              gross_amount, net_amount, cost_amount, profit_amount.
--   * Amounts are precomputed at load time (snapshot semantics) so
--     historical reports are reproducible even if dim_product changes.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/09_create_fact_sales.sql
-- ============================================================

CREATE TABLE warehouse.fact_sales (
    sales_key      BIGSERIAL     PRIMARY KEY,
    order_id       TEXT          NOT NULL,           -- degenerate dimension
    date_key       INTEGER       NOT NULL REFERENCES warehouse.dim_date(date_key),
    customer_key   BIGINT        NOT NULL REFERENCES warehouse.dim_customer(customer_key),
    product_key    BIGINT        NOT NULL REFERENCES warehouse.dim_product(product_key),
    branch_key     BIGINT        NOT NULL REFERENCES warehouse.dim_branch(branch_key),
    quantity       INTEGER       NOT NULL CHECK (quantity > 0),
    unit_price     NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount       NUMERIC(5,4)  NOT NULL CHECK (discount BETWEEN 0 AND 1),
    gross_amount   NUMERIC(12,2) NOT NULL,
    net_amount     NUMERIC(12,2) NOT NULL,
    cost_amount    NUMERIC(12,2) NOT NULL,
    profit_amount  NUMERIC(12,2) NOT NULL
);

-- Indexes for query patterns
CREATE INDEX idx_fact_sales_date     ON warehouse.fact_sales(date_key);
CREATE INDEX idx_fact_sales_customer ON warehouse.fact_sales(customer_key);
CREATE INDEX idx_fact_sales_product  ON warehouse.fact_sales(product_key);
CREATE INDEX idx_fact_sales_branch   ON warehouse.fact_sales(branch_key);
CREATE INDEX idx_fact_sales_order    ON warehouse.fact_sales(order_id);

-- Ownership and grants
ALTER TABLE warehouse.fact_sales OWNER TO etl_user;
GRANT SELECT ON warehouse.fact_sales TO analyst_user;
GRANT USAGE, SELECT ON SEQUENCE warehouse.fact_sales_sales_key_seq TO etl_user;

-- ============================================================
-- Verify
-- ============================================================
\echo ''
\echo '=== fact_sales created ==='
SELECT COUNT(*) AS rows_now FROM warehouse.fact_sales;
