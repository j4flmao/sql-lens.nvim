-- ============================================================
-- sql-lens.nvim DEMO — SQL Server LocalDB
-- Database: SqlLensDemo (500 users, 10K orders, 30K items, 50K logs)
--
-- Keymaps:
--   <leader>sr  = Run query tai cursor (xem ket qua)
--   <leader>sR  = Run tat ca queries
--   <leader>se  = Explain (xem cost/plan inline)
--   <leader>sd  = Float detail (xem plan chi tiet)
--   <leader>sc  = Chon connection
--   <leader>sq  = Toggle on/off
-- ============================================================

-- ===========================================
-- 1. BASIC: Scan toan bo bang lon (no filter)
--    => Seq Scan, high reads
-- ===========================================
SELECT * FROM activity_logs;

-- ===========================================
-- 2. FILTER: Tim theo cot KHONG co index
--    => Clustered Index Scan (full scan)
-- ===========================================
SELECT * FROM activity_logs
WHERE action = 'login'
AND created_at > '2026-01-01';

-- ===========================================
-- 3. JOIN phuc tap: 3 bang
--    => Nested Loops / Hash Match
-- ===========================================
SELECT
    u.username,
    u.email,
    COUNT(o.id) AS total_orders,
    SUM(o.amount) AS total_spent,
    AVG(o.amount) AS avg_order
FROM users u
INNER JOIN orders o ON o.user_id = u.id
WHERE o.status = 'completed'
GROUP BY u.username, u.email
HAVING SUM(o.amount) > 500
ORDER BY total_spent DESC;

-- ===========================================
-- 4. SUBQUERY + JOIN: Top users by revenue
--    => Cost cao vi scan nhieu bang
-- ===========================================
SELECT
    u.username,
    sub.order_count,
    sub.total_revenue,
    sub.avg_item_price
FROM users u
INNER JOIN (
    SELECT
        o.user_id,
        COUNT(DISTINCT o.id) AS order_count,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount/100)) AS total_revenue,
        AVG(oi.unit_price) AS avg_item_price
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.id
    WHERE o.order_date >= DATEADD(MONTH, -6, GETDATE())
    GROUP BY o.user_id
) sub ON sub.user_id = u.id
WHERE sub.total_revenue > 1000
ORDER BY sub.total_revenue DESC;

-- ===========================================
-- 5. WINDOW FUNCTION: Ranking
-- ===========================================
SELECT
    u.username,
    o.product,
    o.amount,
    o.order_date,
    ROW_NUMBER() OVER (PARTITION BY o.user_id ORDER BY o.amount DESC) AS rank_by_amount,
    SUM(o.amount) OVER (PARTITION BY o.user_id) AS user_total,
    AVG(o.amount) OVER () AS global_avg
FROM orders o
INNER JOIN users u ON u.id = o.user_id
WHERE o.status IN ('completed', 'shipped');

-- ===========================================
-- 6. FULL SCAN trên activity_logs (50K rows)
--    => Rat cham, can index!
-- ===========================================
SELECT
    user_id,
    action,
    COUNT(*) AS action_count,
    MIN(created_at) AS first_time,
    MAX(created_at) AS last_time
FROM activity_logs
WHERE action IN ('login', 'checkout', 'search')
AND created_at BETWEEN '2025-06-01' AND '2026-03-01'
GROUP BY user_id, action
HAVING COUNT(*) > 3
ORDER BY action_count DESC;

-- ===========================================
-- 7. CORRELATED SUBQUERY (expensive!)
-- ===========================================
SELECT
    u.username,
    u.email,
    (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count,
    (SELECT MAX(o.amount) FROM orders o WHERE o.user_id = u.id) AS max_order,
    (SELECT COUNT(*) FROM activity_logs al WHERE al.user_id = u.id AND al.action = 'login') AS login_count
FROM users u
WHERE u.id <= 50;

-- ===========================================
-- 8. CTE + Multiple joins
-- ===========================================
WITH monthly_sales AS (
    SELECT
        YEAR(o.order_date) AS yr,
        MONTH(o.order_date) AS mo,
        o.user_id,
        COUNT(*) AS order_count,
        SUM(o.amount) AS monthly_total
    FROM orders o
    WHERE o.status != 'cancelled'
    GROUP BY YEAR(o.order_date), MONTH(o.order_date), o.user_id
),
user_summary AS (
    SELECT
        user_id,
        SUM(order_count) AS total_orders,
        SUM(monthly_total) AS total_revenue,
        AVG(monthly_total) AS avg_monthly
    FROM monthly_sales
    GROUP BY user_id
)
SELECT
    u.username,
    us.total_orders,
    us.total_revenue,
    us.avg_monthly,
    CASE
        WHEN us.total_revenue > 50000 THEN 'VIP'
        WHEN us.total_revenue > 10000 THEN 'Premium'
        ELSE 'Standard'
    END AS tier
FROM user_summary us
INNER JOIN users u ON u.id = us.user_id
WHERE us.total_orders > 5
ORDER BY us.total_revenue DESC;

-- ============================================================
-- 9. TAO INDEX: Chay lai cac query tren de so sanh!
--    => Uncomment rồi <leader>sr de tao index
--    => Sau do <leader>se de xem cost giam
-- ============================================================

-- CREATE INDEX IX_activity_logs_action_date ON activity_logs(action, created_at) INCLUDE (user_id);
-- CREATE INDEX IX_orders_user_status ON orders(user_id, status) INCLUDE (amount, order_date, product);
-- CREATE INDEX IX_orders_date ON orders(order_date) INCLUDE (user_id, status, amount);
-- CREATE INDEX IX_order_items_order ON order_items(order_id) INCLUDE (product_id, quantity, unit_price, discount);
-- CREATE INDEX IX_activity_logs_user ON activity_logs(user_id, action) INCLUDE (created_at);

-- ============================================================
-- 10. DROP INDEX (de reset ve trang thai khong co index)
-- ============================================================

-- DROP INDEX IX_activity_logs_action_date ON activity_logs;
-- DROP INDEX IX_orders_user_status ON orders;
-- DROP INDEX IX_orders_date ON orders;
-- DROP INDEX IX_order_items_order ON order_items;
-- DROP INDEX IX_activity_logs_user ON activity_logs;

-- ============================================================
-- 11. XEM DANH SACH INDEX HIEN TAI
-- ============================================================
SELECT
    t.name AS table_name,
    i.name AS index_name,
    i.type_desc,
    STRING_AGG(c.name, ', ') AS columns
FROM sys.indexes i
INNER JOIN sys.tables t ON t.object_id = i.object_id
INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE ic.is_included_column = 0
GROUP BY t.name, i.name, i.type_desc
ORDER BY t.name, i.name;
