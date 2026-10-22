"""
Load source files (CSV / Excel / JSON) into raw.* tables.

Design:
  * raw is a *snapshot* of the source. Each run TRUNCATEs the target
    table first, then reloads. This makes the script idempotent.
  * Every load is logged in raw.load_log (one row per file).
  * Row-level failures go to raw.load_errors.

Run from repository root:
    python scripts/etl/load_raw.py
"""
import os
import sys
import traceback
from pathlib import Path
from datetime import datetime

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = REPO_ROOT / "data" / "raw"
load_dotenv(REPO_ROOT / ".env")


def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


def read_source(path: Path) -> pd.DataFrame:
    """Read a source file as strings. No type inference — raw keeps everything TEXT."""
    suffix = path.suffix.lower()
    if suffix == ".csv":
        return pd.read_csv(path, dtype=str, keep_default_na=False)
    if suffix == ".json":
        return pd.read_json(path, dtype=str)
    if suffix == ".xlsx":
        return pd.read_excel(path, dtype=str)
    raise ValueError(f"Unsupported file type: {suffix}")


# ---------------------------------------------------------------------------
# Load specs: (source file, target table, source columns in order)
# ---------------------------------------------------------------------------
LOADS = [
    {
        "file": "sales.csv",
        "table": "raw.sales_raw",
        "columns": ["order_id", "order_date", "branch_id", "customer_id",
                    "product_id", "quantity", "unit_price", "discount"],
    },
    {
        "file": "returns.csv",
        "table": "raw.returns_raw",
        "columns": ["return_id", "order_id", "return_date", "reason"],
    },
    {
        "file": "products.xlsx",
        "table": "raw.products_raw",
        "columns": ["product_id", "product_name", "category", "unit_cost"],
    },
    {
        "file": "customers.json",
        "table": "raw.customers_raw",
        "columns": ["customer_id", "name", "city"],
    },
    {
        "file": "branches.json",
        "table": "raw.branches_raw",
        "columns": ["branch_id", "branch_name", "city"],
    },
       {
        "file": "error_catalog.csv",
        "table": "raw.error_catalog_raw",
        "columns": ["error_type", "injected_count", "description"],
    },
]


# ---------------------------------------------------------------------------
# Core loader
# ---------------------------------------------------------------------------
def load_one(conn, spec: dict) -> dict:
    source_file = spec["file"]
    table = spec["table"]
    columns = spec["columns"]
    path = RAW_DIR / source_file

    result = {
        "source_file": source_file,
        "target_table": table,
        "rows_read": 0,
        "rows_loaded": 0,
        "rows_failed": 0,
        "status": "failed",
        "error_message": None,
    }

    with conn.cursor() as cur:
        # Open a load_log entry
        cur.execute(
            """
            INSERT INTO raw.load_log
                (source_file, target_table, rows_read, rows_loaded, rows_failed, status)
            VALUES (%s, %s, 0, 0, 0, 'running')
            RETURNING load_id
            """,
            (source_file, table),
        )
        load_id = cur.fetchone()[0]
        conn.commit()

    try:
        if not path.exists():
            raise FileNotFoundError(f"Missing source file: {path}")

        df = read_source(path)
        result["rows_read"] = len(df)

        # Basic structural check: all expected columns must exist
        missing = [c for c in columns if c not in df.columns]
        if missing:
            raise ValueError(f"Missing columns in {source_file}: {missing}")

        # Convert to list of tuples, preserving order, all values as str
        df = df[columns].fillna("")
        rows = [tuple(str(v) for v in rec) for rec in df.itertuples(index=False, name=None)]

        with conn.cursor() as cur:
            # raw = snapshot of the source
            cur.execute(f"TRUNCATE {table} RESTART IDENTITY")

            placeholders = "(" + ", ".join(["%s"] * (len(columns) + 2)) + ")"
            # +2 for _source_file and _loaded_at defaults? No — _loaded_at has default.
            # We insert _source_file + the source columns.
            insert_sql = (
                f"INSERT INTO {table} (_source_file, {', '.join(columns)}) "
                f"VALUES %s"
            )
            template = "(" + ", ".join(["%s"] * (len(columns) + 1)) + ")"
            data = [(source_file, *r) for r in rows]

            execute_values(cur, insert_sql, data, template=template)
        conn.commit()

        result["rows_loaded"] = len(data)
        result["status"] = "success"

    except Exception as e:
        conn.rollback()
        result["error_message"] = str(e)
        # Try to log row-level failure if we have a load_id
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO raw.load_errors
                        (load_id, source_file, row_number, raw_data, error_message)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (load_id, source_file, None, None, str(e)),
                )
            conn.commit()
        except Exception:
            conn.rollback()

    # Update load_log
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE raw.load_log
                SET finished_at = NOW(),
                    rows_read = %s,
                    rows_loaded = %s,
                    rows_failed = %s,
                    status = %s,
                    error_message = %s
                WHERE load_id = %s
                """,
                (
                    result["rows_read"], result["rows_loaded"], result["rows_failed"],
                    result["status"], result["error_message"], load_id,
                ),
            )
        conn.commit()
    except Exception:
        conn.rollback()

    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f"Loading from: {RAW_DIR}")
    conn = get_connection()
    all_ok = True
    try:
        for spec in LOADS:
            print(f"\n>>> {spec['file']} -> {spec['table']}")
            r = load_one(conn, spec)
            status_symbol = "OK" if r["status"] == "success" else "FAIL"
            print(f"    [{status_symbol}] read={r['rows_read']} loaded={r['rows_loaded']} "
                  f"failed={r['rows_failed']}")
            if r["error_message"]:
                print(f"    error: {r['error_message']}")
                all_ok = False
    finally:
        conn.close()

    print("\nDone." if all_ok else "\nDone with errors.")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
    