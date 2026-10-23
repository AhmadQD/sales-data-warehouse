"""Generate synthetic sales data (multi-source, with known injected errors).

Outputs (in data/raw/):
  sales.csv, returns.csv, products.xlsx, customers.json, branches.json,
  error_catalog.csv  <- ground truth: how many errors of each type were injected
"""
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 42
N_ORDERS = 100_000
N_PRODUCTS = 200
N_CUSTOMERS = 5_000
OUT_DIR = Path("data/raw")

rng = np.random.default_rng(SEED)
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- 1. Reference data
cities = ["Taif", "Jeddah", "Riyadh", "Makkah", "Madinah", "Dammam", "Abha", "Tabuk"]
branches = pd.DataFrame({
    "branch_id": [f"B{i:02d}" for i in range(1, len(cities) + 1)],
    "branch_name": [f"Market {c}" for c in cities],
    "city": cities,
})

categories = ["Dairy", "Bakery", "Produce", "Meat", "Beverages", "Snacks", "Cleaning", "Frozen"]
unit_cost = rng.uniform(2, 80, N_PRODUCTS).round(2)
products = pd.DataFrame({
    "product_id": [f"P{i:03d}" for i in range(1, N_PRODUCTS + 1)],
    "product_name": [f"Product {i:03d}" for i in range(1, N_PRODUCTS + 1)],
    "category": rng.choice(categories, N_PRODUCTS),
    "unit_cost": unit_cost,
})
# Selling price = cost * markup. Kept outside the products file (it lives in the sales system).
unit_price = (unit_cost * rng.uniform(1.15, 1.6, N_PRODUCTS)).round(2)

customers = pd.DataFrame({
    "customer_id": [f"C{i:05d}" for i in range(1, N_CUSTOMERS + 1)],
    "name": [f"Customer {i:05d}" for i in range(1, N_CUSTOMERS + 1)],
    "city": rng.choice(cities, N_CUSTOMERS),
})

# ---------------------------------------------------------------- 2. Clean sales
order_dates = pd.to_datetime("2023-01-01") + pd.to_timedelta(
    rng.integers(0, 1096, N_ORDERS), unit="D"
)
product_idx = rng.integers(0, N_PRODUCTS, N_ORDERS)
sales = pd.DataFrame({
    "order_id": [f"O{i:07d}" for i in range(1, N_ORDERS + 1)],
    "order_date": order_dates,
    "branch_id": rng.choice(branches["branch_id"], N_ORDERS),
    "customer_id": rng.choice(customers["customer_id"], N_ORDERS),
    "product_id": products["product_id"].to_numpy()[product_idx],
    "quantity": rng.integers(1, 11, N_ORDERS),
    "unit_price": unit_price[product_idx],
    "discount": rng.choice([0.0, 0.05, 0.10, 0.15], N_ORDERS, p=[0.6, 0.2, 0.15, 0.05]),
})

# ---------------------------------------------------------------- 3. Returns (about 3% of orders)
returned = sales.sample(frac=0.03, random_state=SEED)
return_delay = pd.to_timedelta(rng.integers(1, 31, len(returned)), unit="D").to_numpy()
returns = pd.DataFrame({
    "return_id": [f"R{i:06d}" for i in range(1, len(returned) + 1)],
    "order_id": returned["order_id"].to_numpy(),
    "return_date": (returned["order_date"].to_numpy() + return_delay),
    "reason": rng.choice(["Damaged", "Expired", "Wrong item", "Changed mind"], len(returned)),
})
returns["return_date"] = pd.to_datetime(returns["return_date"]).dt.strftime("%Y-%m-%d")

# ---------------------------------------------------------------- 4. Inject known errors
# Each error type gets its own set of rows, so the counts in the catalog are exact.
sales["order_date"] = sales["order_date"].dt.strftime("%Y-%m-%d")
sales["customer_id"] = sales["customer_id"].astype(object)

permutation = rng.permutation(len(sales))
position = 0


def take(fraction):
    """Return the next block of unused row positions."""
    global position
    n = int(N_ORDERS * fraction)
    rows = permutation[position:position + n]
    position += n
    return rows


catalog = []

rows = take(0.03)
sales.iloc[rows, sales.columns.get_loc("order_date")] = pd.to_datetime(
    sales.iloc[rows]["order_date"]
).dt.strftime("%d/%m/%Y")
catalog.append(("mixed_date_format", len(rows), "Date written as DD/MM/YYYY instead of YYYY-MM-DD"))

rows = take(0.01)
sales.iloc[rows, sales.columns.get_loc("customer_id")] = None
catalog.append(("missing_customer_id", len(rows), "customer_id is empty"))

rows = take(0.02)
sales.iloc[rows, sales.columns.get_loc("branch_id")] = (
    sales.iloc[rows]["branch_id"].str.lower() + " "
)
catalog.append(("dirty_branch_id", len(rows), "branch_id in lowercase with a trailing space"))

rows = take(0.005)
sales.iloc[rows, sales.columns.get_loc("quantity")] = -sales.iloc[rows]["quantity"]
catalog.append(("negative_quantity", len(rows), "quantity is negative"))

rows = take(0.02)
sales.iloc[rows, sales.columns.get_loc("discount")] = np.nan
catalog.append(("missing_discount", len(rows), "discount is empty"))

# Exact duplicate rows, taken from rows that carry no other error.
duplicates = sales.iloc[permutation[position:position + int(N_ORDERS * 0.01)]]
catalog.append(("duplicate_row", len(duplicates), "Exact copy of an existing row"))
sales = pd.concat([sales, duplicates]).sample(frac=1, random_state=SEED).reset_index(drop=True)

# ---------------------------------------------------------------- 5. Write the source files
sales.to_csv(OUT_DIR / "sales.csv", index=False)
returns.to_csv(OUT_DIR / "returns.csv", index=False)
products.to_excel(OUT_DIR / "products.xlsx", index=False)
customers.to_json(OUT_DIR / "customers.json", orient="records", indent=2)
branches.to_json(OUT_DIR / "branches.json", orient="records", indent=2)
pd.DataFrame(catalog, columns=["error_type", "injected_count", "description"]).to_csv(
    OUT_DIR / "error_catalog.csv", index=False
)

print(f"sales rows (with duplicates): {len(sales)}")
print(f"returns rows: {len(returns)}")
for error_type, count, _ in catalog:
    print(f"  {error_type}: {count}")
print(f"Files written to: {OUT_DIR.resolve()}")
