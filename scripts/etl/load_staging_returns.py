"""
Clean and load raw.returns_raw into staging.returns_clean.

Notes:
  * All return_date values are already ISO (YYYY-MM-DD), but we still parse
    to DATE for safety.
  * return_id, order_id are TEXT natural keys (e.g. "R000001", "O0075722").
  * Returns whose order_id does NOT exist in staging.sales_clean are KEPT in
    returns_clean (they are real returns), and also recorded in
    staging.orphan_returns for auditability.

Run from repository root:
    python scripts/etl/load_staging_returns.py
"""
import os
from datetime import datetime
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values
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


def parse_date(value: str):
    if value is None or value == "":
        raise ValueError("empty return_date")
    value = value.strip()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"unparseable return_date: {value!r}")


def reject(cur, source_row_id, reason, raw_data):
    cur.execute(
        """
        INSERT INTO staging.rejected_rows
            (source_table, source_row_id, reason, raw_data)
        VALUES ('raw.returns_raw', %s, %s, %s)
        """,
        (source_row_id, reason, raw_data),
    )


def clean_returns(conn):
    stats = {
        "read": 0,
        "kept": 0,
        "rejected": 0,
        "orphan": 0,
    }

    with conn.cursor() as cur:
        # Clear previous state
        cur.execute("DELETE FROM staging.rejected_rows WHERE source_table = 'raw.returns_raw'")
        cur.execute("TRUNCATE staging.returns_clean")
        cur.execute("TRUNCATE staging.orphan_returns RESTART IDENTITY")
        conn.commit()

        # Fetch raw rows
        cur.execute("""
            SELECT _row_id, return_id, order_id, return_date, reason
            FROM raw.returns_raw
            ORDER BY _row_id
        """)
        rows = cur.fetchall()
        stats["read"] = len(rows)

        to_insert = []

        for _row_id, return_id, order_id, return_date, reason in rows:
            raw_repr = (f"return_id={return_id}, order_id={order_id}, "
                        f"date={return_date}, reason={reason}")
            try:
                return_id_s = (return_id or "").strip()
                if not return_id_s:
                    raise ValueError("empty return_id")

                order_id_s = (order_id or "").strip()
                if not order_id_s:
                    raise ValueError("empty order_id")

                date_obj = parse_date(return_date)
                reason_s = (reason or "").strip() or None

                to_insert.append((return_id_s, order_id_s, date_obj, reason_s))
            except Exception as e:
                reject(cur, _row_id, str(e), raw_repr)
                stats["rejected"] += 1

        # Bulk insert
        if to_insert:
            execute_values(
                cur,
                """
                INSERT INTO staging.returns_clean
                    (return_id, order_id, return_date, reason)
                VALUES %s
                """,
                to_insert,
            )
        stats["kept"] = len(to_insert)

        # Detect orphans (returns whose order_id is not in sales_clean)
        cur.execute("""
            INSERT INTO staging.orphan_returns (return_id, order_id)
            SELECT r.return_id, r.order_id
            FROM staging.returns_clean r
            LEFT JOIN staging.sales_clean s ON r.order_id = s.order_id
            WHERE s.order_id IS NULL
        """)
        cur.execute("SELECT COUNT(*) FROM staging.orphan_returns")
        stats["orphan"] = cur.fetchone()[0]

        conn.commit()

    return stats


def main():
    conn = get_connection()
    try:
        stats = clean_returns(conn)
    finally:
        conn.close()

    print("=== staging.returns_clean ===")
    print(f"  read     : {stats['read']}")
    print(f"  kept     : {stats['kept']}")
    print(f"  rejected : {stats['rejected']}")
    print(f"  orphan returns (recorded in staging.orphan_returns): {stats['orphan']}")


if __name__ == "__main__":
    main()
    