# ETL & Design Decisions — sales-data-warehouse

This document records every non-trivial design decision, the reasoning
behind it, and the alternative(s) that were rejected. It exists so a
future maintainer (or interviewer) can understand *why* the warehouse
looks the way it does.

---

## 1. Layered Architecture: `raw` → `staging` → `warehouse`

**Decision**: Three PostgreSQL schemas, each with a single responsibility.

**Why**:
- **`raw`** is a *snapshot of the source*. No parsing, no validation,
  no deduplication. Everything is `TEXT`. This preserves data lineage
  and makes the pipeline re-runnable from the source of truth.
- **`staging`** is where cleaning, typing, and validation happen.
  This is the only layer that reads `raw` and the only layer that
  `warehouse` reads from.
- **`warehouse`** is the serving layer (star schema). It never reads
  `raw` directly.

**Rejected alternative**: A single schema with cleaning done in Python
before `INSERT`. Rejected because:
- Loses traceability (no way to answer "what did the source look like?").
- Makes re-processing dependent on the source file still being present.
- Fails the "audit log" requirement of question 8.

---

## 2. Raw layer uses `TEXT` for every column

**Decision**: Every source column lands in `raw` as `TEXT`, with a
`_row_id`, `_loaded_at`, and `_source_file` for lineage.

**Why**:
- A `DATE` column would reject the 3,000 `mixed_date_format` rows at
  load time, losing them before we can measure them.
- `INTEGER` for `quantity` would silently accept negatives; we want to
  reject them explicitly in `staging` so they appear in `rejected_rows`.
- Keeping everything as `TEXT` means "the raw layer never rejects a row
  due to type coercion" — the only rejections in `raw` are structural
  (e.g. a file with a missing column).

**Rejected alternative**: Typed columns in `raw`. Rejected because it
defeats the purpose of a landing zone.

---

## 3. Reject `negative_quantity` instead of correcting it

**Decision**: 500 rows with `quantity <= 0` are moved to
`staging.rejected_rows` with an explicit reason.

**Why**:
- A negative quantity in a sales line is **ambiguous**: it could be an
  input error (`-5` instead of `5`) or an unrecorded return.
- Correcting it to `ABS(quantity)` would fabricate sales that never
  happened and inflate revenue.
- Rejecting preserves the row for a human review, without corrupting
  the fact table.

**Rejected alternatives**:
- `ABS(quantity)`: fabricates data. Rejected.
- `quantity = 0`: loses the transaction entirely and silently. Rejected.
- Setting `quantity = NULL`: breaks the `CHECK (quantity > 0)` invariant
  and requires a nullable column in the fact table. Rejected.

---

## 4. Keep `missing_customer_id` rows (map to Unknown member)

**Decision**: 1,000 rows with an empty `customer_id` are kept in
`staging.sales_clean` with `customer_id = NULL`, and mapped to
`customer_key = 0` in `warehouse.fact_sales`.

**Why**:
- Rejecting them would discard real sales (≈305,000 in revenue).
- Keeping them with an `Unknown` member allows reporting to include
  them while flagging them for follow-up.
- A companion view (`vw_unknown_sales`) reports their volume, so the
  business can act on them without them distorting the top-customer
  ranking.

**Rejected alternative**: Reject the rows. Rejected because the loss
of revenue is unacceptable for a sales warehouse.

---

## 5. Correct `mixed_date_format` instead of rejecting

**Decision**: 3,000 rows with `DD/MM/YYYY` are converted to `DATE`
and kept.

**Why**:
- The format is unambiguous (both `YYYY-MM-DD` and `DD/MM/YYYY` are
  present in the file, and no row has a day > 12 in the `DD/MM` part,
  so there is no ambiguity between `DD/MM` and `MM/DD`).
- The row's business content (quantity, price, etc.) is valid.
- Rejecting would lose 3,000 valid sales for a cosmetic issue.

**Rejected alternative**: Strict ISO-8601 only. Rejected because it
would discard rows that are recoverable without loss.

---

## 6. Normalize `branch_id` (trim + lower)

**Decision**: 2,000 rows with `branch_id` such as `"b01 "` or `"B01"`
are normalized to `"b01"`.

**Why**:
- The source uses mixed case and trailing spaces, but the value is
  semantically identical.
- Rejecting would lose 2,000 valid sales for a formatting issue.

**Rejected alternative**: Reject. Rejected because the transformation
is lossless.

---

## 7. Deduplicate `sales` on all business columns

**Decision**: 1,000 exact-duplicate rows are removed (keeping the
first by `_row_id`).

**Why**:
- The duplicates are byte-for-byte identical (same `order_id`, date,
  branch, customer, product, quantity, price, discount).
