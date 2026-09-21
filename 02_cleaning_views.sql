-- ============================================================================
-- 02 - CLEANING VIEWS (PORTFOLIO VERSION)
-- Fashion Retail Analytics | PostgreSQL
-- ============================================================================
-- Six understandable views replace the many small technical staging views.
-- Each WITH block is a temporary step inside one view, not another saved view.

-- 1) BRANCHES: standardize IDs, names, locations, and dates.
CREATE OR REPLACE VIEW clean.branches AS
SELECT
    UPPER(BTRIM(branch_id)) AS branch_id,
    BTRIM(branch_name_ar) AS branch_name_ar,
    BTRIM(governorate) AS governorate,
    BTRIM(city) AS city,
    NULLIF(BTRIM(opening_date), '')::date AS opening_date,
    BTRIM(location_type) AS location_type
FROM raw.branches;

-- 2) PRODUCTS: deduplicate SKU records and standardize colors, sizes, and prices.
CREATE OR REPLACE VIEW clean.products AS
WITH ranked AS (
    SELECT p.*,
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(BTRIM(sku))
            ORDER BY _loaded_at DESC, _source_row_number DESC
        ) AS row_num
    FROM raw.products p
)
SELECT
    UPPER(BTRIM(product_id)) AS product_id,
    UPPER(BTRIM(style_code)) AS style_code,
    UPPER(BTRIM(sku)) AS sku,
    BTRIM(product_name_ar) AS product_name_ar,
    BTRIM(category) AS category,
    BTRIM(subcategory) AS subcategory,
    BTRIM(gender) AS gender,
    CASE UPPER(BTRIM(color))
        WHEN 'BRG' THEN 'نبيتي' WHEN 'GREEN' THEN 'أخضر'
        WHEN 'WHT' THEN 'أبيض' WHEN 'BEIGE' THEN 'بيج'
        WHEN 'BLK' THEN 'أسود' WHEN 'GRAY' THEN 'رمادي'
        WHEN 'NAVY' THEN 'كحلي' WHEN 'ابيض' THEN 'أبيض'
        WHEN 'ازرق' THEN 'أزرق' ELSE BTRIM(color)
    END AS color,
    CASE UPPER(BTRIM(size))
        WHEN 'SMALL' THEN 'S' WHEN 'MEDIUM' THEN 'M'
        WHEN 'LARGE' THEN 'L' WHEN 'X LARGE' THEN 'XL'
        ELSE UPPER(BTRIM(size))
    END AS size,
    BTRIM(brand) AS brand,
    UPPER(BTRIM(supplier_id)) AS supplier_id,
    NULLIF(BTRIM(standard_cost), '')::numeric(12,2) AS standard_cost,
    NULLIF(BTRIM(list_price), '')::numeric(12,2) AS list_price,
    NULLIF(BTRIM(launch_date), '')::date AS launch_date,
    BTRIM(product_status) AS product_status
FROM ranked
WHERE row_num = 1;

-- 3) CUSTOMERS: clean contact data and assign duplicate people one master ID.
CREATE OR REPLACE VIEW clean.customers AS
WITH prepared AS (
    SELECT
        UPPER(BTRIM(customer_id)) AS source_customer_id,
        REGEXP_REPLACE(BTRIM(customer_name), '\s+', ' ', 'g') AS customer_name,
        BTRIM(gender) AS gender,
        NULLIF(BTRIM(birth_date), '')::date AS birth_date,
        REGEXP_REPLACE(phone, '[^0-9]', '', 'g') AS phone_digits,
        LOWER(REGEXP_REPLACE(BTRIM(email), '\s+', '', 'g')) AS email,
        BTRIM(city) AS city,
        BTRIM(governorate) AS governorate,
        NULLIF(BTRIM(registration_date), '')::date AS registration_date,
        BTRIM(registration_channel) AS registration_channel,
        BTRIM(loyalty_level) AS loyalty_level
    FROM raw.customers
), normalized AS (
    SELECT prepared.*,
        CASE
            WHEN LENGTH(phone_digits) = 12 AND phone_digits LIKE '20%'
                THEN '0' || SUBSTRING(phone_digits FROM 3)
            WHEN LENGTH(phone_digits) = 14 AND phone_digits LIKE '0020%'
                THEN '0' || SUBSTRING(phone_digits FROM 5)
            ELSE phone_digits
        END AS phone
    FROM prepared
)
SELECT
    source_customer_id,
    MIN(source_customer_id) OVER (
        PARTITION BY phone, LOWER(customer_name), birth_date
    ) AS customer_id,
    customer_name, gender, birth_date, phone, email, city, governorate,
    registration_date, registration_channel, loyalty_level
