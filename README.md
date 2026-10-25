# sales-data-warehouse


[![ETL Pipeline Tests](https://github.com/AhmadQD/sales-data-warehouse/actions/workflows/test.yml/badge.svg)](https://github.com/AhmadQD/sales-data-warehouse/actions/workflows/test.yml)



A production-style **PostgreSQL data warehouse** with a layered ETL pipeline.

> All source data is **synthetic** (generated with `SEED=42`).

## What this project demonstrates

- **Dimensional modeling** — Star Schema (`docs/star_schema.md`).
- **Layered ETL** — `raw` → `staging` → `warehouse`.
- **Data quality** — 100% detection vs. ground-truth catalog.
- **18 acceptance tests** — `scripts/db/12_master_test_runner.sql`.
- **Incremental loading** — watermark-based, idempotent.
- **Role-based security** — `analyst_user` isolated from `raw`/`staging`.
- **Backup & recovery** — `pg_dump -Fc` + retention + verification.

## Architecture

    data/raw/* → raw → staging → warehouse → analyst (views)

## Documentation

- `docs/star_schema.md` — dimensional model
- `docs/etl_decisions.md` — every decision
- `docs/data_dictionary.md` — every table and column
- `docs/backup_strategy.md` — backup now + production path
- `docs/analytical_questions.md` — the 8 questions

## Results

- **ETL detection rate**: 100% (9,500 / 9,500 injected errors)
- **18/18 acceptance tests PASS**
- **fact_sales**: 99,570 rows, $30.8M gross, $7.6M profit
- **11 views** answer the 8 analytical questions




## Power BI Dashboard

A 4-page Power BI dashboard is included in `dashboards/` (`.pbix` + PDF + screenshots).

| Page | Preview |
|---|---|
| Sales Overview | ![Sales Overview](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/1.png) |
| Branches | ![Branches](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/2.png) |
| Customers | ![Customers](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/3.png) |
| ETL Quality | ![ETL Quality](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/4.png) |

Open `dashboards/sales_dashboard.pbix` in Power BI Desktop to interact with it.





## Quick start

    git clone https://github.com/AhmadQD/sales-data-warehouse.git
    cd sales-data-warehouse
    pip install psycopg2-binary pandas openpyxl python-dotenv
    python scripts/generate_data.py
    psql -U postgres -f scripts/db/01_create_database.sql
    python scripts/etl/load_raw.py
    python scripts/etl/load_staging_sales.py
    python scripts/etl/load_fact_sales.py
    psql -U postgres -d sales_dw -f scripts/db/12_master_test_runner.sql
    psql -U postgres -d sales_dw -f scripts/queries/run_all.sql

## License

Educational project. Synthetic data. No warranty.