- A single `order_id` must produce a single fact row; otherwise
  revenue is double-counted.

**Rejected alternatives**:
- Keep both: inflates revenue. Rejected.
- Aggregate them: nonsense for a sales fact. Rejected.

---

## 8. Date dimension uses `YYYYMMDD` integer key

**Decision**: `date_key` is an `INTEGER` in `YYYYMMDD` format
(e.g. `20240115`).

**Why**:
- Sorts naturally (`20240115 > 20231231`) without conversion.
- Fast joins and indexes (small integer).
- Readable in queries (`WHERE date_key BETWEEN 20240101 AND 20241231`).

**Rejected alternative**: `DATE` as primary key. Rejected because
integers index faster and `date_key` is a standard DWH convention.

---

## 9. Profit is precomputed and stored

**Decision**: `fact_sales` stores `gross_amount`, `net_amount`,
`cost_amount`, and `profit_amount` as separate columns.

**Why**:
- `unit_cost` lives in `dim_product` and may change over time.
  Snapshotting it into `fact_sales.cost_amount` preserves the
  historical value used in that sale.
- Keeping all four measures allows audit (a consumer can recompute and
  compare).
- Query performance: no need to join `dim_product` on every profit
  query.

**Rejected alternative**: Compute profit on the fly in each query.
Rejected because it produces wrong historical figures if `unit_cost`
changes and it prevents audit.

---

## 10. SCD Type 2 scaffolding, but SCD Type 1 behavior

**Decision**: `dim_customer`, `dim_product`, and `dim_branch` have
`valid_from`, `valid_to`, `is_current` columns, but only one row per
entity (with `is_current = TRUE`).

**Why**:
- The source data has no change history, so a real SCD Type 2 would be
  fabricated.
- Keeping the columns means the model is *ready* for Type 2 without a
  schema migration later.
- The current behavior is Type 1 (overwrite), documented explicitly.

**Rejected alternative**: Drop the SCD columns entirely. Rejected
because it would hide the intent and require a schema change later.

---

## 11. Unknown member (key = 0) in every dimension

**Decision**: Each dimension has a row with key `0` and
`<name> = 'UNKNOWN'`.

**Why**:
- Fact rows with no matching dimension member (e.g. missing
  `customer_id`) must not be dropped.
- Foreign keys in `fact_sales` are enforced (`NOT NULL`), so the
  Unknown member guarantees every fact row has a valid reference.
- Reporting can filter `customer_key = 0` to exclude unknowns, or
  include them explicitly via `vw_unknown_sales`.

**Rejected alternative**: Allow `NULL` foreign keys. Rejected because
it complicates every join and hides data quality issues.

---

## 12. Incremental loading with a watermark table

**Decision**: `warehouse.etl_watermark` stores the last `order_id`
loaded per pipeline. Each run processes only rows with
`order_id > last_loaded_key`.

**Why**:
- Full reload (`TRUNCATE + INSERT`) is fine for 100k rows but not for
  millions.
- The watermark makes the pipeline **incremental** and **idempotent**.
- The watermark is updated in the same transaction as the inserts, so a
  crash mid-run does not advance the cursor.

**Rejected alternatives**:
- `order_date` watermark: rejected because two runs on the same day
  with new rows would be missed.
- `_row_id` watermark: rejected because `raw` is reloaded (TRUNCATE
  ... RESTART IDENTITY), which changes `_row_id`s.
- Surrogate key (`sales_key`) watermark: rejected for the same reason.

**Known limitation**: `order_id` is assumed to be monotonically
increasing. In a real source, this must be verified. If not true, the
pipeline should switch to a `(created_at, id)` composite watermark.

---

## 13. `etl_runs` (append-only) instead of `etl_stats` (snapshot)

**Decision**: Every ETL run is appended to `staging.etl_runs`. The
earlier `staging.etl_stats` was a snapshot that was `DELETE`d before
every run.

