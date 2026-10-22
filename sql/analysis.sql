-- Olist | SQLite
-- Revenue excludes freight. Delivery dates are compared by calendar day.

-- Analysis views
DROP VIEW IF EXISTS monthly_summary;
DROP VIEW IF EXISTS order_analysis;
DROP VIEW IF EXISTS clean_orders;

CREATE VIEW clean_orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    datetime(NULLIF(TRIM(order_purchase_timestamp), '')) AS purchase_date,
    datetime(NULLIF(TRIM(order_approved_at), '')) AS approved_date,
    datetime(NULLIF(TRIM(order_delivered_carrier_date), '')) AS carrier_delivery_date,
    datetime(NULLIF(TRIM(order_delivered_customer_date), '')) AS delivery_date,
    datetime(NULLIF(TRIM(order_estimated_delivery_date), '')) AS estimated_delivery_date
FROM orders;

CREATE VIEW order_analysis AS
WITH item_totals AS (
    SELECT
        order_id,
        COUNT(*) AS item_count,
        SUM(price) AS product_revenue,
        SUM(freight_value) AS freight_total
    FROM order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total
    FROM payments
    GROUP BY order_id
),
review_totals AS (
    SELECT
        order_id,
        AVG(review_score) AS average_review_score,
        COUNT(review_score) AS review_count
    FROM reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.purchase_date,
    o.delivery_date,
    o.estimated_delivery_date,
    CASE
        WHEN o.order_status <> 'delivered' THEN NULL
        WHEN o.delivery_date IS NULL
          OR o.estimated_delivery_date IS NULL THEN NULL
        WHEN date(o.delivery_date) > date(o.estimated_delivery_date) THEN 1
        ELSE 0
    END AS late_delivery_flag,
    i.item_count,
    i.product_revenue,
    i.freight_total,
    p.payment_total,
    r.average_review_score,
    r.review_count
FROM clean_orders AS o
LEFT JOIN item_totals AS i ON o.order_id = i.order_id
LEFT JOIN payment_totals AS p ON o.order_id = p.order_id
LEFT JOIN review_totals AS r ON o.order_id = r.order_id;

-- Monthly summary
CREATE VIEW monthly_summary AS
SELECT
    strftime('%Y-%m', purchase_date) AS order_month,
    COUNT(*) AS orders_placed,
    SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END) AS delivered_orders,
    ROUND(
        SUM(CASE WHEN order_status = 'delivered' THEN product_revenue ELSE 0 END),
        2
    ) AS delivered_product_revenue,
    ROUND(
        100.0 * SUM(CASE WHEN late_delivery_flag = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN late_delivery_flag IS NOT NULL THEN 1 ELSE 0 END), 0),
        2
    ) AS late_rate_pct
FROM order_analysis
WHERE purchase_date IS NOT NULL
GROUP BY strftime('%Y-%m', purchase_date);

-- Q1. Monthly orders and revenue
SELECT *
FROM monthly_summary
ORDER BY order_month;

-- Q2a. Overall late delivery rate
SELECT
    COUNT(*) AS delivered_orders_with_valid_dates,
    SUM(late_delivery_flag) AS late_orders,
    ROUND(100.0 * SUM(late_delivery_flag) / COUNT(*), 2) AS late_rate_pct
FROM order_analysis
WHERE order_status = 'delivered'
  AND late_delivery_flag IS NOT NULL;

-- Q2b. Top categories by revenue
-- Orders may appear in more than one category.
WITH category_orders AS (
    SELECT
        COALESCE(t.product_category_name_english,
                 p.product_category_name,
                 'Unknown') AS category_name,
        a.order_id,
        SUM(oi.price) AS product_revenue,
        MAX(a.late_delivery_flag) AS late_delivery_flag
    FROM order_analysis AS a
    JOIN order_items AS oi ON a.order_id = oi.order_id
    JOIN products AS p ON oi.product_id = p.product_id
    LEFT JOIN category_translation AS t
        ON p.product_category_name = t.product_category_name
    WHERE a.order_status = 'delivered'
      AND a.late_delivery_flag IS NOT NULL
    GROUP BY
        COALESCE(t.product_category_name_english,
                 p.product_category_name,
                 'Unknown'),
        a.order_id
)
SELECT
    category_name,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(product_revenue), 2) AS product_revenue,
    SUM(late_delivery_flag) AS late_orders,
    ROUND(100.0 * SUM(late_delivery_flag) / COUNT(*), 2) AS late_rate_pct
FROM category_orders
GROUP BY category_name
ORDER BY product_revenue DESC
LIMIT 10;

-- Q3. Reviews: late vs. on time
-- Mean review score per order; association only.
SELECT
    CASE
        WHEN late_delivery_flag = 1 THEN 'Late'
        ELSE 'On time'
    END AS delivery_group,
    COUNT(*) AS orders_with_reviews,
    ROUND(AVG(average_review_score), 2) AS average_review_score
FROM order_analysis
WHERE order_status = 'delivered'
  AND late_delivery_flag IS NOT NULL
  AND average_review_score IS NOT NULL
GROUP BY late_delivery_flag
ORDER BY late_delivery_flag DESC;

-- Q4. Top sellers by revenue
-- Orders may appear under more than one seller.
WITH seller_orders AS (
    SELECT
        oi.seller_id,
        a.order_id,
        SUM(oi.price) AS product_revenue,
        MAX(a.late_delivery_flag) AS late_delivery_flag
    FROM order_analysis AS a
    JOIN order_items AS oi ON a.order_id = oi.order_id
    WHERE a.order_status = 'delivered'
      AND a.late_delivery_flag IS NOT NULL
    GROUP BY oi.seller_id, a.order_id
)
SELECT
    seller_id,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(product_revenue), 2) AS product_revenue,
    SUM(late_delivery_flag) AS late_orders,
    ROUND(100.0 * SUM(late_delivery_flag) / COUNT(*), 2) AS late_rate_pct
FROM seller_orders
GROUP BY seller_id
ORDER BY product_revenue DESC
LIMIT 10;

-- Q5. Repeat customers within the dataset period
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders
    FROM orders AS o
    JOIN customers AS c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN delivered_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_group,
    COUNT(*) AS customers,
    SUM(delivered_orders) AS delivered_orders
FROM customer_orders
GROUP BY customer_group
ORDER BY delivered_orders DESC;
