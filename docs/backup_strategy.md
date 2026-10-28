# Backup Strategy — sales-data-warehouse



## Restore Test — 2026-10-23

A full restore was performed to validate the backup:

1. Created `sales_dw_restore_test` database.
2. `pg_restore --clean --if-exists` from `backups/sales_dw_2026-10-23_00-03-57.dump`.
3. Applied roles from `backups/roles_2026-10-23_00-03-57.sql`.
4. Ran `scripts/db/12_master_test_runner.sql`.

**Result: 24/24 tests PASS.** The dump contains 99,570 rows in
`fact_sales` (matches source at backup time). The restored database
is indistinguishable from the original in behavior.

Note: `role already exists` warnings during role restore are expected
when restoring into the same PostgreSQL cluster (roles are cluster-level,
not database-level). For a true disaster-recovery drill, restore on a
fresh cluster.





## Current Implementation

| Aspect | Value |
|---|---|
| Tool | `pg_dump -Fc` + `pg_dumpall --roles-only` |
| Location | `backups/` (gitignored, never committed) |
| Frequency | Manual (`bash scripts/backup/backup.sh`) |
| Size | ~6 MB per dump |
| Retention | 7 most recent dumps |
| Verification | `pg_restore --list` after each dump |

## Why `-Fc` (custom format)

- Compressed (~4x smaller than plain SQL).
- Selective restore (single table/schema).
- Verified via `pg_restore --list`.

## Why roles are separate

`pg_dump` does not capture roles (they are cluster-level). Tables are
owned by `etl_user`, so a restore without roles would fail.
`pg_dumpall --roles-only` fills this gap.

## Restore Procedure

```bash
psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='sales_dw';"
psql -U postgres -c "DROP DATABASE sales_dw;"
psql -U postgres -c "CREATE DATABASE sales_dw;"
psql -U postgres -f backups/roles_<timestamp>.sql
pg_restore -U postgres -d sales_dw --clean --if-exists backups/sales_dw_<timestamp>.dump
psql -U postgres -d sales_dw -f scripts/db/12_master_test_runner.sql


