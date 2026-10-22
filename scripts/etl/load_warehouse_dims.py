"""
Load warehouse dimension tables from staging.

Mappings:
    staging.customers_clean -> warehouse.dim_customer
    staging.products_clean  -> warehouse.dim_product
    staging.branches_clean  -> warehouse.dim_branch

The 'UNKNOWN' row (key=0) is preserved. We delete all other rows
and reload — dimensions are snapshots for this project (SCD Type 1
behavior with SCD Type 2 scaffolding).

Run from repository root:
    python scripts/etl/load_warehouse_dims.py
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


def load_dim_customer(cur):
    cur.execute("DELETE FROM warehouse.dim_customer WHERE customer_key > 0")
    cur.execute("""
        INSERT INTO warehouse.dim_customer (customer_id, name, city)
        SELECT customer_id, name, city
        FROM staging.customers_clean
        ORDER BY customer_id
    """)
    cur.execute("SELECT COUNT(*) FROM warehouse.dim_customer")
    return cur.fetchone()[0]


def load_dim_product(cur):
    cur.execute("DELETE FROM warehouse.dim_product WHERE product_key > 0")
    cur.execute("""
        INSERT INTO warehouse.dim_product (product_id, product_name, category, unit_cost)
        SELECT product_id, product_name, category, unit_cost
        FROM staging.products_clean
        ORDER BY product_id
    """)
    cur.execute("SELECT COUNT(*) FROM warehouse.dim_product")
    return cur.fetchone()[0]


def load_dim_branch(cur):
    cur.execute("DELETE FROM warehouse.dim_branch WHERE branch_key > 0")
    cur.execute("""
        INSERT INTO warehouse.dim_branch (branch_id, branch_name, city)
        SELECT branch_id, branch_name, city
        FROM staging.branches_clean
        ORDER BY branch_id
    """)
    cur.execute("SELECT COUNT(*) FROM warehouse.dim_branch")
    return cur.fetchone()[0]


def main():
    conn = get_connection()
    try:
        for name, fn in [
            ("dim_customer", load_dim_customer),
            ("dim_product",  load_dim_product),
            ("dim_branch",   load_dim_branch),
        ]:
            with conn.cursor() as cur:
                total = fn(cur)
            conn.commit()
            print(f"{name:14s}: {total} rows (including UNKNOWN)")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
    