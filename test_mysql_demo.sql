-- ========================================
-- SqlLens MySQL Demo (Laragon)
-- Database: sql_lens_test
-- ========================================

-- Xem tất cả users
SELECT * FROM users;

-- Tìm theo ID
SELECT name, email FROM users WHERE id = 1;

-- Đếm tổng
SELECT COUNT(*) AS total_users FROM users;

-- Thêm user mới
INSERT INTO users (name, email) VALUES ('Demo User', 'demo@test.com');

-- Xem lại sau khi thêm
SELECT * FROM users ORDER BY created_at DESC;
