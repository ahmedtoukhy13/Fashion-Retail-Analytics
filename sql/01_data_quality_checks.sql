-- ============================================================================
-- 01 - DATA QUALITY CHECKS
-- Fashion Retail Analytics | PostgreSQL
-- ============================================================================
-- These queries do not change data. Run one section at a time and review it.
-- A result of zero is normally the expected result for problem-count checks.

-- 1) Row counts: confirms that the main analytics views contain data.
SELECT 'fact_sales_analysis' AS dataset, COUNT(*) AS row_count
FROM analytics.fact_sales_analysis
UNION ALL
SELECT 'dim_products', COUNT(*) FROM analytics.dim_products
UNION ALL
SELECT 'dim_customers', COUNT(*) FROM analytics.dim_customers;

-- 2) Sales date coverage: confirms that sales stay inside the project period.
SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    COUNT(*) AS sales_lines
FROM analytics.fact_sales_analysis;

-- 3) Duplicate sales lines: should return zero rows.
SELECT sales_channel, line_id, COUNT(*) AS duplicate_count
FROM analytics.fact_sales_analysis
GROUP BY sales_channel, line_id
HAVING COUNT(*) > 1;

-- 4) Missing product matches: should be zero or fully explained.
SELECT COUNT(*) AS sales_lines_without_product
FROM analytics.fact_sales_analysis
WHERE standard_cost IS NULL;

-- 5) Invalid numeric values: should return zero rows.
SELECT order_id, line_id, quantity, unit_price, line_discount, net_amount
FROM analytics.fact_sales_analysis
WHERE quantity <= 0
   OR unit_price < 0
   OR line_discount < 0
   OR net_amount < 0;

-- 6) Reconciliation by channel: useful for checking Tableau totals.
SELECT
    sales_channel,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(recognized_sales_amount) AS recognized_sales,
    SUM(cost_of_goods_sold) AS cost_of_goods_sold,
    SUM(gross_profit) AS gross_profit
FROM analytics.fact_sales_analysis
GROUP BY sales_channel
ORDER BY sales_channel;

-- 7) Overall dashboard KPIs.
SELECT
    SUM(recognized_sales_amount) AS total_sales,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(gross_profit) AS gross_profit,
    ROUND(100 * SUM(gross_profit) / NULLIF(SUM(recognized_sales_amount), 0), 1) AS gross_margin_pct,
ROUND(
    SUM(recognized_sales_amount) /
    NULLIF(COUNT(DISTINCT order_id) FILTER (WHERE sales_status = 'Recognized'), 0),
    2
) AS average_order_valueFROM analytics.fact_sales_analysis;
