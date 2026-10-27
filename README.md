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

The ETL pipeline was validated against expected anomaly counts in a seeded synthetic dataset (`SEED=42`). The validation compares observed anomaly counts with the expected counts for each error category.

**Limitation:** This is count-based validation, not record-level accuracy measurement. Because the ground-truth catalog stores aggregate counts rather than record-level anomaly labels, record-level precision, recall, false positives, and false negatives cannot currently be reliably measured.

The reported result of 9,500 / 9,500 expected injected anomalies indicates agreement between observed and expected counts. It should not be interpreted as proof that every injected anomaly was detected correctly.

Record-level precision and recall would require record-level ground-truth labels and comparison with the ETL detection results. Results on synthetic data may not represent performance on real-world data.



### Detection Metrics and Limitations

The current validation confirms that the observed anomaly counts match the expected injected anomaly counts for each error category in the synthetic dataset.

This is **count-based validation**, not record-level precision or recall. The current ground-truth catalog stores aggregate counts rather than record-level anomaly labels, so false positives and false negatives cannot be reliably quantified at the record level.

Record-level precision and recall remain unmeasured and would require record-level ground-truth labels and comparison with the ETL detection results.

These results apply to the seeded synthetic dataset and should not be interpreted as a guarantee of equivalent performance on real-world data.




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