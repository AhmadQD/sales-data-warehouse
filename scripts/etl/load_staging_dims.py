"""
Clean and load dimension source data into staging.*_clean.

Sources:
  raw.customers_raw -> staging.customers_clean
  raw.products_raw  -> staging.products_clean
  raw.branches_raw  -> staging.branches_clean

Natural keys (customer_id, product_id, branch_id) are TEXT in the source
(e.g. "C00001") and remain TEXT here — they are preserved for traceability.
Surrogate keys will be generated in the warehouse layer.

Rows that cannot be cleaned go to staging.rejected_rows.

Run from repository root:
    python scripts/etl/load_staging_dims.py
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


def reject(cur, source_table, source_row_id, reason, raw_data):
    """Insert one rejected row into the audit table."""
    cur.execute(
        """
        INSERT INTO staging.rejected_rows
            (source_table, source_row_id, reason, raw_data)
        VALUES (%s, %s, %s, %s)
        """,
        (source_table, source_row_id, reason, raw_data),
    )


# ---------------------------------------------------------------------------
# Customers
# ---------------------------------------------------------------------------
def clean_customers(cur):
    cur.execute("TRUNCATE staging.customers_clean")
    cur.execute("""
        SELECT _row_id, customer_id, name, city
        FROM raw.customers_raw
        ORDER BY _row_id
    """)
    rows = cur.fetchall()

    kept = 0
    rejected = 0
    for row_id, cid, name, city in rows:
        raw_repr = f"customer_id={cid}, name={name}, city={city}"
        try:
            customer_id = (cid or "").strip()
            if not customer_id:
                raise ValueError("empty customer_id")
            clean_name = (name or "").strip()
            if not clean_name:
                raise ValueError("empty name")
            clean_city = (city or "").strip() or None

            cur.execute(
                """
                INSERT INTO staging.customers_clean
                    (customer_id, name, city)
                VALUES (%s, %s, %s)
                """,
                (customer_id, clean_name, clean_city),
            )
            kept += 1
        except Exception as e:
            reject(cur, "raw.customers_raw", row_id, str(e), raw_repr)
            rejected += 1
    return kept, rejected


# ---------------------------------------------------------------------------
# Products
# ---------------------------------------------------------------------------
def clean_products(cur):
    cur.execute("TRUNCATE staging.products_clean")
    cur.execute("""
        SELECT _row_id, product_id, product_name, category, unit_cost
        FROM raw.products_raw
        ORDER BY _row_id
    """)
    rows = cur.fetchall()

    kept = 0
    rejected = 0
    for row_id, pid, name, category, cost in rows:
        raw_repr = f"product_id={pid}, name={name}, category={category}, cost={cost}"
        try:
            product_id = (pid or "").strip()
            if not product_id:
                raise ValueError("empty product_id")
            clean_name = (name or "").strip()
            if not clean_name:
                raise ValueError("empty product_name")
            clean_cat = (category or "").strip()
            if not clean_cat:
                raise ValueError("empty category")

            unit_cost = float(cost)
            if unit_cost < 0:
                raise ValueError(f"negative unit_cost: {unit_cost}")

            cur.execute(
                """
                INSERT INTO staging.products_clean
                    (product_id, product_name, category, unit_cost)
                VALUES (%s, %s, %s, %s)
                """,
                (product_id, clean_name, clean_cat, round(unit_cost, 2)),
            )
            kept += 1
        except Exception as e:
            reject(cur, "raw.products_raw", row_id, str(e), raw_repr)
            rejected += 1
    return kept, rejected


# ---------------------------------------------------------------------------
# Branches
# ---------------------------------------------------------------------------
def clean_branches(cur):
    cur.execute("TRUNCATE staging.branches_clean")
    cur.execute("""
        SELECT _row_id, branch_id, branch_name, city
        FROM raw.branches_raw
        ORDER BY _row_id
    """)
    rows = cur.fetchall()

    kept = 0
    rejected = 0
    for row_id, bid, name, city in rows:
        raw_repr = f"branch_id={bid}, name={name}, city={city}"
        try:
            clean_id = (bid or "").strip().lower()
            if not clean_id:
                raise ValueError("empty branch_id")
            clean_name = (name or "").strip()
            if not clean_name:
                raise ValueError("empty branch_name")
            clean_city = (city or "").strip() or None

            cur.execute(
                """
                INSERT INTO staging.branches_clean
                    (branch_id, branch_name, city)
                VALUES (%s, %s, %s)
                """,
                (clean_id, clean_name, clean_city),
            )
            kept += 1
        except Exception as e:
            reject(cur, "raw.branches_raw", row_id, str(e), raw_repr)
            rejected += 1
    return kept, rejected


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    conn = get_connection()
    try:
        # Clear previous rejections for these source tables
        with conn.cursor() as cur:
            cur.execute(
                """
                DELETE FROM staging.rejected_rows
                WHERE source_table IN
                    ('raw.customers_raw', 'raw.products_raw', 'raw.branches_raw')
                """
            )
        conn.commit()

        for name, fn in [
            ("customers", clean_customers),
            ("products",  clean_products),
            ("branches",  clean_branches),
        ]:
            with conn.cursor() as cur:
                kept, rejected = fn(cur)
            conn.commit()
            print(f"{name:10s}: kept={kept:5d}  rejected={rejected}")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
    