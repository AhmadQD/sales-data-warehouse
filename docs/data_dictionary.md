# Data Dictionary — sales-data-warehouse

Every table, every column, and its purpose.

## Schemas

| Schema | Purpose |
|---|---|
| `raw` | Landing zone. Source data as-is, all `TEXT`. |
| `staging` | Cleaned, typed, validated. |
| `warehouse` | Star schema (dimensions + fact). Serving layer. |

---

## `raw` — Landing Zone

All tables carry `_row_id BIGSERIAL`, `_loaded_at TIMESTAMP`, `_source_file TEXT`.

### `raw.sales_raw`
| Column | Type | Source | Notes |
|---|---|---|---|
| order_id | TEXT | sales.csv | e.g. `O0100000` |
| order_date | TEXT | sales.csv | `YYYY-MM-DD` or `DD/MM/YYYY` |
| branch_id | TEXT | sales.csv | possibly dirty (`"b01 "`) |
| customer_id | TEXT | sales.csv | possibly empty |
| product_id | TEXT | sales.csv | e.g. `P089` |
| quantity | TEXT | sales.csv | possibly negative |
| unit_price | TEXT | sales.csv | |
| discount | TEXT | sales.csv | possibly empty |

### `raw.returns_raw`
| Column | Type | Notes |
|---|---|---|
| return_id | TEXT | e.g. `R000001` |
| order_id | TEXT | FK to sales |
| return_date | TEXT | `YYYY-MM-DD` |
| reason | TEXT | |

### `raw.products_raw`
| Column | Type | Notes |
|---|---|---|
| product_id | TEXT | e.g. `P089` |
| product_name | TEXT | |
| category | TEXT | 8 categories |
| unit_cost | TEXT | |

### `raw.customers_raw`
| Column | Type | Notes |
|---|---|---|
| customer_id | TEXT | e.g. `C00001` |
| name | TEXT | |
| city | TEXT | |

### `raw.branches_raw`
| Column | Type | Notes |
|---|---|---|
| branch_id | TEXT | e.g. `b01` |
| branch_name | TEXT | |
| city | TEXT | |

### `raw.error_catalog_raw`
Ground truth for injected errors (used by question 8).
| Column | Type | Notes |
|---|---|---|
| error_type | TEXT | 6 types |
| injected_count | TEXT | expected count |
| description | TEXT | human-readable |

### `raw.load_log`
Audit log for each file load.
| Column | Type | Notes |
|---|---|---|
| load_id | BIGSERIAL | PK |
| source_file | TEXT | e.g. `sales.csv` |
| target_table | TEXT | e.g. `raw.sales_raw` |
| started_at | TIMESTAMP | |
| finished_at | TIMESTAMP | |
| rows_read | INTEGER | |
| rows_loaded | INTEGER | |
| rows_failed | INTEGER | |
| status | TEXT | `running` / `success` / `failed` |
| error_message | TEXT | |

### `raw.load_errors`
Row-level failures during load.
| Column | Type | Notes |
|---|---|---|
| error_id | BIGSERIAL | PK |
| load_id | BIGINT | FK to `load_log` |
| source_file | TEXT | |
| row_number | INTEGER | |
| raw_data | TEXT | |
| error_message | TEXT | |

---

## `staging` — Cleaned & Typed

### `staging.sales_clean`
| Column | Type | Notes |
|---|---|---|
| order_id | TEXT | **PK** |
| order_date | DATE | parsed |
| branch_id | TEXT | lowercased, trimmed |
| customer_id | TEXT | NULL if missing |
| product_id | TEXT | |
| quantity | INTEGER | `> 0` (CHECK) |
| unit_price | NUMERIC(10,2) | `>= 0` |
| discount | NUMERIC(5,4) | `[0,1]`, default 0 |

### `staging.returns_clean`
| Column | Type | Notes |
|---|---|---|
| return_id | TEXT | **PK** |
| order_id | TEXT | may be orphan |
| return_date | DATE | |
| reason | TEXT | |

### `staging.products_clean`
| Column | Type | Notes |
|---|---|---|
| product_id | TEXT | **PK** |
| product_name | TEXT | |
| category | TEXT | |
| unit_cost | NUMERIC(10,2) | `>= 0` |

### `staging.customers_clean`
| Column | Type | Notes |
|---|---|---|
| customer_id | TEXT | **PK** |
| name | TEXT | |
| city | TEXT | |

### `staging.branches_clean`
| Column | Type | Notes |
|---|---|---|
| branch_id | TEXT | **PK**, lowercased |
| branch_name | TEXT | |
| city | TEXT | |

### `staging.rejected_rows`
Audit trail for every dropped row.
| Column | Type | Notes |
|---|---|---|
| rejected_id | BIGSERIAL | PK |
| source_table | TEXT | e.g. `raw.sales_raw` |
| source_row_id | BIGINT | `raw._row_id` |
| reason | TEXT | e.g. `quantity <= 0` |
| raw_data | TEXT | full row snapshot |
| rejected_at | TIMESTAMP | |

### `staging.orphan_returns`
Returns whose `order_id` is not in `sales_clean`.
| Column | Type | Notes |
|---|---|---|
| orphan_id | BIGSERIAL | PK |
| return_id | TEXT | |
| order_id | TEXT | |
| detected_at | TIMESTAMP | |

