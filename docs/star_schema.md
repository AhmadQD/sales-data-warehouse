Star Schema Design — sales-data-warehouse
Purpose
This document describes the dimensional model (star schema) used in the Warehouse layer. It is the contract that the ETL and all analytical queries depend on.

Note: All source data is synthetic (generated with SEED=42 in scripts/generate_data.py). No real customer or sales data is used.

Overview
The warehouse follows a classic star schema:

1 fact table: fact_sales

> **Grain assumption**: one row per `order_id`. This holds for the current
> synthetic dataset (each order contains a single product). In a real
> retail scenario, an order may contain multiple line items; the grain
> would then become "one row per sales line", and a `sales_line_id`
> surrogate key would replace `order_id` as the deduplication key.

4 dimension tables: dim_date, dim_customer, dim_product, dim_branch

1 degenerate dimension: order_id (stored inside fact_sales, no separate table)

text
dim_date      ─┐
dim_customer  ─┤
dim_product   ─┼──►  fact_sales
dim_branch    ─┘
Every relationship is many-to-one from fact_sales to a dimension.

Fact Table: fact_sales
One row per valid sales line (after cleaning and validation in the Staging layer).

Column	Type	Role
sales_key	BIGSERIAL PK	Surrogate key for the fact row
order_id	INTEGER	Degenerate dimension (source order id)
date_key	INTEGER FK	→ dim_date.date_key
customer_key	BIGINT FK	→ dim_customer.customer_key
product_key	BIGINT FK	→ dim_product.product_key
branch_key	BIGINT FK	→ dim_branch.branch_key
quantity	INTEGER	Units sold
unit_price	NUMERIC(10,2)	Price per unit at time of sale
discount	NUMERIC(5,4)	Discount rate (0.0 – 1.0)
gross_amount	NUMERIC(12,2)	quantity * unit_price
net_amount	NUMERIC(12,2)	gross_amount * (1 - discount)
cost_amount	NUMERIC(12,2)	quantity * unit_cost (from dim_product)
profit_amount	NUMERIC(12,2)	net_amount - cost_amount
Why profit is stored (not computed in queries)
Questions 6 (most profitable categories) and 7 (return rate per product) are used repeatedly.

unit_cost comes from dim_product and may change over time. We snapshot it into the fact row at load time.

gross_amount, net_amount, cost_amount, profit_amount are all kept separately so any consumer can audit the calculation (DBA-friendly).

Dimension: dim_date
A pre-populated date dimension covering the data range (2020-01-01 → 2030-12-31).

Column	Type	Notes
date_key	INTEGER PK	Format YYYYMMDD (e.g. 20240115)
full_date	DATE	Unique
year	SMALLINT	
quarter	SMALLINT	1–4
month	SMALLINT	1–12
month_name	TEXT	
day	SMALLINT	1–31
day_of_week	SMALLINT	0 = Sunday … 6 = Saturday
is_weekend	BOOLEAN	
Why date_key = YYYYMMDD
Sorts naturally without conversion (20240115 > 20231231).

Readable in queries and reports.

Small integer → fast joins and indexes.

Dimension: dim_customer
Column	Type	Notes
customer_key	BIGSERIAL PK	Surrogate key
customer_id	INTEGER	Natural key (UNIQUE), source id
name	TEXT	
city	TEXT	
valid_from	TIMESTAMP	SCD scaffolding
valid_to	TIMESTAMP	SCD scaffolding (default '9999-12-31')
is_current	BOOLEAN	SCD scaffolding (default TRUE)
SCD Type 2 — structural only (for now)
The source data has no change history, so implementing full SCD Type 2 would be artificial for a 4-week project. We keep the columns so the model is ready for Type 2, but load a single row per customer:

valid_from = load_timestamp

valid_to = '9999-12-31'

is_current = TRUE

Dimension: dim_product
Column	Type	Notes
product_key	BIGSERIAL PK	Surrogate key
product_id	INTEGER	Natural key (UNIQUE)
product_name	TEXT	
category	TEXT	
unit_cost	NUMERIC(10,2)	Current cost per unit
unit_cost lives here for reference; the value used in any given sale is snapshotted into fact_sales.cost_amount.

Dimension: dim_branch
Column	Type	Notes
branch_key	BIGSERIAL PK	Surrogate key
branch_id	TEXT	Natural key (UNIQUE), cleaned (trim/lower)
branch_name	TEXT	
city	TEXT	
The source branch_id is dirty (e.g. "b01 " with trailing space, mixed case). Cleaning happens in Staging; only cleaned values land here.

Degenerate Dimension: order_id
order_id has no attributes of its own, so no separate dimension table. It is stored directly in fact_sales. It is needed to link returns (question 7) at a later step.

Not modeled yet (deliberately)
fact_returns
Returns are a separate fact (3,000 rows, different grain: one row per return, not per sale). Mixing them into fact_sales would break the grain. Decision deferred to Step 5, when the ETL is designed.

Error tracking
Injected errors (mixed_date_format, missing_customer_id, etc.) are handled in Staging and logged. They never reach the warehouse. error_catalog.csv is used to measure ETL detection accuracy (question 8) — it is not a warehouse table.

Mapping: Analytical Questions → Schema
#	Question	Tables used
1	Monthly & yearly total sales	fact_sales + dim_date
2	Top 10 / bottom 10 products	fact_sales + dim_product
3	Branch performance comparison	fact_sales + dim_branch
4	Top customers by purchase	fact_sales + dim_customer
5	Sales growth vs previous period	fact_sales + dim_date
6	Most profitable categories	fact_sales + dim_product (profit_amount)
7	Return rate per product	fact_sales + fact_returns (Step 5)
8	Corrected / rejected records per load	ETL logs (Staging) — not warehouse tables
Design Principles Applied
Surrogate keys on every dimension → decouple from source, support SCD, faster joins.

Natural keys kept as UNIQUE columns → traceability and dedup.

Profit snapshot in fact → correct history, auditable.

Date dimension pre-built → simpler, faster time queries.

One grain per fact table → no mixing sales and returns.

No speculative tables → only what an analytical question requires.