"""
Clean and load raw.sales_raw into staging.sales_clean.

Cleaning rules (documented in docs/etl_decisions.md):
  1. order_date:
       - Accepts 'YYYY-MM-DD' and 'DD/MM/YYYY'.
       - Converts to DATE.
       - Rows that cannot be parsed go to rejected_rows.
  2. branch_id:
       - LOWER(TRIM(...)) — handles "B01", "b01 ", "b01".
  3. customer_id:
       - Empty -> NULL. Row is kept (analysis can use Unknown customer).
  4. product_id:
       - Kept as TEXT (e.g. "P089").
  5. quantity:
       - Rows with quantity <= 0 are REJECTED (negative quantities are
         ambiguous: input error vs unrecorded return — do not guess).
  6. discount:
       - Empty -> 0.
  7. duplicates:
       - Rows identical across all business columns are deduplicated,
         keeping the first occurrence by _row_id.

Run from repository root:
    python scripts/etl/load_staging_sales.py
"""
import os
from datetime import datetime
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


def parse_date(value: str):
    """Accept YYYY-MM-DD and DD/MM/YYYY. Return a date or raise ValueError."""
    if value is None or value == "":
        raise ValueError("empty order_date")
    value = value.strip()

    for fmt in ("%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue

    raise ValueError(f"unparseable order_date: {value!r}")


def reject(cur, source_row_id, reason, raw_data):
    cur.execute(
        """
        INSERT INTO staging.rejected_rows
            (source_table, source_row_id, reason, raw_data)
        VALUES ('raw.sales_raw', %s, %s, %s)
        """,
        (source_row_id, reason, raw_data),
    )


def clean_sales(conn):
    stats = {
        "read": 0,
        "kept": 0,
        "rejected_negative_quantity": 0,
        "rejected_bad_date": 0,
        "rejected_other": 0,
        "duplicates_removed": 0,
        "normalized_branch_id": 0,
        "normalized_date": 0,
        "normalized_discount": 0,
        "nulled_customer_id": 0,
    }

    with conn.cursor() as cur:
        # Clear previous state
        cur.execute("DELETE FROM staging.rejected_rows WHERE source_table = 'raw.sales_raw'")
        cur.execute("TRUNCATE staging.sales_clean")
        conn.commit()

        # Fetch raw rows
        cur.execute("""
            SELECT _row_id, order_id, order_date, branch_id, customer_id,
                   product_id, quantity, unit_price, discount
            FROM raw.sales_raw
            ORDER BY _row_id
        """)
        rows = cur.fetchall()
        stats["read"] = len(rows)

        # Deduplication: track seen business-tuples
        seen = set()
        to_insert = []

        for row in rows:
            (_row_id, order_id, order_date, branch_id, customer_id,
             product_id, quantity, unit_price, discount) = row

            raw_repr = (f"order_id={order_id}, date={order_date}, branch={branch_id}, "
                        f"customer={customer_id}, product={product_id}, qty={quantity}, "
                        f"price={unit_price}, disc={discount}")

            # --- order_id: required, TEXT
            order_id_s = (order_id or "").strip()
            if not order_id_s:
                reject(cur, _row_id, "empty order_id", raw_repr)
                stats["rejected_other"] += 1
                continue

            # --- product_id: required, TEXT
            product_id_s = (product_id or "").strip()
            if not product_id_s:
                reject(cur, _row_id, "empty product_id", raw_repr)
                stats["rejected_other"] += 1
                continue

            # --- branch_id: LOWER(TRIM)
            branch_id_raw = (branch_id or "").strip()
            if not branch_id_raw:
                reject(cur, _row_id, "empty branch_id", raw_repr)
                stats["rejected_other"] += 1
                continue
            branch_id_s = branch_id_raw.lower()
            if branch_id_s != branch_id:
                stats["normalized_branch_id"] += 1

            # --- quantity: positive only
            try:
                qty = int(quantity)
            except (TypeError, ValueError):
                reject(cur, _row_id, f"non-integer quantity: {quantity!r}", raw_repr)
                stats["rejected_other"] += 1
                continue

            if qty <= 0:
                reject(cur, _row_id,
                       f"quantity <= 0 ({qty}) — ambiguous, rejected",
                       raw_repr)
                stats["rejected_negative_quantity"] += 1
                continue

            # --- order_date: parse
            try:
                date_obj = parse_date(order_date)
                # Count normalization: input was not already ISO
                if not order_date.strip().startswith(str(date_obj.year)):
                    stats["normalized_date"] += 1
            except ValueError as e:
                reject(cur, _row_id, str(e), raw_repr)
                stats["rejected_bad_date"] += 1
                continue

            # --- customer_id: empty -> NULL
            cust_id_s = (customer_id or "").strip()
            customer_id_val = cust_id_s if cust_id_s else None
            if customer_id_val is None:
                stats["nulled_customer_id"] += 1

            # --- unit_price
            try:
                price = float(unit_price)
            except (TypeError, ValueError):
                reject(cur, _row_id, f"non-numeric unit_price: {unit_price!r}", raw_repr)
                stats["rejected_other"] += 1
                continue
            if price < 0:
                reject(cur, _row_id, f"negative unit_price: {price}", raw_repr)
                stats["rejected_other"] += 1
                continue

            # --- discount: empty -> 0
            disc_s = (discount or "").strip()
            if disc_s == "":
                disc = 0.0
                stats["normalized_discount"] += 1
            else:
                try:
                    disc = float(disc_s)
                except ValueError:
                    reject(cur, _row_id, f"bad discount: {discount!r}", raw_repr)
                    stats["rejected_other"] += 1
                    continue
                if disc < 0 or disc > 1:
                    reject(cur, _row_id, f"discount out of range: {disc}", raw_repr)
                    stats["rejected_other"] += 1
                    continue

            # --- Deduplication key (all business fields, cleaned)
            key = (order_id_s, date_obj, branch_id_s, customer_id_val,
                   product_id_s, qty, round(price, 2), round(disc, 4))
            if key in seen:
                stats["duplicates_removed"] += 1
                continue
            seen.add(key)

            to_insert.append((
                order_id_s, date_obj, branch_id_s, customer_id_val,
                product_id_s, qty, round(price, 2), round(disc, 4),
            ))

        # Bulk insert
        from psycopg2.extras import execute_values
        if to_insert:
            execute_values(
                cur,
                """
                INSERT INTO staging.sales_clean
                    (order_id, order_date, branch_id, customer_id,
                     product_id, quantity, unit_price, discount)
                VALUES %s
                """,
                to_insert,
            )
        conn.commit()
        stats["kept"] = len(to_insert)

    return stats


def main():
    conn = get_connection()
    try:
        stats = clean_sales(conn)
    finally:
        conn.close()

    print("=== staging.sales_clean ===")
    print(f"  read                        : {stats['read']}")
    print(f"  kept                        : {stats['kept']}")
    print(f"  rejected (negative qty)     : {stats['rejected_negative_quantity']}")
    print(f"  rejected (bad date)         : {stats['rejected_bad_date']}")
    print(f"  rejected (other)            : {stats['rejected_other']}")
    print(f"  duplicates removed          : {stats['duplicates_removed']}")
    print("  --- normalizations (info only) ---")
    print(f"  branch_id normalized        : {stats['normalized_branch_id']}")
    print(f"  date re-formatted           : {stats['normalized_date']}")
    print(f"  discount defaulted to 0     : {stats['normalized_discount']}")
    print(f"  customer_id nulled          : {stats['nulled_customer_id']}")

    # Persist stats to staging.etl_stats (single source of truth for reports)
    conn2 = get_connection()
    try:
        with conn2.cursor() as cur:
            cur.execute("DELETE FROM staging.etl_stats WHERE source_table = 'raw.sales_raw'")
            metrics = [
                ("read", stats["read"]),
                ("kept", stats["kept"]),
                ("rejected_negative_quantity", stats["rejected_negative_quantity"]),
                ("rejected_bad_date", stats["rejected_bad_date"]),
                ("rejected_other", stats["rejected_other"]),
                ("duplicates_removed", stats["duplicates_removed"]),
                ("normalized_branch_id", stats["normalized_branch_id"]),
                ("normalized_date", stats["normalized_date"]),
                ("normalized_discount", stats["normalized_discount"]),
                ("nulled_customer_id", stats["nulled_customer_id"]),
            ]
            for metric, value in metrics:
                cur.execute(
                    """
                    INSERT INTO staging.etl_stats (source_table, metric, value)
                    VALUES ('raw.sales_raw', %s, %s)
                    """,
                    (metric, value),
                )
        conn2.commit()
    finally:
        conn2.close()

    expected_kept = 101000 - 500 - 1000  # raw - neg - dup
    print()
    if stats["kept"] == expected_kept:
        print(f"OK: kept == {expected_kept} (as expected).")
    else:
        print(f"WARNING: expected kept={expected_kept}, got {stats['kept']}")


if __name__ == "__main__":
    main()
    