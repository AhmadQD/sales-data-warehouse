"""
ETL Quality Report — answers analytical question 8.

Reads the LATEST run from staging.etl_runs (append-only audit log),
compares observed counts with raw.error_catalog_raw, and EXITS WITH
NON-ZERO CODE if any mismatch is found. This ensures CI fails when
data quality degrades.

Note: dirty_branch_id is computed directly from raw.sales_raw, because
the source uses uppercase branch_ids (all rows change on LOWER(TRIM)),
while the catalog only counts the 2,000 intentionally-injected rows.

Run from repository root:
    python scripts/etl/quality_report.py
"""
import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(REPO_ROOT / ".env")


def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


def main():
    conn = get_connection()
    exit_code = 0

    try:
        with conn.cursor() as cur:
            # Latest run from etl_runs
            cur.execute("""
                SELECT
                    rejected_negative_quantity,
                    rejected_bad_date,
                    rejected_other,
                    duplicates_removed,
                    normalized_branch_id,
                    normalized_date,
                    normalized_discount,
                    nulled_customer_id,
                    rows_read,
                    rows_kept
                FROM staging.etl_runs
                WHERE pipeline_name = 'staging_sales'
                ORDER BY run_at DESC
                LIMIT 1
            """)
            latest = cur.fetchone()

            if latest is None:
                print("ERROR: no ETL runs found in staging.etl_runs", file=sys.stderr)
                return 1

            (neg_qty, bad_date, other, dups, norm_branch,
             norm_date, norm_disc, null_cust, rows_read, rows_kept) = latest

            # Ground truth
            cur.execute("""
                SELECT error_type, injected_count::int
                FROM raw.error_catalog_raw
                ORDER BY error_type
            """)
            catalog = dict(cur.fetchall())

            # Map catalog error_type -> observed count from the latest run
            observed_map = {
                "mixed_date_format":   norm_date,
                "missing_customer_id": null_cust,
                "dirty_branch_id":     None,  # computed from raw below
                "negative_quantity":   neg_qty,
                "missing_discount":    norm_disc,
                "duplicate_row":       dups,
            }

            print("=" * 78)
            print("ETL QUALITY REPORT — Answers question 8")
            print("=" * 78)
            print(f"Source: staging.etl_runs (latest run)")
            print(f"  rows_read = {rows_read}, rows_kept = {rows_kept}")
            print()
            print(f"{'error_type':<24} {'expected':>10} {'observed':>10} {'match':>8}")
            print("-" * 78)

            total_expected = 0
            total_observed = 0
            failures = 0

            for error_type, expected in sorted(catalog.items()):
                if error_type == "dirty_branch_id":
                    cur.execute("""
                        SELECT COUNT(*) FROM raw.sales_raw
                        WHERE branch_id <> TRIM(branch_id)
                           OR branch_id <> UPPER(branch_id)
                    """)
                    observed = cur.fetchone()[0]
                else:
                    observed = observed_map.get(error_type)

                if observed is None:
                    print(f"{error_type:<24} {expected:>10} {'?':>10} {'N/A':>8}")
                    failures += 1
                    continue

                match = (observed == expected)
                total_expected += expected
                total_observed += observed
                if not match:
                    failures += 1
                print(f"{error_type:<24} {expected:>10} {observed:>10} {'OK' if match else 'DIFF':>8}")

            print("-" * 78)
            print(f"{'TOTAL':<24} {total_expected:>10} {total_observed:>10}")
            print()

            if total_expected > 0:
                rate = 100.0 * total_observed / total_expected
                print(f"Detection rate: {rate:.2f}%")

            print()
            if failures == 0:
                print("RESULT: PASS — all error counts match the catalog.")
            else:
                print(f"RESULT: FAIL — {failures} mismatch(es) found.")
                exit_code = 1

    finally:
        conn.close()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())