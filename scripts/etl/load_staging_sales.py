"""
Clean and load raw.sales_raw into staging.sales_clean (incremental).

Incremental strategy:
  * Read watermark WHERE pipeline_name='staging_sales'.
  * Only rows with order_id > last_loaded_key are processed.
  * ON CONFLICT (order_id) DO UPDATE (upsert).
  * Watermark updated in the SAME transaction as inserts.

Audit:
  * Every run is appended to staging.etl_runs (append-only).
  * Rejected rows are linked to their run_id, preserving history.

Run from repository root:
    python scripts/etl/load_staging_sales.py
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
        raise ValueError("empty order_date")
    value = value.strip()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"unparseable order_date: {value!r}")


def reject(cur, run_id, source_row_id, reason, raw_data):
    cur.execute(
        """
        INSERT INTO staging.rejected_rows
            (run_id, source_table, source_row_id, reason, raw_data)
        VALUES (%s, 'raw.sales_raw', %s, %s, %s)
        """,
        (run_id, source_row_id, reason, raw_data),
    )


def get_watermark(cur, pipeline):
    cur.execute(
        "SELECT last_loaded_key FROM warehouse.etl_watermark WHERE pipeline_name = %s",
        (pipeline,),
    )
    row = cur.fetchone()
    return row[0] if row and row[0] else None


def update_watermark(cur, pipeline, last_key, last_date, rows_last_run):
    cur.execute(
        """
        UPDATE warehouse.etl_watermark
        SET last_loaded_key = %s,
            last_loaded_date = %s,
            last_run_at = NOW(),
            rows_loaded_last_run = %s,
            total_rows_processed = total_rows_processed + %s
        WHERE pipeline_name = %s
        """,
        (last_key, last_date, rows_last_run, rows_last_run, pipeline),
    )


def clean_sales(conn):
    stats = {
        "read": 0,
        "kept": 0,
        "rejected_negative_quantity": 0,
        "rejected_bad_date": 0,
        "rejected_other": 0,
        "normalized_branch_id": 0,
        "normalized_date": 0,
        "normalized_discount": 0,
        "nulled_customer_id": 0,
        "watermark_before": None,
        "watermark_after": None,
        "run_id": None,
    }

    with conn.cursor() as cur:
        # 1. Open a run entry FIRST (so we can link rejections to it)
        cur.execute(
            """
            INSERT INTO staging.etl_runs
                (pipeline_name, rows_read, rows_kept)
            VALUES ('staging_sales', 0, 0)
            RETURNING run_id
            """
        )
        stats["run_id"] = cur.fetchone()[0]

        wm = get_watermark(cur, "staging_sales")
        stats["watermark_before"] = wm

        if wm is None:
            cur.execute("""
                SELECT _row_id, order_id, order_date, branch_id, customer_id,
                       product_id, quantity, unit_price, discount
                FROM raw.sales_raw
                ORDER BY order_id
            """)
        else:
            cur.execute("""
                SELECT _row_id, order_id, order_date, branch_id, customer_id,
                       product_id, quantity, unit_price, discount
                FROM raw.sales_raw
                WHERE order_id > %s
                ORDER BY order_id
            """, (wm,))

        rows = cur.fetchall()
        stats["read"] = len(rows)

        to_insert = []
        max_order_id = wm
        max_date = None

        for row in rows:
            (_row_id, order_id, order_date, branch_id, customer_id,
             product_id, quantity, unit_price, discount) = row

            raw_repr = (f"order_id={order_id}, date={order_date}, branch={branch_id}, "
                        f"customer={customer_id}, product={product_id}, qty={quantity}, "
                        f"price={unit_price}, disc={discount}")

            order_id_s = (order_id or "").strip()
            if not order_id_s:
                reject(cur, stats["run_id"], _row_id, "empty order_id", raw_repr)
                stats["rejected_other"] += 1
                continue

            product_id_s = (product_id or "").strip()
            if not product_id_s:
                reject(cur, stats["run_id"], _row_id, "empty product_id", raw_repr)
                stats["rejected_other"] += 1
                continue

            branch_id_raw = (branch_id or "").strip()
            if not branch_id_raw:
                reject(cur, stats["run_id"], _row_id, "empty branch_id", raw_repr)
                stats["rejected_other"] += 1
                continue
            branch_id_s = branch_id_raw.lower()
            if branch_id_s != branch_id:
                stats["normalized_branch_id"] += 1

            try:
                qty = int(quantity)
            except (TypeError, ValueError):
                reject(cur, stats["run_id"], _row_id, f"non-integer quantity: {quantity!r}", raw_repr)
                stats["rejected_other"] += 1
                continue

            if qty <= 0:
                reject(cur, stats["run_id"], _row_id,
                       f"quantity <= 0 ({qty}) — ambiguous, rejected", raw_repr)
                stats["rejected_negative_quantity"] += 1
                continue

            try:
                date_obj = parse_date(order_date)
                if not order_date.strip().startswith(str(date_obj.year)):
                    stats["normalized_date"] += 1
            except ValueError as e:
                reject(cur, stats["run_id"], _row_id, str(e), raw_repr)
                stats["rejected_bad_date"] += 1
                continue

            cust_id_s = (customer_id or "").strip()
            customer_id_val = cust_id_s if cust_id_s else None
            if customer_id_val is None:
                stats["nulled_customer_id"] += 1

            try:
                price = float(unit_price)
            except (TypeError, ValueError):
                reject(cur, stats["run_id"], _row_id, f"non-numeric unit_price: {unit_price!r}", raw_repr)
                stats["rejected_other"] += 1
                continue
            if price < 0:
                reject(cur, stats["run_id"], _row_id, f"negative unit_price: {price}", raw_repr)
                stats["rejected_other"] += 1
                continue

            disc_s = (discount or "").strip()
            if disc_s == "":
                disc = 0.0
                stats["normalized_discount"] += 1
            else:
                try:
                    disc = float(disc_s)
                except ValueError:
                    reject(cur, stats["run_id"], _row_id, f"bad discount: {discount!r}", raw_repr)
                    stats["rejected_other"] += 1
                    continue
                if disc < 0 or disc > 1:
                    reject(cur, stats["run_id"], _row_id, f"discount out of range: {disc}", raw_repr)
                    stats["rejected_other"] += 1
                    continue

            to_insert.append((
                order_id_s, date_obj, branch_id_s, customer_id_val,
                product_id_s, qty, round(price, 2), round(disc, 4),
            ))

            if max_order_id is None or order_id_s > max_order_id:
                max_order_id = order_id_s
            if max_date is None or date_obj > max_date:
                max_date = date_obj




               # Deduplicate to_insert by order_id (keep last occurrence)
        before_dedup = len(to_insert)
        dedup = {}
        for row in to_insert:
            dedup[row[0]] = row
        to_insert = list(dedup.values())
        stats["duplicates_removed"] = before_dedup - len(to_insert)



            # Insert with UPSERT, using RETURNING (xmax = 0) to distinguish inserted vs updated
        inserted_count = 0
        updated_count = 0

        if to_insert:
            # Deduplicate by order_id (keep last occurrence)
            dedup = {}
            for row in to_insert:
                dedup[row[0]] = row
            to_insert = list(dedup.values())

            # execute_values cannot RETURNING per-row easily, so insert one by one
            # (acceptable for 99k rows; ~2-3 seconds)
            for row in to_insert:
                cur.execute(
                    """
                    INSERT INTO staging.sales_clean
                        (order_id, order_date, branch_id, customer_id,
                         product_id, quantity, unit_price, discount)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (order_id) DO UPDATE SET
                        order_date   = EXCLUDED.order_date,
                        branch_id    = EXCLUDED.branch_id,
                        customer_id  = EXCLUDED.customer_id,
                        product_id   = EXCLUDED.product_id,
                        quantity     = EXCLUDED.quantity,
                        unit_price   = EXCLUDED.unit_price,
                        discount     = EXCLUDED.discount
                    RETURNING (xmax = 0) AS was_inserted
                    """,
                    row,
                )
                if cur.fetchone()[0]:
                    inserted_count += 1
                else:
                    updated_count += 1

            stats["kept"] = inserted_count + updated_count
        else:
            stats["kept"] = 0

        stats["rows_inserted"] = inserted_count
        stats["rows_updated"] = updated_count

        # Update watermark
        if max_order_id is not None:
            update_watermark(cur, "staging_sales", max_order_id, max_date, stats["kept"])
            stats["watermark_after"] = max_order_id
        else:
            stats["watermark_after"] = wm

                  # Update the run entry
        cur.execute(
            """
            UPDATE staging.etl_runs
            SET rows_read = %s,
                rows_kept = %s,
                rows_inserted = %s,
                rows_updated = %s,
                duplicates_removed = %s,
                rejected_negative_quantity = %s,
                rejected_bad_date = %s,
                rejected_other = %s,
                normalized_branch_id = %s,
                normalized_date = %s,
                normalized_discount = %s,
                nulled_customer_id = %s
            WHERE run_id = %s
            """,
            (
                stats["read"], stats["kept"],
                stats.get("rows_inserted", 0), stats.get("rows_updated", 0),
                stats.get("duplicates_removed", 0),
                stats["rejected_negative_quantity"], stats["rejected_bad_date"],
                stats["rejected_other"],
                stats["normalized_branch_id"], stats["normalized_date"],
                stats["normalized_discount"], stats["nulled_customer_id"],
                stats["run_id"],
            ),
        )

        conn.commit()

    return stats


def main():
    conn = get_connection()
    try:
        stats = clean_sales(conn)
    finally:
        conn.close()

    print("=== staging.sales_clean (incremental) ===")
    print(f"  run_id                      : {stats['run_id']}")
    print(f"  watermark before            : {stats['watermark_before']}")
    print(f"  watermark after             : {stats['watermark_after']}")
    print(f"  read                        : {stats['read']}")
    print(f"  kept (new/updated)          : {stats['kept']}")
    print(f"  rejected (negative qty)     : {stats['rejected_negative_quantity']}")
    print(f"  rejected (bad date)         : {stats['rejected_bad_date']}")
    print(f"  rejected (other)            : {stats['rejected_other']}")
    print(f"  normalized (branch/date/disc): "
          f"{stats['normalized_branch_id']}/{stats['normalized_date']}/{stats['normalized_discount']}")
    print(f"  nulled customer_id          : {stats['nulled_customer_id']}")


if __name__ == "__main__":
    main()