### `staging.etl_runs`
Append-only audit log of every ETL run.
| Column | Type | Notes |
|---|---|---|
| run_id | BIGSERIAL | PK |
| pipeline_name | TEXT | `staging_sales` |
| run_at | TIMESTAMP | |
| rows_read | INTEGER | |
| rows_kept | INTEGER | |
| rejected_negative_quantity | INTEGER | |
| rejected_bad_date | INTEGER | |
| rejected_other | INTEGER | |
| duplicates_removed | INTEGER | |
| normalized_branch_id | INTEGER | |
| normalized_date | INTEGER | |
| normalized_discount | INTEGER | |
| nulled_customer_id | INTEGER | |

---

## `warehouse` — Star Schema

### `warehouse.dim_date`
| Column | Type | Notes |
|---|---|---|
| date_key | INTEGER | **PK**, `YYYYMMDD` |
| full_date | DATE | UNIQUE |
| year | SMALLINT | |
| quarter | SMALLINT | 1-4 |
| month | SMALLINT | 1-12 |
| month_name | TEXT | |
| day | SMALLINT | 1-31 |
| day_of_week | SMALLINT | 0=Sun, 6=Sat |
| is_weekend | BOOLEAN | |

Range: 2020-01-01 → 2030-12-31 (4,018 rows).

### `warehouse.dim_customer`
| Column | Type | Notes |
|---|---|---|
| customer_key | BIGSERIAL | **PK** (surrogate) |
| customer_id | TEXT | **UNIQUE** (natural) |
| name | TEXT | |
| city | TEXT | |
| valid_from | TIMESTAMP | SCD scaffolding |
| valid_to | TIMESTAMP | SCD scaffolding |
| is_current | BOOLEAN | SCD scaffolding |

Includes `customer_key = 0` / `customer_id = 'UNKNOWN'`.

### `warehouse.dim_product`
| Column | Type | Notes |
|---|---|---|
| product_key | BIGSERIAL | **PK** |
| product_id | TEXT | **UNIQUE** |
| product_name | TEXT | |
| category | TEXT | |
| unit_cost | NUMERIC(10,2) | |
| valid_from | TIMESTAMP | |
| valid_to | TIMESTAMP | |
| is_current | BOOLEAN | |

Includes `product_key = 0` / `'UNKNOWN'`.

### `warehouse.dim_branch`
| Column | Type | Notes |
|---|---|---|
| branch_key | BIGSERIAL | **PK** |
| branch_id | TEXT | **UNIQUE** |
| branch_name | TEXT | |
| city | TEXT | |
| valid_from | TIMESTAMP | |
| valid_to | TIMESTAMP | |
| is_current | BOOLEAN | |

Includes `branch_key = 0` / `'UNKNOWN'`.

### `warehouse.fact_sales`
Grain: one row per `order_id`.

| Column | Type | Notes |
|---|---|---|
| sales_key | BIGSERIAL | **PK** |
| order_id | TEXT | degenerate dimension |
| date_key | INTEGER | **FK** → dim_date |
| customer_key | BIGINT | **FK** → dim_customer |
| product_key | BIGINT | **FK** → dim_product |
| branch_key | BIGINT | **FK** → dim_branch |
| quantity | INTEGER | `> 0` |
| unit_price | NUMERIC(10,2) | `>= 0` |
| discount | NUMERIC(5,4) | `[0,1]` |
| gross_amount | NUMERIC(12,2) | `quantity * unit_price` |
| net_amount | NUMERIC(12,2) | `gross * (1 - discount)` |
| cost_amount | NUMERIC(12,2) | `quantity * dim_product.unit_cost` |
| profit_amount | NUMERIC(12,2) | `net - cost` |

**Indexes**: date_key, customer_key, product_key, branch_key, order_id.

### `warehouse.etl_watermark`
Incremental loading cursor.
| Column | Type | Notes |
|---|---|---|
| pipeline_name | TEXT | **PK** |
| last_loaded_key | TEXT | last `order_id` loaded |
| last_loaded_date | DATE | |
| last_run_at | TIMESTAMP | |
| rows_loaded_last_run | INTEGER | |
| total_rows_loaded | INTEGER | |

Pipelines: `staging_sales`, `fact_sales`.

---

## Views (`warehouse`)

| View | Question | Description |
|---|---|---|
| `vw_monthly_sales` | Q1 | Monthly & yearly totals |
| `vw_product_performance` | Q2 | Products with revenue rank |
| `vw_branch_performance` | Q3 | Branches vs. average |
| `vw_top_customers` | Q4 | Top customers (excl. Unknown) |
| `vw_unknown_sales` | Q4 (companion) | Unknown-customer volume |
| `vw_monthly_growth` | Q5 | MoM + YoY growth |
| `vw_profit_by_category` | Q6 | Profit by category |
| `vw_return_rate_by_product` | Q7 | Return rate per product |
| `vw_return_overview` | Q7 (companion) | Global return stats |
| `vw_etl_quality` | Q8 | Detection vs. catalog |

All views are granted to `analyst_user`.
