-- ============================================================================
-- 03 - ANALYTICS MODEL (PORTFOLIO VERSION)
-- Fashion Retail Analytics | PostgreSQL
-- ============================================================================
-- Five business-ready views: four dimensions and one final Tableau fact view.

-- 1) DATE DIMENSION: one row per day for the full project period.
CREATE OR REPLACE VIEW analytics.dim_date AS
SELECT
    d::date AS date,
    EXTRACT(YEAR FROM d)::integer AS year,
    EXTRACT(QUARTER FROM d)::integer AS quarter,
    EXTRACT(MONTH FROM d)::integer AS month_number,
    TO_CHAR(d, 'Month') AS month_name,
    DATE_TRUNC('month', d)::date AS month_start
FROM GENERATE_SERIES(DATE '2024-01-01', DATE '2025-12-31', INTERVAL '1 day') AS dates(d);

-- 2) CUSTOMER DIMENSION: keep one recent record for each master customer.
CREATE OR REPLACE VIEW analytics.dim_customers AS
WITH ranked AS (
    SELECT c.*,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY registration_date DESC, source_customer_id
        ) AS row_num
    FROM clean.customers c
)
SELECT
    customer_id, customer_name, gender, birth_date, phone, email, city,
    governorate, registration_date, registration_channel, loyalty_level
FROM ranked WHERE row_num = 1
UNION ALL
SELECT
    'ANONYMOUS', 'عميل غير مسجل', NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, 'Store', NULL;

-- 3) PRODUCT DIMENSION: business attributes used to slice sales.
CREATE OR REPLACE VIEW analytics.dim_products AS
SELECT
    sku, product_name_ar, category, subcategory, gender, color, size, brand,
    supplier_id, standard_cost, list_price, product_status
FROM clean.products;

-- 4) LOCATION DIMENSION: store and warehouse location details.
CREATE OR REPLACE VIEW analytics.dim_locations AS
SELECT
    branch_id AS location_id,
    branch_name_ar AS location_name,
    governorate, city, opening_date, location_type
FROM clean.branches;

-- 5) FINAL SALES FACT: the single analysis table connected to Tableau.
CREATE OR REPLACE VIEW analytics.fact_sales_analysis AS
WITH sales_union AS (
    SELECT
        sales_channel, order_id, line_id, order_date, order_time, branch_id,
        source_customer_id, sku, quantity, unit_price, line_discount,
        net_amount, order_status, NULL::text AS shipping_governorate
    FROM clean.store_sales
    UNION ALL
    SELECT
        sales_channel, order_id, line_id, order_date, order_time, branch_id,
        source_customer_id, sku, quantity, unit_price, line_discount,
        net_amount, order_status, shipping_governorate
    FROM clean.online_sales
), classified AS (
    SELECT s.*,
        COALESCE(c.customer_id, NULLIF(s.source_customer_id, ''), 'ANONYMOUS') AS customer_id,
        CASE
            WHEN s.order_status = 'Cancelled' THEN 'Cancelled'
            WHEN s.order_status IN ('Pending', 'Confirmed', 'Shipped') THEN 'Open'
            ELSE 'Recognized'
        END AS sales_status,
        CASE
            WHEN s.order_status IN ('Completed', 'Delivered', 'Partially Returned', 'Returned')
                THEN s.net_amount ELSE 0::numeric
        END AS recognized_sales_amount
    FROM sales_union s
    LEFT JOIN clean.customers c ON s.source_customer_id = c.source_customer_id
), costed AS (
    SELECT c.*, p.standard_cost,
        CASE
            WHEN c.sales_status <> 'Recognized' THEN 0::numeric
            WHEN p.standard_cost IS NULL THEN NULL::numeric
            ELSE c.quantity * p.standard_cost
        END AS cost_of_goods_sold
    FROM classified c
    LEFT JOIN analytics.dim_products p ON c.sku = p.sku
)
SELECT
    sales_channel, order_id, line_id, order_date, order_time, branch_id,
    customer_id, sku, quantity, unit_price, line_discount, net_amount,
    order_status, shipping_governorate, sales_status, recognized_sales_amount,
    standard_cost, cost_of_goods_sold,
    CASE
        WHEN sales_status <> 'Recognized' THEN 0::numeric
        WHEN standard_cost IS NULL THEN NULL::numeric
        ELSE recognized_sales_amount - cost_of_goods_sold
    END AS gross_profit
FROM costed;
