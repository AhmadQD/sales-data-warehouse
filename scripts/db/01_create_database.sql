-- ============================================================
-- 01_create_database.sql
-- Creates the sales_dw database and its three schemas.
--
-- Part 1 of 2. Run this FIRST, connected to the default database:
-- psql -U postgres -f scripts/db/01_create_database.sql
--
-- Then run 02_roles_and_grants.sql connected to sales_dw.
-- ============================================================

-- 1. Database
-- CREATE DATABASE cannot run inside a transaction block,
-- and cannot be executed while connected to the target DB.
CREATE DATABASE sales_dw;

-- 2. Connect to the new database before creating schemas:
-- \c sales_dw
--
-- (Left as a manual step so this script can also be run from psql
-- interactively without losing the session.)

-- 3. Schemas (layered architecture)
CREATE SCHEMA raw; -- landing zone: source data as-is
CREATE SCHEMA staging; -- cleaned / validated data
CREATE SCHEMA warehouse; -- final star schema (serving layer)