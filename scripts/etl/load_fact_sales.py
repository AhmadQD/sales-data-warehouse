"""
Load warehouse.fact_sales from staging.sales_clean (incremental).

Incremental strategy:
  * Read watermark WHERE pipeline_name='fact_sales'.
  * Only rows with order_id > last_loaded_key are processed.
  * On first run (watermark NULL), all rows are processed (backfill).
  * fact_sales has no unique constraint on order_id, so we rely on
    the watermark + a defensive guard (skip order_ids already in fact_sales).
  * Watermark is updated in the SAME transaction as the inserts.

Amounts are precomputed (snapshot semantics):
  gross  = quantity * unit_price
  net    = gross * (1 - discount)
  cost   = quantity * dim_product.unit_cost
  profit = net - cost

Run from repository root:
    python scripts/etl/load_fact_sales.py
"""
import os
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


def load_fact(conn):
    stats = {
        "read": 0,
        "loaded": 0,
        "skipped_existing": 0,
        "unknown_customer": 0,
        "unknown_product": 0,
        "unknown_branch": 0,
        "watermark_before": None,
        "watermark_after": None,
        "total_gross": 0.0,
        "total_net": 0.0,
        "total_cost": 0.0,
        "total_profit": 0.0,
    }

    with conn.cursor() as cur:
        wm = get_watermark(cur, "fact_sales")
        stats["watermark_before"] = wm

        # Build lookups
        cur.execute("SELECT customer_id, customer_key FROM warehouse.dim_customer")
        cust_map = dict(cur.fetchall())

        cur.execute("SELECT product_id, product_key, unit_cost FROM warehouse.dim_product")
        prod_map = {pid: (pkey, float(cost)) for pid, pkey, cost in cur.fetchall()}

        cur.execute("SELECT branch_id, branch_key FROM warehouse.dim_branch")
        branch_map = dict(cur.fetchall())

        cur.execute("SELECT date_key, full_date FROM warehouse.dim_date")
        date_map = {fd: dk for dk, fd in cur.fetchall()}

        # Read staging (incremental)
        if wm is None:
            cur.execute("""
                SELECT order_id, order_date, branch_id, customer_id,
                       product_id, quantity, unit_price, discount
                FROM staging.sales_clean
                ORDER BY order_id
            """)
        else:
            cur.execute("""
                SELECT order_id, order_date, branch_id, customer_id,
                       product_id, quantity, unit_price, discount
                FROM staging.sales_clean
                WHERE order_id > %s
                ORDER BY order_id
            """, (wm,))

        rows = cur.fetchall()
        stats["read"] = len(rows)

        # Defensive: existing order_ids in fact_sales (avoid duplicates on backfill)
        existing_orders = set()
        if wm is None:
            cur.execute("SELECT order_id FROM warehouse.fact_sales")
            existing_orders = {r[0] for r in cur.fetchall()}

        to_insert = []
        max_order_id = wm
        max_date = None

        for (order_id, order_date, branch_id, customer_id,
             product_id, quantity, unit_price, discount) in rows:

            if order_id in existing_orders:
                stats["skipped_existing"] += 1
                continue

            date_key = date_map.get(order_date)
            if date_key is None:
                continue

            if customer_id is None:
                customer_key = 0
                stats["unknown_customer"] += 1
            else:
                customer_key = cust_map.get(customer_id, 0)
                if customer_key == 0:
                    stats["unknown_customer"] += 1

            pk = prod_map.get(product_id)
            if pk is None:
                product_key, unit_cost = 0, 0.0
                stats["unknown_product"] += 1
            else:
                product_key, unit_cost = pk

            branch_key = branch_map.get(branch_id, 0)
            if branch_key == 0:
                stats["unknown_branch"] += 1

            qty = int(quantity)
            price = float(unit_price)
            disc = float(discount)

            gross = round(qty * price, 2)
            net = round(gross * (1 - disc), 2)
            cost = round(qty * unit_cost, 2)
            profit = round(net - cost, 2)

            stats["total_gross"] += gross
            stats["total_net"] += net
            stats["total_cost"] += cost
            stats["total_profit"] += profit

            to_insert.append((
                order_id, date_key, customer_key, product_key, branch_key,
                qty, round(price, 2), round(disc, 4),
                gross, net, cost, profit,
            ))

            if max_order_id is None or order_id > max_order_id:
                max_order_id = order_id
            if max_date is None or order_date > max_date:
                max_date = order_date

        if to_insert:
            
            execute_values(
                cur,
                """
                INSERT INTO warehouse.fact_sales
                    (order_id, date_key, customer_key, product_key, branch_key,
                     quantity, unit_price, discount,
                     gross_amount, net_amount, cost_amount, profit_amount)
                VALUES %s
                ON CONFLICT (order_id) DO UPDATE SET
                    date_key      = EXCLUDED.date_key,
                    customer_key  = EXCLUDED.customer_key,
                    product_key   = EXCLUDED.product_key,
                    branch_key    = EXCLUDED.branch_key,
                    quantity      = EXCLUDED.quantity,
                    unit_price    = EXCLUDED.unit_price,
                    discount      = EXCLUDED.discount,
                    gross_amount  = EXCLUDED.gross_amount,
                    net_amount    = EXCLUDED.net_amount,
                    cost_amount   = EXCLUDED.cost_amount,
                    profit_amount = EXCLUDED.profit_amount
                """,
                to_insert,
            )

        stats["loaded"] = len(to_insert)

        # Update watermark
        if max_order_id is not None:
            update_watermark(cur, "fact_sales", max_order_id, max_date, stats["loaded"])
            stats["watermark_after"] = max_order_id
        else:
            stats["watermark_after"] = wm

        conn.commit()

    return stats


def main():
    conn = get_connection()
    try:
        stats = load_fact(conn)
    finally:
        conn.close()

    print("=== warehouse.fact_sales (incremental) ===")
    print(f"  watermark before      : {stats['watermark_before']}")
    print(f"  watermark after       : {stats['watermark_after']}")
    print(f"  read                  : {stats['read']}")
    print(f"  loaded (new rows)     : {stats['loaded']}")
    print(f"  skipped (existing)    : {stats['skipped_existing']}")
    print(f"  unknown customer_key  : {stats['unknown_customer']}")
    print(f"  unknown product_key   : {stats['unknown_product']}")
    print(f"  unknown branch_key    : {stats['unknown_branch']}")
    print()
    print("  Totals (this run only):")
    print(f"    gross  : {stats['total_gross']:>15,.2f}")
    print(f"    net    : {stats['total_net']:>15,.2f}")
    print(f"    cost   : {stats['total_cost']:>15,.2f}")
    print(f"    profit : {stats['total_profit']:>15,.2f}")


if __name__ == "__main__":
    main()
    