FROM normalized;

-- 4) STORE SALES: deduplicate and clean branch, date, SKU, and numeric fields.
CREATE OR REPLACE VIEW clean.store_sales AS
WITH deduplicated AS (
    SELECT s.*,
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(BTRIM(line_id))
            ORDER BY _loaded_at DESC, _source_row_number DESC
        ) AS row_num
    FROM raw.store_sales s
), standardized AS (
    SELECT *,
        CASE LOWER(BTRIM(branch_id))
            WHEN 'nasr city' THEN 'BR001' WHEN 'مدينة نصر' THEN 'BR001'
            WHEN 'فرع مدينة نصر' THEN 'BR001' WHEN 'new cairo' THEN 'BR002'
            WHEN 'القاهرة الجديدة' THEN 'BR002' WHEN 'sheikh zayed' THEN 'BR003'
            WHEN 'الشيخ زايد' THEN 'BR003' WHEN 'alexandria' THEN 'BR004'
            WHEN 'الاسكندريه' THEN 'BR004' WHEN 'mansoura' THEN 'BR005'
            WHEN 'المنصوره' THEN 'BR005' WHEN 'tanta' THEN 'BR006'
            WHEN 'طنطا' THEN 'BR006' ELSE UPPER(BTRIM(branch_id))
        END AS clean_branch_id,
        CASE
            WHEN BTRIM(order_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN BTRIM(order_date)::date
            WHEN BTRIM(order_date) ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
                 AND SPLIT_PART(BTRIM(order_date), '/', 2)::integer > 12
                THEN TO_DATE(BTRIM(order_date), 'MM/DD/YYYY')
            WHEN BTRIM(order_date) ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
                THEN TO_DATE(BTRIM(order_date), 'DD/MM/YYYY')
            ELSE NULL
        END AS clean_order_date,
        COALESCE(NULLIF(UPPER(BTRIM(sku)), ''), 'UNKNOWN') AS clean_sku,
        BTRIM(quantity)::integer AS clean_quantity,
        REPLACE(REPLACE(UPPER(BTRIM(unit_price)), 'EGP', ''), ',', '')::numeric(12,2) AS clean_unit_price,
        REPLACE(REPLACE(UPPER(BTRIM(line_discount)), 'EGP', ''), ',', '')::numeric(12,2) AS clean_discount
    FROM deduplicated WHERE row_num = 1
)
SELECT
    'Store'::text AS sales_channel,
    UPPER(BTRIM(order_id)) AS order_id,
    UPPER(BTRIM(line_id)) AS line_id,
    clean_order_date AS order_date,
    BTRIM(order_time)::time AS order_time,
    clean_branch_id AS branch_id,
    NULLIF(UPPER(BTRIM(customer_id)), '') AS source_customer_id,
    clean_sku AS sku,
    clean_quantity AS quantity,
    clean_unit_price AS unit_price,
    clean_discount AS line_discount,
    clean_quantity * clean_unit_price - clean_discount AS net_amount,
    BTRIM(order_status) AS order_status
FROM standardized;

-- 5) ONLINE SALES: clean orders and items, then join them into sales lines.
CREATE OR REPLACE VIEW clean.online_sales AS
WITH item_ranked AS (
    SELECT i.*,
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(BTRIM(line_id))
            ORDER BY _loaded_at DESC, _source_row_number DESC
        ) AS row_num
    FROM raw.online_order_items i
), items AS (
    SELECT
        UPPER(BTRIM(order_id)) AS order_id,
        UPPER(BTRIM(line_id)) AS line_id,
        COALESCE(NULLIF(UPPER(BTRIM(sku)), ''), 'UNKNOWN') AS sku,
        BTRIM(quantity)::integer AS quantity,
        REPLACE(BTRIM(unit_price), ',', '')::numeric(12,2) AS unit_price,
        REPLACE(BTRIM(line_discount), ',', '')::numeric(12,2) AS line_discount,
        REPLACE(BTRIM(net_amount), ',', '')::numeric(12,2) AS net_amount
    FROM item_ranked WHERE row_num = 1
), orders AS (
    SELECT
        UPPER(BTRIM(order_id)) AS order_id,
        BTRIM(order_date)::date AS order_date,
        BTRIM(order_time)::time AS order_time,
        UPPER(BTRIM(customer_id)) AS source_customer_id,
        BTRIM(order_status) AS order_status,
        CASE LOWER(BTRIM(shipping_governorate))
            WHEN 'alexandria' THEN 'الإسكندرية' WHEN 'cairo' THEN 'القاهرة'
            WHEN 'giza' THEN 'الجيزة' WHEN 'القاهره' THEN 'القاهرة'
            ELSE BTRIM(shipping_governorate)
        END AS shipping_governorate
    FROM raw.online_orders
)
SELECT
    'Online'::text AS sales_channel,
    o.order_id, i.line_id, o.order_date, o.order_time,
    NULL::text AS branch_id, o.source_customer_id,
    i.sku, i.quantity, i.unit_price, i.line_discount, i.net_amount,
    o.order_status, o.shipping_governorate
