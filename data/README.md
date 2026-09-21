# Data Files

The original CSV files are not included in this repository because of their size.

The project used the following source datasets:

- `branches.csv`
- `customers.csv`
- `inventory_movements.csv`
- `monthly_targets.csv`
- `online_order_items.csv`
- `online_orders.csv`
- `payments.csv`
- `products.csv`
- `purchase_order_items.csv`
- `purchase_orders.csv`
- `returns.csv`
- `shipments.csv`
- `store_sales.csv`
- `suppliers.csv`

Place the CSV files in this folder before running:

```bash
python python/load_csv_to_postgres.py
```

The Python script loads the source data into PostgreSQL's `raw` schema. The SQL
scripts then clean and transform the data into the `clean` and `analytics` schemas.
