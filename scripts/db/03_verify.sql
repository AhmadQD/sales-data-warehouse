-- ============================================================
-- 03_verify.sql
-- Read-only verification of the database setup.
-- Run connected to sales_dw:
-- psql -U postgres -d sales_dw -f scripts/db/03_verify.sql
--
-- Expected: 4 schemas, 4 roles, analyst_user denied on raw/staging.
-- ============================================================

\echo '=== 1. Schemas ==='
\dn+

\echo ''
\echo '=== 2. Roles ==='
\du

\echo ''
\echo '=== 3. Database encoding and collation ==='
SELECT datname, pg_encoding_to_char(encoding) AS encoding, datcollate
FROM pg_database
WHERE datname = 'sales_dw';

\echo ''
\echo '=== 4. Access privileges on schemas ==='
SELECT nspname AS schema,
nspacl AS access_privileges
FROM pg_namespace
WHERE nspname IN ('raw', 'staging', 'warehouse')
ORDER BY nspname;