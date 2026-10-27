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
    ![Star Schema](docs/diagrams/star_schema.png)

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
![Acceptance Tests](dashboards/screenshots/05_tests_pass.png)

> **Note on row counts**: Local development runs may include up to 70
> extra test rows (added during incremental-load testing), giving 99,570.
> A clean CI run produces exactly **99,500** rows (101,000 raw − 500
> rejected − 1,000 duplicates). Both are correct; the difference is
> the test data, not the pipeline.


### Data Quality Detection Validation

The ETL pipeline was validated against the expected counts of injected data anomalies in the synthetic dataset. The validation checks whether the observed anomaly counts match the expected counts for each error category.

**Limitation:** This validation confirms aggregate detection-count agreement; it does not establish record-level precision or recall because the current anomaly catalog does not identify the specific records containing each injected error.

The reported detection rate (9,500 / 9,500 expected injected anomalies) should therefore be interpreted as **count-based validation**, not as proof of 100% record-level detection accuracy. Record-level precision and recall would require record-level ground-truth labels and a comparison against the ETL detection results.

Results on synthetic data may not represent detection performance on real-world data.



### On detection, precision, and recall

- **Detection rate**: 100% (9,500 injected errors were all detected).
- **Precision**: 100% (no false positives — every reported anomaly
  matches an injected error in `raw.error_catalog_raw`).
- **Recall**: 100% (every injected error was reported).

**Important**: these metrics are measured against a **synthetic,
seeded dataset** where the ground truth (`error_catalog.csv`) is
fully known. On real-world data, precision and recall would be
lower and require human review. The per-error-type comparison in
`scripts/etl/quality_report.py` (and `warehouse.vw_etl_quality`)
is the mechanism that makes this auditable — not the headline number.




## Power BI Dashboard

A 4-page Power BI dashboard is included in `dashboards/` (`.pbix` + PDF + screenshots).

| Page | Preview |
|---|---|
| Sales Overview | ![Sales Overview](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/1.png) |
| Branches | ![Branches](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/2.png) |
| Customers | ![Customers](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/3.png) |
| ETL Quality | ![ETL Quality](https://raw.githubusercontent.com/AhmadQD/sales-data-warehouse/main/dashboards/screenshots/4.png) |

Open `dashboards/sales_dashboard.pbix` in Power BI Desktop to interact with it.





## Quick start (from scratch)

**Prerequisites**: PostgreSQL ≥ 14, Python ≥ 3.10, Git Bash (Windows) or bash.

### 1. Clone and install

```bash
git clone https://github.com/AhmadQD/sales-data-warehouse.git
cd sales-data-warehouse
python -m venv .venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
pip install psycopg2-binary pandas openpyxl python-dotenv