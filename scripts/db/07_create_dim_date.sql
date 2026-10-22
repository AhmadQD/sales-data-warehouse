-- ============================================================
-- 07_create_dim_date.sql
-- Creates and populates warehouse.dim_date.
--
-- Date range: 2020-01-01 to 2030-12-31 (covers all source data).
-- date_key format: YYYYMMDD (integer) — sorts naturally, fast joins.
--
-- Run connected to sales_dw:
--   psql -U postgres -d sales_dw -f scripts/db/07_create_dim_date.sql
-- ============================================================

CREATE TABLE warehouse.dim_date (
    date_key     INTEGER PRIMARY KEY,
    full_date    DATE     NOT NULL UNIQUE,
    year         SMALLINT NOT NULL,
    quarter      SMALLINT NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month        SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
    month_name   TEXT     NOT NULL,
    day          SMALLINT NOT NULL CHECK (day BETWEEN 1 AND 31),
    day_of_week  SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    is_weekend   BOOLEAN  NOT NULL
);

-- Populate the date dimension for 11 years.
INSERT INTO warehouse.dim_date
SELECT
    (EXTRACT(YEAR  FROM d)::int * 10000
   + EXTRACT(MONTH FROM d)::int * 100
   + EXTRACT(DAY   FROM d)::int)                 AS date_key,
    d::date                                      AS full_date,
    EXTRACT(YEAR    FROM d)::smallint            AS year,
    EXTRACT(QUARTER FROM d)::smallint            AS quarter,
    EXTRACT(MONTH   FROM d)::smallint            AS month,
    TO_CHAR(d, 'FMMonth')                        AS month_name,
    EXTRACT(DAY     FROM d)::smallint            AS day,
    EXTRACT(DOW     FROM d)::smallint            AS day_of_week,  -- 0=Sun, 6=Sat
    EXTRACT(DOW     FROM d) IN (0, 6)            AS is_weekend
FROM generate_series(
        DATE '2020-01-01',
        DATE '2030-12-31',
        INTERVAL '1 day'
     ) AS d;

-- Ownership and grants
ALTER TABLE warehouse.dim_date OWNER TO etl_user;

-- Analyst can read it
GRANT SELECT ON warehouse.dim_date TO analyst_user;

-- ============================================================
-- Verify
-- ============================================================
\echo ''
\echo '=== dim_date populated ==='
SELECT
    COUNT(*)                       AS rows_total,
    MIN(full_date)                 AS first_date,
    MAX(full_date)                 AS last_date,
    COUNT(*) FILTER (WHERE is_weekend)  AS weekend_days,
    COUNT(*) FILTER (WHERE NOT is_weekend) AS weekday_days
FROM warehouse.dim_date;

\echo ''
\echo '=== Sample rows ==='
SELECT * FROM warehouse.dim_date
WHERE full_date IN ('2023-01-01', '2024-06-15', '2025-12-31')
ORDER BY full_date;