FROM items i
JOIN orders o ON i.order_id = o.order_id;

-- 6) RETURNS: clean values and repair invalid sales-line references when possible.
CREATE OR REPLACE VIEW clean.returns AS
WITH prepared AS (
    SELECT
        UPPER(BTRIM(return_id)) AS return_id,
        UPPER(BTRIM(original_order_id)) AS original_order_id,
        UPPER(BTRIM(original_line_id)) AS original_line_id,
        BTRIM(return_date)::date AS return_date,
        BTRIM(return_channel) AS return_channel,
        NULLIF(UPPER(BTRIM(branch_id)), '') AS branch_id,
        UPPER(BTRIM(sku)) AS sku,
        BTRIM(returned_quantity)::integer AS returned_quantity,
        BTRIM(return_reason) AS return_reason,
        BTRIM(item_condition) AS item_condition,
        REPLACE(BTRIM(refund_amount), ',', '')::numeric(12,2) AS refund_amount,
        BTRIM(return_status) AS return_status,
        BTRIM(inventory_action) AS inventory_action
    FROM raw.returns
), sales_lines AS (
    SELECT order_id, line_id, sku FROM clean.store_sales
    UNION ALL
    SELECT order_id, line_id, sku FROM clean.online_sales
)
SELECT
    r.return_id, r.original_order_id,
    COALESCE(valid_line.line_id, matching_line.line_id, r.original_line_id) AS original_line_id,
    r.return_date, r.return_channel, r.branch_id, r.sku, r.returned_quantity,
    r.return_reason, r.item_condition, r.refund_amount, r.return_status,
    r.inventory_action,
    CASE
        WHEN valid_line.line_id IS NOT NULL THEN 'VALID'
        WHEN matching_line.line_id IS NOT NULL THEN 'CORRECTED'
        ELSE 'UNMATCHED'
    END AS reference_status
FROM prepared r
LEFT JOIN LATERAL (
    SELECT MIN(line_id) AS line_id FROM sales_lines
    WHERE line_id = r.original_line_id
) valid_line ON TRUE
LEFT JOIN LATERAL (
    SELECT MIN(line_id) AS line_id FROM sales_lines
    WHERE order_id = r.original_order_id AND sku = r.sku
) matching_line ON valid_line.line_id IS NULL;
