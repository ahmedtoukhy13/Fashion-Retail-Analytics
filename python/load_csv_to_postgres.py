"""Load the project's CSV files into the PostgreSQL raw schema.

The raw layer keeps source values unchanged. Data cleaning is handled later
by the SQL views in the project's sql folder.
"""

import csv
import os
import re
from datetime import datetime, timezone
from getpass import getpass
from pathlib import Path

import psycopg
from psycopg import sql


# Connection settings. The password is requested when the script starts,
# so it is never saved inside the project or uploaded to GitHub.
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME", "fashion_retail_analytics"),
    "user": os.getenv("DB_USER", "postgres"),
}

DATA_FOLDER = Path(__file__).resolve().parents[1] / "data"

# CSV filenames should match one of these raw table names.
RAW_TABLES = {
    "branches",
    "customers",
    "inventory_movements",
    "monthly_targets",
    "online_order_items",
    "online_orders",
    "payments",
    "products",
    "purchase_order_items",
    "purchase_orders",
    "returns",
    "shipments",
    "store_sales",
    "suppliers",
}


def table_name_from_file(file_path: Path) -> str:
    """Convert a CSV filename such as Store_Sales.csv to store_sales."""
    table_name = re.sub(r"[^a-z0-9]+", "_", file_path.stem.lower()).strip("_")
    if table_name not in RAW_TABLES:
        raise ValueError(f"No raw table is configured for {file_path.name}")
    return table_name


def load_csv(connection: psycopg.Connection, file_path: Path) -> int:
    """Insert one CSV file into its matching raw table and return row count."""
    table_name = table_name_from_file(file_path)
    loaded_at = datetime.now(timezone.utc)

    with file_path.open("r", encoding="utf-8-sig", newline="") as csv_file:
        reader = csv.DictReader(csv_file)
        if not reader.fieldnames:
            return 0

        source_columns = reader.fieldnames
        insert_columns = source_columns + [
            "_source_file",
            "_source_row_number",
            "_loaded_at",
        ]

        statement = sql.SQL("INSERT INTO {}.{} ({}) VALUES ({})").format(
            sql.Identifier("raw"),
            sql.Identifier(table_name),
            sql.SQL(", ").join(map(sql.Identifier, insert_columns)),
            sql.SQL(", ").join(sql.Placeholder() for _ in insert_columns),
        )

        rows = []
        for row_number, row in enumerate(reader, start=2):
            values = [row[column] for column in source_columns]
            values.extend([file_path.name, row_number, loaded_at])
            rows.append(values)

        with connection.cursor() as cursor:
            cursor.executemany(statement, rows)

    return len(rows)


def main() -> None:
    csv_files = sorted(DATA_FOLDER.glob("*.csv"))
    if not csv_files:
        print(f"No CSV files found in: {DATA_FOLDER}")
        return

    password = getpass("PostgreSQL password: ")

    with psycopg.connect(**DB_CONFIG, password=password) as connection:
        for file_path in csv_files:
            row_count = load_csv(connection, file_path)
            print(f"Loaded {row_count:,} rows from {file_path.name}")

    print("CSV loading completed successfully.")


if __name__ == "__main__":
    main()
