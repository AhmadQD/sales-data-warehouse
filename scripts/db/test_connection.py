"""
Smoke test: verify psycopg2 can connect to sales_dw as etl_user.
Loads credentials from .env (never hardcoded).
Run: python scripts/db/test_connection.py
"""
import os
from pathlib import Path
import psycopg2
from dotenv import load_dotenv

# Load .env from repository root
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

conn = psycopg2.connect(
    host=os.getenv("DB_HOST"),
    port=os.getenv("DB_PORT"),
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
)

with conn.cursor() as cur:
    cur.execute("SELECT current_user, current_database(), version();")
    user, db, version = cur.fetchone()
    print(f"Connected as : {user}")
    print(f"Database     : {db}")
    print(f"Version      : {version.split(',')[0]}")

    cur.execute("""
        SELECT nspname
        FROM pg_namespace
        WHERE nspname IN ('raw', 'staging', 'warehouse')
        ORDER BY nspname;
    """)
    schemas = [row[0] for row in cur.fetchall()]
    print(f"Schemas visible: {schemas}")

conn.close()
print("OK")