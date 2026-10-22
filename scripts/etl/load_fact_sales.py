"""
Load warehouse.fact_sales from staging.sales_clean.

For each sales row:
  * Look up surrogate keys from the four dimensions.
  * customer_id NULL  -> customer_key = 0 (Unknown).
  * product_id missing in dim -> product_key = 0 (should not happen).
  * branch_id missing in dim -> branch_key = 0 (should not happen).
  * Compute gross / net / cost / profit.

Strategy: TRUNCATE + full reload (idempotent for this project).

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


def load_fact(conn):
    stats = {
        "read": 0,
        "loaded": 0,
        "unknown_customer": 0,
        "unknown_product": 0,
        "unknown_branch": 0,
        "total_gross": 0.0,
        "total_net": 0.0,
        "total_cost": 0.0,
        "total_profit": 0.0,
    }

    with conn.cursor() as cur:
        cur.execute("TRUNCATE warehouse.fact_sales RESTART IDENTITY")

        # Build lookups (in memory — small dimensions)
        cur.execute("SELECT customer_id, customer_key FROM warehouse.dim_customer")
        cust_map = dict(cur.fetchall())

        cur.execute("SELECT product_id, product_key, unit_cost FROM warehouse.dim_product")
        prod_rows = cur.fetchall()
        prod_map = {pid: (pkey, cost) for pid, pkey, cost in prod_rows}

        cur.execute("SELECT branch_id, branch_key FROM warehouse.dim_branch")
        branch_map = dict(cur.fetchall())

        cur.execute("SELECT date_key, full_date FROM warehouse.dim_date")
        # convert date -> date_key
        date_map = {}
        for dk, fd in cur.fetchall():
            date_map[fd] = dk

        # Read staging
        cur.execute("""
            SELECT order_id, order_date, branch_id, customer_id,
                   product_id, quantity, unit_price, discount
            FROM staging.sales_clean
        """)
        rows = cur.fetchall()
        stats["read"] = len(rows)

        to_insert = []

        for (order_id, order_date, branch_id, customer_id,
             product_id, quantity, unit_price, discount) in rows:

            # date_key
            date_key = date_map.get(order_date)
            if date_key is None:
                # Should not happen (range covers 2020-2030)
                continue

            # customer_key
            if customer_id is None:
                customer_key = 0
                stats["unknown_customer"] += 1
            else:
                customer_key = cust_map.get(customer_id, 0)
                if customer_key == 0:
                    stats["unknown_customer"] += 1

            # product_key + unit_cost
            pk = prod_map.get(product_id)
            if pk is None:
                product_key, unit_cost = 0, 0.0
                stats["unknown_product"] += 1
            else:
                product_key, unit_cost = pk
                unit_cost = float(unit_cost)

            # branch_key
            branch_key = branch_map.get(branch_id, 0)
            if branch_key == 0:
                stats["unknown_branch"] += 1

            # Compute amounts
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

        if to_insert:
            execute_values(
                cur,
                """
                INSERT INTO warehouse.fact_sales
                    (order_id, date_key, customer_key, product_key, branch_key,
                     quantity, unit_price, discount,
                     gross_amount, net_amount, cost_amount, profit_amount)
                VALUES %s
                """,
                to_insert,
            )
        conn.commit()
        stats["loaded"] = len(to_insert)

    return stats


def main():
    conn = get_connection()
    try:
        stats = load_fact(conn)
    finally:
        conn.close()

    print("=== warehouse.fact_sales ===")
    print(f"  read                 : {stats['read']}")
    print(f"  loaded               : {stats['loaded']}")
    print(f"  unknown customer_key : {stats['unknown_customer']}")
    print(f"  unknown product_key  : {stats['unknown_product']}")
    print(f"  unknown branch_key   : {stats['unknown_branch']}")
    print()
    print("  Totals (sanity check):")
    print(f"    gross  : {stats['total_gross']:>15,.2f}")
    print(f"    net    : {stats['total_net']:>15,.2f}")
    print(f"    cost   : {stats['total_cost']:>15,.2f}")
    print(f"    profit : {stats['total_profit']:>15,.2f}")


if __name__ == "__main__":
    main()
    