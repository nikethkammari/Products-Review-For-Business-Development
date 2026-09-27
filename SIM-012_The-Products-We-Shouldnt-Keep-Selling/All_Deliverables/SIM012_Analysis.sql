-- 01_Data_Cleaning
UPDATE products 
SET product_name = TRIM(product_name),
    category = CASE 
        WHEN LOWER(TRIM(category)) IN ('audio - wireless', 'wireless audio') THEN 'Wireless Audio'
        WHEN LOWER(TRIM(category)) = 'mobile accessories' THEN 'Mobile Accessories'
        WHEN LOWER(TRIM(category)) = 'smart accessories' THEN 'Smart Accessories'
        WHEN LOWER(TRIM(category)) = 'smart home' THEN 'Smart Home'
        WHEN LOWER(TRIM(category)) = 'computer accessories' THEN 'Computer Accessories'
        WHEN LOWER(TRIM(category)) = 'personal electronics' THEN 'Personal Electronics'
        WHEN LOWER(TRIM(category)) = 'wearables' THEN 'Wearables'
        ELSE INITCAP(category) END;

-- 02_Sales_Margin_Baseline
SELECT p.product_id, p.product_name, p.category,
       SUM(s.gross_sales) AS gross_sales,
       SUM(s.discount_amount) AS discount_amount,
       SUM(s.net_sales) AS net_sales,
       SUM(s.quantity * p.unit_cost) AS total_cost,
       (SUM(s.net_sales) - SUM(s.quantity * p.unit_cost)) / SUM(s.net_sales) * 100 AS effective_margin_pct
FROM products p
JOIN sales_orders s ON p.product_id = s.product_id
GROUP BY p.product_id, p.product_name, p.category;

-- 03_Return_Analysis (Use LEFT JOIN to retain items without returns)
SELECT p.product_id,
       COUNT(DISTINCT r.return_id) AS returned_orders,
       COALESCE(SUM(r.refund_amount), 0) AS total_refund_amount,
       (COUNT(DISTINCT r.return_id) * 1.0 / COUNT(DISTINCT s.order_id)) * 100 AS return_rate_pct
FROM products p
JOIN sales_orders s ON p.product_id = s.product_id
LEFT JOIN returns r ON p.product_id = r.product_id
GROUP BY p.product_id;

-- 04_Rating_Analysis
SELECT p.product_id, AVG(r.rating) AS avg_rating, COUNT(r.review_id) AS total_reviews
FROM products p
LEFT JOIN product_reviews r ON p.product_id = r.product_id
GROUP BY p.product_id;

-- 05_Campaign_Efficiency
SELECT p.product_id, SUM(c.campaign_spend) AS total_spend, SUM(c.attributed_revenue) AS attributed_rev,
       CASE WHEN SUM(c.campaign_spend) > 0 THEN SUM(c.attributed_revenue) / SUM(c.campaign_spend) ELSE 0 END AS roas
FROM products p
LEFT JOIN product_campaign_performance c ON p.product_id = c.product_id
GROUP BY p.product_id;

-- 06_Product_Age
SELECT product_id, product_name, launch_date,
       DATEDIFF('2026-08-24', launch_date) AS days_since_launch,
       CASE WHEN DATEDIFF('2026-08-24', launch_date) <= 90 THEN 'Immature' ELSE 'Mature' END AS maturity_status
FROM products;

-- 07_Portfolio_Summary


CREATE OR REPLACE VIEW portfolio_summary AS
WITH product_sales AS (
    SELECT 
        product_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(quantity) AS total_units_sold,
        SUM(gross_sales) AS total_gross_sales,
        SUM(discount_amount) AS total_discount_amount,
        SUM(net_sales) AS total_net_sales
    FROM sales_orders
    GROUP BY product_id
),
product_returns AS (
    SELECT 
        product_id,
        COUNT(DISTINCT return_id) AS total_returns,
        SUM(refund_amount) AS total_refund_amount
    FROM returns
    GROUP BY product_id
),
product_reviews_agg AS (
    SELECT 
        product_id,
        COUNT(review_id) AS total_reviews,
        ROUND(AVG(rating)::numeric, 2) AS avg_rating
    FROM product_reviews
    GROUP BY product_id
),
product_marketing AS (
    SELECT 
        product_id,
        SUM(campaign_spend) AS total_marketing_spend,
        SUM(attributed_revenue) AS total_attributed_revenue
    FROM product_campaign_performance
    GROUP BY product_id
)
SELECT 
    p.product_id,
    p.product_name,
    p.category,
    p.launch_date,
    ('2025-03-31'::date - p.launch_date::date) AS product_age_days,
    p.selling_price,
    p.unit_cost,
    
    -- Sales Metrics
    COALESCE(s.total_orders, 0) AS total_orders,
    COALESCE(s.total_units_sold, 0) AS total_units_sold,
    COALESCE(s.total_gross_sales, 0) AS total_gross_sales,
    COALESCE(s.total_discount_amount, 0) AS total_discount_amount,
    COALESCE(s.total_net_sales, 0) AS total_net_sales,
    
    -- Margin & Return Metrics
    ROUND(((p.selling_price - p.unit_cost) / NULLIF(p.selling_price, 0))::numeric, 4) AS gross_margin_pct,
    COALESCE(r.total_returns, 0) AS total_returns,
    ROUND((COALESCE(r.total_returns, 0)::numeric / NULLIF(s.total_orders, 0))::numeric, 4) AS return_rate_pct,
    COALESCE(r.total_refund_amount, 0) AS total_refund_amount,
    
    -- Realized Net Margin
    (COALESCE(s.total_net_sales, 0) - COALESCE(r.total_refund_amount, 0)) AS realized_net_revenue,
    
    -- Review & Marketing Metrics
    COALESCE(rv.avg_rating, 0) AS avg_rating,
    COALESCE(m.total_marketing_spend, 0) AS total_marketing_spend,
    COALESCE(m.total_attributed_revenue, 0) AS total_attributed_revenue,
    ROUND((COALESCE(m.total_attributed_revenue, 0)::numeric / NULLIF(m.total_marketing_spend, 0))::numeric, 2) AS roas,
    
    -- Archetype Classification Logic
    CASE 
        WHEN ('2025-03-31'::date - p.launch_date::date) < 90 THEN 'Immature Product'
        WHEN COALESCE(s.total_net_sales, 0) > 10000000 AND (p.selling_price - p.unit_cost) < 200 THEN 'Revenue Trap'
        WHEN ((p.selling_price - p.unit_cost) / NULLIF(p.selling_price, 0)) >= 0.35 
             AND COALESCE(rv.avg_rating, 0) >= 4.0 
             AND (COALESCE(r.total_returns, 0)::numeric / NULLIF(s.total_orders, 0)) < 0.05 THEN 'Star'
        WHEN ((p.selling_price - p.unit_cost) / NULLIF(p.selling_price, 0)) >= 0.35 
             AND COALESCE(rv.avg_rating, 0) >= 4.0 
             AND COALESCE(m.total_marketing_spend, 0) < 100000 THEN 'Hidden Opportunity'
        ELSE 'Weak Product'
    END AS strategic_archetype

FROM products p
LEFT JOIN product_sales s ON p.product_id = s.product_id
LEFT JOIN product_returns r ON p.product_id = r.product_id
LEFT JOIN product_reviews_agg rv ON p.product_id = rv.product_id
LEFT JOIN product_marketing m ON p.product_id = m.product_id
ORDER BY total_net_sales DESC;