-- ============================================================
-- 01_create_database.sql
-- Creates the sales_dw database and its three schemas.
--
-- Run connected to the default database:
--   psql -U postgres -f scripts/db/01_create_database.sql
--
-- Then run 02_roles_and_grants.sql connected to sales_dw.
-- ============================================================

-- 1. Create the database
CREATE DATABASE sales_dw;

-- 2. Connect to it before creating schemas
\c sales_dw

-- 3. Schemas (layered architecture)
CREATE SCHEMA raw;        -- landing zone: source data as-is
CREATE SCHEMA staging;    -- cleaned / validated data
CREATE SCHEMA warehouse;  -- final star schema (serving layer)
