-- ============================================================
-- 02_roles_and_grants.sql
-- Creates three roles and applies least-privilege grants.
--
-- Part 2 of 2. Run this AFTER 01_create_database.sql, connected to sales_dw:
-- psql -U postgres -d sales_dw -f scripts/db/02_roles_and_grants.sql
--
-- NOTE: passwords below are for LOCAL DEVELOPMENT ONLY.
-- Do not reuse them in any real deployment.
-- ============================================================

-- 1. Roles
CREATE ROLE etl_user WITH LOGIN PASSWORD 'etl_secret_2024';
CREATE ROLE analyst_user WITH LOGIN PASSWORD 'analyst_secret_2024';
CREATE ROLE dba_admin WITH LOGIN PASSWORD 'dba_secret_2024' SUPERUSER;

-- 2. Grants: ETL writes to all three layers
GRANT USAGE, CREATE ON SCHEMA raw TO etl_user;
GRANT USAGE, CREATE ON SCHEMA staging TO etl_user;
GRANT USAGE, CREATE ON SCHEMA warehouse TO etl_user;

-- 3. Grants: Analyst reads ONLY from warehouse
GRANT USAGE ON SCHEMA warehouse TO analyst_user;
GRANT SELECT ON ALL TABLES IN SCHEMA warehouse TO analyst_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA warehouse
GRANT SELECT ON TABLES TO analyst_user;

-- 4. Default privileges for ETL on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL ON TABLES TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT ALL ON TABLES TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA warehouse GRANT ALL ON TABLES TO etl_user;

-- 5. Hard isolation: analyst must NOT see raw or staging
REVOKE ALL ON SCHEMA raw FROM analyst_user;
REVOKE ALL ON SCHEMA staging FROM analyst_user;
REVOKE ALL ON SCHEMA public FROM analyst_user;