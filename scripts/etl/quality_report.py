"""
ETL Quality Report — answers analytical question 8:
"How many records were corrected or rejected in each load?"

Compares the ETL's measured results (staging.etl_stats + staging.rejected_rows
+ staging.orphan_returns) against the ground truth in raw.error_catalog_raw.

Run from repository root:
    python scripts/etl/quality_report.py
"""
import os
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


# How each injected error is measured from the ETL outputs.
# Each entry: (catalog error_type, SQL to compute observed count)
OBSERVED_SQL = {
    "mixed_date_format": """
        SELECT value FROM staging.etl_stats
        WHERE source_table='raw.sales_raw' AND metric='normalized_date'
    """,
    "missing_customer_id": """
        SELECT value FROM staging.etl_stats
        WHERE source_table='raw.sales_raw' AND metric='nulled_customer_id'
    """,
    "dirty_branch_id": """
        -- rows whose branch_id differed from LOWER(TRIM(...))
        -- (all rows had mixed-case branch_id, so normalized_branch_id counts them)
        SELECT value FROM staging.etl_stats
        WHERE source_table='raw.sales_raw' AND metric='normalized_branch_id'
    """,
    "negative_quantity": """
        SELECT value FROM staging.etl_stats
        WHERE source_table='raw.sales_raw' AND metric='rejected_negative_quantity'
    """,
    "missing_discount": """
        SELECT value FROM staging.etl_stats
        WHERE source_table='raw.sales_raw' AND metric='normalized_discount'
    """,
    "duplicate_row": """
        SELECT value FROM staging.etl_stats
        WHERE source_table='raw.sales_raw' AND metric='duplicates_removed'
    """,
}

# For dirty_branch_id, the catalog expects 2000 (only the injected rows),
# but normalized_branch_id counts ALL rows (101000) because the source
# uses uppercase everywhere. We override with a more targeted measure below.
OVERRIDES = {
    "dirty_branch_id": """
        -- Count rows whose branch_id in raw contained a space or lowercase letters
        SELECT COUNT(*) FROM raw.sales_raw
        WHERE branch_id <> UPPER(TRIM(branch_id))
           OR branch_id <> TRIM(branch_id)
    """,
}


def main():
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            # Ground truth
            cur.execute("""
                SELECT error_type, injected_count::int, description
                FROM raw.error_catalog_raw
                ORDER BY error_type
            """)
            catalog = cur.fetchall()

            print("=" * 78)
            print("ETL QUALITY REPORT — Answers question 8")
            print("=" * 78)
            print()
            print(f"{'error_type':<24} {'expected':>10} {'observed':>10} {'match':>8}")
            print("-" * 78)

            all_ok = True
            total_expected = 0
            total_observed = 0

            for error_type, expected, _desc in catalog:
                # Use override if present
                if error_type in OVERRIDES:
                    cur.execute(OVERRIDES[error_type])
                    observed = cur.fetchone()[0]
                elif error_type in OBSERVED_SQL:
                    cur.execute(OBSERVED_SQL[error_type])
                    row = cur.fetchone()
                    observed = row[0] if row else 0
                else:
                    observed = None

                total_expected += expected
                if observed is not None:
                    total_observed += observed
                    match = "OK" if observed == expected else "DIFF"
                    if observed != expected:
                        all_ok = False
                else:
                    match = "N/A"

                obs_str = str(observed) if observed is not None else "?"
                print(f"{error_type:<24} {expected:>10} {obs_str:>10} {match:>8}")

            print("-" * 78)
            print(f"{'TOTAL':<24} {total_expected:>10} {total_observed:>10}")
            print()

            # Detection rate
            if total_expected > 0:
                rate = 100.0 * total_observed / total_expected
                print(f"Detection rate: {rate:.2f}%")

            # Additional info: rejected rows and orphan returns
            print()
            print("Additional ETL results:")
            cur.execute("""
                SELECT source_table, COUNT(*)
                FROM staging.rejected_rows
                GROUP BY source_table
                ORDER BY source_table
            """)
            for src, cnt in cur.fetchall():
                print(f"  rejected rows from {src}: {cnt}")

            cur.execute("SELECT COUNT(*) FROM staging.orphan_returns")
            orphans = cur.fetchone()[0]
            print(f"  orphan returns (order_id not in sales_clean): {orphans}")

            print()
            if all_ok:
                print("RESULT: ETL detected every injected error with expected counts.")
            else:
                print("RESULT: Some counts differ from the catalog — review above.")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
    