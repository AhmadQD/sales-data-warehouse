-- ============================================================
-- 08_create_warehouse_dims.sql
-- Creates the warehouse dimension tables:
--   warehouse.dim_customer, warehouse.dim_product, warehouse.dim_branch
--
-- Design notes:
--   * Surrogate keys (BIGSERIAL) — decoupled from source.
--   * Natural keys kept as UNIQUE columns — traceability.
--   * SCD Type 2 scaffolding (valid_from, valid_to, is_current)
--     with a single current row per entity (SCD Type 1 behavior).
--   * An "Unknown" row (key = 0) is inserted in each dimension
--     so fact rows never have a dangling foreign key.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/08_create_warehouse_dims.sql
-- ============================================================

-- ---------------------------------------------------------
-- dim_customer
-- ---------------------------------------------------------
CREATE TABLE warehouse.dim_customer (
    customer_key  BIGSERIAL    PRIMARY KEY,
    customer_id   TEXT         NOT NULL UNIQUE,
    name          TEXT         NOT NULL,
    city          TEXT,
    valid_from    TIMESTAMP    NOT NULL DEFAULT NOW(),
    valid_to      TIMESTAMP    NOT NULL DEFAULT '9999-12-31',
    is_current    BOOLEAN      NOT NULL DEFAULT TRUE
);

INSERT INTO warehouse.dim_customer
    (customer_key, customer_id, name, city, valid_from, valid_to, is_current)
VALUES
    (0, 'UNKNOWN', 'Unknown Customer', NULL, '1900-01-01', '9999-12-31', TRUE);

-- ---------------------------------------------------------
-- dim_product
-- ---------------------------------------------------------
CREATE TABLE warehouse.dim_product (
    product_key   BIGSERIAL     PRIMARY KEY,
    product_id    TEXT          NOT NULL UNIQUE,
    product_name  TEXT          NOT NULL,
    category      TEXT          NOT NULL,
    unit_cost     NUMERIC(10,2) NOT NULL,
    valid_from    TIMESTAMP     NOT NULL DEFAULT NOW(),
    valid_to      TIMESTAMP     NOT NULL DEFAULT '9999-12-31',
    is_current    BOOLEAN       NOT NULL DEFAULT TRUE
);

INSERT INTO warehouse.dim_product
    (product_key, product_id, product_name, category, unit_cost,
     valid_from, valid_to, is_current)
VALUES
    (0, 'UNKNOWN', 'Unknown Product', 'Unknown', 0,
     '1900-01-01', '9999-12-31', TRUE);

-- ---------------------------------------------------------
-- dim_branch
-- ---------------------------------------------------------
CREATE TABLE warehouse.dim_branch (
    branch_key    BIGSERIAL    PRIMARY KEY,
    branch_id     TEXT         NOT NULL UNIQUE,
    branch_name   TEXT         NOT NULL,
    city          TEXT,
    valid_from    TIMESTAMP    NOT NULL DEFAULT NOW(),
    valid_to      TIMESTAMP    NOT NULL DEFAULT '9999-12-31',
    is_current    BOOLEAN      NOT NULL DEFAULT TRUE
);

INSERT INTO warehouse.dim_branch
    (branch_key, branch_id, branch_name, city, valid_from, valid_to, is_current)
VALUES
    (0, 'UNKNOWN', 'Unknown Branch', NULL, '1900-01-01', '9999-12-31', TRUE);

-- ---------------------------------------------------------
-- Ownership and grants
-- ---------------------------------------------------------
ALTER TABLE warehouse.dim_customer OWNER TO etl_user;
ALTER TABLE warehouse.dim_product  OWNER TO etl_user;
ALTER TABLE warehouse.dim_branch   OWNER TO etl_user;

GRANT SELECT ON warehouse.dim_customer TO analyst_user;
GRANT SELECT ON warehouse.dim_product  TO analyst_user;
GRANT SELECT ON warehouse.dim_branch   TO analyst_user;

-- Sequences (BIGSERIAL)
GRANT USAGE, SELECT ON SEQUENCE warehouse.dim_customer_customer_key_seq TO etl_user;
GRANT USAGE, SELECT ON SEQUENCE warehouse.dim_product_product_key_seq   TO etl_user;
GRANT USAGE, SELECT ON SEQUENCE warehouse.dim_branch_branch_key_seq     TO etl_user;

-- ============================================================
-- Verify
-- ============================================================
\echo ''
\echo '=== Warehouse dimensions created ==='
SELECT 'dim_customer' AS table_name, COUNT(*) FROM warehouse.dim_customer
UNION ALL
SELECT 'dim_product', COUNT(*) FROM warehouse.dim_product
UNION ALL
SELECT 'dim_branch', COUNT(*) FROM warehouse.dim_branch;

\echo ''
\echo '=== Unknown members ==='
SELECT customer_key, customer_id, name FROM warehouse.dim_customer WHERE customer_key = 0;
SELECT product_key,  product_id,  product_name FROM warehouse.dim_product  WHERE product_key = 0;
SELECT branch_key,   branch_id,   branch_name  FROM warehouse.dim_branch   WHERE branch_key = 0;
