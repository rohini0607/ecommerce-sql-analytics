-- ============================================================
-- E-Commerce Sales Analytics — MySQL Project (REAL DATA, CORRECTED)
-- Built from Olist Brazilian E-Commerce Kaggle dataset
-- Works on MySQL 8.0+ (needed for window functions)
-- Fix applied: customers now includes customer_unique_id, since
-- Olist's customer_id is a PER-ORDER id, not a per-person id.
-- Repeat customer analysis must use customer_unique_id instead.
-- ============================================================

DROP DATABASE IF EXISTS ecommerce_analytics;
CREATE DATABASE ecommerce_analytics;
USE ecommerce_analytics;

-- ------------------------------------------------------------
-- 1. TABLES
-- ------------------------------------------------------------

CREATE TABLE customers (
    customer_id         VARCHAR(64) PRIMARY KEY,
    customer_unique_id  VARCHAR(64),
    city                VARCHAR(100),
    state               VARCHAR(10)
);

CREATE TABLE products (
    product_id    VARCHAR(64) PRIMARY KEY,
    category      VARCHAR(100)
);

CREATE TABLE orders (
    order_id      VARCHAR(64) PRIMARY KEY,
    customer_id   VARCHAR(64),
    order_date    DATETIME,
    status        VARCHAR(20),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id VARCHAR(80) PRIMARY KEY,
    order_id      VARCHAR(64),
    product_id    VARCHAR(64),
    quantity      INT NOT NULL DEFAULT 1,
    price         DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- ------------------------------------------------------------
-- 2. IMPORT THE CLEANED CSVs
-- Copy clean_customers.csv, clean_products.csv, clean_orders.csv,
-- clean_order_items.csv into your MySQL secure folder first.
-- Find it with: SHOW VARIABLES LIKE 'secure_file_priv';
-- Then use the FULL path (forward slashes) in each LOAD statement below.
-- ------------------------------------------------------------

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean_customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, customer_unique_id, city, state);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean_products.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, category);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean_orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, order_date, status);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean_order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_item_id, order_id, product_id, quantity, price);

-- ============================================================
-- 3. THE 6 BUSINESS QUESTIONS
-- ============================================================

-- Q1: Top 10 products by total revenue
SELECT
    p.category,
    p.product_id,
    SUM(oi.quantity * oi.price) AS total_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_id, p.category
ORDER BY total_revenue DESC
LIMIT 10;


-- Q2: Monthly revenue growth %
-- Note: 2016 data is negligible (Olist test volume before real launch in 2017),
-- so early growth % swings wildly. Worth excluding 2016 in your write-up if
-- you want cleaner trend numbers: add WHERE o.order_date >= '2017-01-01'
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(o.order_date, '%Y-%m') AS month,
        SUM(oi.quantity * oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month) * 100, 2
    ) AS growth_pct
FROM monthly_revenue
ORDER BY month;


-- Q3: Rank customers by total spend within each state
SELECT
    c.state,
    c.customer_id,
    SUM(oi.quantity * oi.price) AS total_spend,
    RANK() OVER (PARTITION BY c.state ORDER BY SUM(oi.quantity * oi.price) DESC) AS spend_rank
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.state, c.customer_id;


-- Q4: Repeat customer rate (CORRECTED)
-- Olist's customer_id is generated fresh per ORDER, not per person.
-- The real "same human" identifier is customer_unique_id, so repeat
-- purchase behavior must be measured through that column instead.
WITH customer_order_counts AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS num_orders
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    (SELECT COUNT(*) FROM customer_order_counts WHERE num_orders > 1) AS repeat_customers,
    (SELECT COUNT(*) FROM customer_order_counts) AS total_unique_customers,
    ROUND(
        (SELECT COUNT(*) FROM customer_order_counts WHERE num_orders > 1) * 100.0
        / (SELECT COUNT(*) FROM customer_order_counts), 2
    ) AS repeat_rate_pct
FROM customer_order_counts
LIMIT 1;


-- Q5: Orders with no matching customer record (data quality check)
SELECT o.order_id, o.customer_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


-- Q6: Running total of daily revenue
SELECT
    DATE(o.order_date) AS order_day,
    SUM(oi.quantity * oi.price) AS daily_revenue,
    SUM(SUM(oi.quantity * oi.price)) OVER (ORDER BY DATE(o.order_date)) AS running_total
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY DATE(o.order_date)
ORDER BY order_day;