**Why**:
- Question 8 ("how many records were corrected or rejected in each
  load?") requires a *history*, not a snapshot.
- An append-only log also serves as an audit trail for SOC 2 / GDPR
  style reviews.
- `vw_etl_quality` reads the latest row from `etl_runs`.

**Rejected alternative**: Keep `etl_stats` as a snapshot. Rejected
because it cannot answer question 8 after a second run.

---

## 14. Orphan returns are kept, not rejected

**Decision**: 16 returns whose `order_id` is not in `sales_clean`
are kept in `staging.returns_clean` and recorded in
`staging.orphan_returns`.

**Why**:
- A return is a real business event, even if the original sale is
  missing (it may be in a source we have not ingested yet, or was in
  the 500 rejected negative-quantity rows).
- Rejecting them would lose data that will become linkable once the
  source is complete.

**Rejected alternative**: Reject them. Rejected because data loss is
worse than a temporarily-orphaned row.

---

## 15. `vw_top_customers` excludes the Unknown member

**Decision**: `vw_top_customers` filters out `customer_key = 0`. A
companion view `vw_unknown_sales` reports unknown-customer volume.

**Why**:
- Including Unknown in the top-customer ranking would dominate the
  chart with an entity that is not a customer.
- Reporting it separately preserves transparency without distortion.

---

## 16. Passwords are never committed

**Decision**: Database credentials live in `.env` (gitignored).
Passwords in SQL scripts (`02_roles_and_grants.sql`) are marked
**for local development only**.

**Why**:
- Committing credentials to GitHub is a serious security issue.
- In production, passwords would come from a secrets manager (Vault,
  AWS Secrets Manager, etc.).

**Rejected alternative**: Hardcode passwords in Python. Rejected —
this was an actual bug caught during development (`test_connection.py`
initially had the password inline).

---

## 17. Backup strategy: local now, cloud documented

**Decision**: Backups are local (`backups/`, gitignored), retention 7,
verification via `pg_restore --list`. Cloud off-site, encryption, and
scheduling are documented in `docs/backup_strategy.md` but not
implemented.

**Why**:
- Local backups are sufficient for the project scope.
- The script uses `BACKUP_DIR` as a variable, so switching to a cloud
  path is a one-line change.
- Documenting the production path explicitly is stronger than a
  half-implemented cloud integration.

---

## Lessons learned (written down so they are not repeated)

1. **Never `DELETE` from an audit table.** Use append-only. (Cost me a
   re-run to fix.)
2. **Check source data before writing a cleaner.** Assuming
   `customer_id` was an integer cost one debugging cycle. Always
   `SELECT ... LIMIT 5` first.
3. **Verify `.gitignore` before `git add`** on any sensitive file.
   `.env` was almost committed once.
4. **`ALTER OWNER` is required** for `TRUNCATE ... RESTART IDENTITY`
   by a non-owner role. Learned the hard way with `etl_user`.
5. **Sequences need explicit `GRANT USAGE`.** `GRANT ... ON SCHEMA`
   alone is not enough for `BIGSERIAL`.
6. **`CREATE OR REPLACE VIEW` cannot change column types.** Use
   `DROP VIEW` + `CREATE VIEW` when the underlying types change.


   
---

## 18. Incremental loading uses UPSERT, but watermark remains the limit

**Decision**: `load_staging_sales.py` and `load_fact_sales.py` use
`ON CONFLICT (order_id) DO UPDATE` (UPSERT). The watermark still
filters with `WHERE order_id > last_loaded_key`.

**Why**:
- UPSERT handles **updates to existing orders** that are re-read.
- The watermark makes the pipeline idempotent and efficient.

**Known limitation**: The watermark still filters by `order_id`, so:
- **Late-arriving records** (with a smaller `order_id`) are skipped.
- **Updates to existing orders** that don't pass the watermark are missed.

**Production fix (not implemented)**:
- Add an `updated_at` column to the source and use a
  `(updated_at, order_id)` composite watermark.
- Or switch to Change Data Capture (CDC).

**Scope decision**: For a 4-week learning project with a controlled
synthetic source, this trade-off is documented explicitly.







---

## 19. Manual test for updates and late-arriving records

The automated tests (`F10`) prove that re-running the ETL does not
duplicate rows. However, two scenarios are **not** covered by CI
because they require modifying `raw` data during the test:

1. **Updating an existing order** (e.g., changing `quantity` for an
   `order_id` already loaded).
2. **Late-arriving record** (an `order_id` smaller than the current
   watermark).

### How to test manually (update scenario)

```bash
# 1. Pick an existing order
psql -U postgres -d sales_dw -c \
  "SELECT order_id, quantity FROM staging.sales_clean LIMIT 1;"

# 2. Change it in raw
psql -U postgres -d sales_dw -c \
  "UPDATE raw.sales_raw SET quantity = 99 WHERE order_id = '<ORDER_ID>';"

# 3. Reset the watermark so the row is re-read
psql -U postgres -d sales_dw -c \
  "UPDATE warehouse.etl_watermark SET last_loaded_key = NULL
   WHERE pipeline_name = 'staging_sales';"

# 4. Re-run ETL
python scripts/etl/load_staging_sales.py

# 5. Verify the update propagated
psql -U postgres -d sales_dw -c \
  "SELECT order_id, quantity FROM staging.sales_clean
   WHERE order_id = '<ORDER_ID>';"
    