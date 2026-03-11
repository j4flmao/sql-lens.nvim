-- ========================================
-- SqlLens PostgreSQL Demo
-- Database: defaultdb (Aiven Cloud)
-- ========================================

-- ── Schema Setup ──

CREATE TABLE IF NOT EXISTS departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    budget DECIMAL(15,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    department_id INT REFERENCES departments(id) ON DELETE SET NULL,
    salary DECIMAL(12,2) NOT NULL,
    hire_date DATE DEFAULT CURRENT_DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    department_id INT REFERENCES departments(id),
    budget DECIMAL(15,2),
    status VARCHAR(20) DEFAULT 'planning' CHECK (status IN ('planning', 'active', 'completed', 'cancelled')),
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employee_projects (
    employee_id INT REFERENCES employees(id) ON DELETE CASCADE,
    project_id INT REFERENCES projects(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'member',
    assigned_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (employee_id, project_id)
);

CREATE TABLE IF NOT EXISTS salaries_log (
    id SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employees(id),
    old_salary DECIMAL(12,2),
    new_salary DECIMAL(12,2),
    changed_at TIMESTAMP DEFAULT NOW()
);

-- ── Seed Data ──

INSERT INTO departments (name, budget) VALUES
    ('Engineering', 500000.00),
    ('Marketing', 200000.00),
    ('Sales', 300000.00),
    ('HR', 150000.00),
    ('Finance', 250000.00)
ON CONFLICT (name) DO NOTHING;

INSERT INTO employees (first_name, last_name, email, department_id, salary, hire_date) VALUES
    ('Nguyen', 'Van A',     'a.nguyen@company.com',   1, 85000.00, '2023-01-15'),
    ('Tran',   'Thi B',     'b.tran@company.com',     1, 92000.00, '2022-06-01'),
    ('Le',     'Van C',     'c.le@company.com',       2, 65000.00, '2023-03-20'),
    ('Pham',   'Thi D',     'd.pham@company.com',     3, 72000.00, '2021-11-10'),
    ('Hoang',  'Van E',     'e.hoang@company.com',    1, 110000.00, '2020-08-05'),
    ('Vo',     'Thi F',     'f.vo@company.com',       4, 58000.00, '2024-01-08'),
    ('Dang',   'Van G',     'g.dang@company.com',     5, 78000.00, '2022-09-15'),
    ('Bui',    'Thi H',     'h.bui@company.com',      2, 61000.00, '2023-07-22'),
    ('Do',     'Van I',     'i.do@company.com',       3, 95000.00, '2021-04-30'),
    ('Ngo',    'Thi K',     'k.ngo@company.com',      1, 88000.00, '2023-02-14')
ON CONFLICT (email) DO NOTHING;

INSERT INTO projects (name, description, department_id, budget, status, start_date, end_date) VALUES
    ('API Gateway v2',      'Rebuild API gateway with rate limiting',  1, 120000.00, 'active',    '2025-01-01', '2025-06-30'),
    ('Brand Refresh',       'Company-wide rebrand campaign',           2, 80000.00,  'active',    '2025-02-01', '2025-05-31'),
    ('CRM Integration',     'Integrate Salesforce with internal CRM',  3, 95000.00,  'planning',  '2025-04-01', '2025-12-31'),
    ('Employee Portal',     'Self-service HR portal',                  4, 45000.00,  'completed', '2024-06-01', '2025-01-31'),
    ('Budget Dashboard',    'Real-time finance dashboard',             5, 60000.00,  'active',    '2025-03-01', '2025-09-30'),
    ('Mobile App',          'Customer-facing mobile application',      1, 200000.00, 'planning',  '2025-07-01', '2026-03-31'),
    ('Data Pipeline',       'ETL pipeline for analytics',              1, 150000.00, 'active',    '2025-01-15', '2025-08-15')
ON CONFLICT DO NOTHING;

INSERT INTO employee_projects (employee_id, project_id, role) VALUES
    (1, 1, 'developer'),
    (2, 1, 'lead'),
    (5, 1, 'architect'),
    (3, 2, 'designer'),
    (8, 2, 'member'),
    (4, 3, 'lead'),
    (9, 3, 'member'),
    (6, 4, 'lead'),
    (7, 5, 'lead'),
    (10, 7, 'developer'),
    (1, 7, 'member'),
    (2, 6, 'lead'),
    (5, 6, 'architect')
ON CONFLICT DO NOTHING;

-- ── Basic Queries ──

SELECT * FROM employees;

SELECT * FROM departments ORDER BY budget DESC;

SELECT first_name, last_name, salary FROM employees WHERE salary > 80000 ORDER BY salary DESC;

-- ── Aggregation ──

SELECT
    d.name AS department,
    COUNT(e.id) AS headcount,
    ROUND(AVG(e.salary), 2) AS avg_salary,
    MIN(e.salary) AS min_salary,
    MAX(e.salary) AS max_salary,
    SUM(e.salary) AS total_payroll
FROM departments d
LEFT JOIN employees e ON e.department_id = d.id
GROUP BY d.id, d.name
ORDER BY total_payroll DESC;

-- ── Joins ──

SELECT
    e.first_name || ' ' || e.last_name AS employee,
    d.name AS department,
    p.name AS project,
    ep.role
FROM employees e
JOIN departments d ON d.id = e.department_id
JOIN employee_projects ep ON ep.employee_id = e.id
JOIN projects p ON p.id = ep.project_id
WHERE p.status = 'active'
ORDER BY d.name, e.last_name;

-- ── Subquery: employees earning above department average ──

SELECT
    e.first_name || ' ' || e.last_name AS employee,
    e.salary,
    d.name AS department,
    dept_avg.avg_salary
FROM employees e
JOIN departments d ON d.id = e.department_id
JOIN (
    SELECT department_id, ROUND(AVG(salary), 2) AS avg_salary
    FROM employees
    GROUP BY department_id
) dept_avg ON dept_avg.department_id = e.department_id
WHERE e.salary > dept_avg.avg_salary
ORDER BY e.salary DESC;

-- ── CTE: project cost analysis ──

WITH project_costs AS (
    SELECT
        p.id,
        p.name,
        p.budget AS project_budget,
        d.name AS department,
        d.budget AS dept_budget,
        COUNT(ep.employee_id) AS team_size,
        ROUND(p.budget / NULLIF(COUNT(ep.employee_id), 0), 2) AS cost_per_member
    FROM projects p
    JOIN departments d ON d.id = p.department_id
    LEFT JOIN employee_projects ep ON ep.project_id = p.id
    GROUP BY p.id, p.name, p.budget, d.name, d.budget
)
SELECT
    name,
    department,
    project_budget,
    team_size,
    cost_per_member,
    ROUND(project_budget / NULLIF(dept_budget, 0) * 100, 1) AS pct_of_dept_budget
FROM project_costs
ORDER BY project_budget DESC;

-- ── Window Functions ──

SELECT
    first_name || ' ' || last_name AS employee,
    department_id,
    salary,
    RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) AS salary_rank,
    salary - LAG(salary) OVER (PARTITION BY department_id ORDER BY salary DESC) AS gap_to_prev,
    ROUND(salary / SUM(salary) OVER (PARTITION BY department_id) * 100, 1) AS pct_of_dept
FROM employees
ORDER BY department_id, salary_rank;

-- ── CASE + conditional aggregation ──

SELECT
    d.name AS department,
    COUNT(*) AS total_projects,
    COUNT(*) FILTER (WHERE p.status = 'active') AS active,
    COUNT(*) FILTER (WHERE p.status = 'planning') AS planning,
    COUNT(*) FILTER (WHERE p.status = 'completed') AS completed,
    SUM(p.budget) AS total_budget,
    CASE
        WHEN SUM(p.budget) > 200000 THEN 'HIGH'
        WHEN SUM(p.budget) > 100000 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS budget_tier
FROM projects p
JOIN departments d ON d.id = p.department_id
GROUP BY d.id, d.name
ORDER BY total_budget DESC;

-- ── Full-text search simulation (ILIKE) ──

SELECT id, name, description
FROM projects
WHERE description ILIKE '%api%' OR description ILIKE '%dashboard%';

-- ── UPDATE with RETURNING ──

UPDATE employees
SET salary = salary * 1.05
WHERE department_id = 1
  AND hire_date < '2023-01-01'
RETURNING first_name, last_name, salary AS new_salary;

-- ── DELETE with subquery ──

DELETE FROM employee_projects
WHERE project_id IN (
    SELECT id FROM projects WHERE status = 'cancelled'
);

-- ── Create index for performance ──

CREATE INDEX IF NOT EXISTS idx_employees_dept ON employees(department_id);
CREATE INDEX IF NOT EXISTS idx_employees_salary ON employees(salary);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_emp_proj_emp ON employee_projects(employee_id);

-- ── Complex: department health report ──

WITH dept_stats AS (
    SELECT
        d.id,
        d.name,
        d.budget,
        COUNT(DISTINCT e.id) AS employees,
        COUNT(DISTINCT p.id) AS projects,
        COALESCE(SUM(DISTINCT p.budget), 0) AS projects_cost,
        ROUND(AVG(e.salary), 2) AS avg_salary
    FROM departments d
    LEFT JOIN employees e ON e.department_id = d.id
    LEFT JOIN projects p ON p.department_id = d.id
    GROUP BY d.id, d.name, d.budget
)
SELECT
    name,
    employees,
    projects,
    budget AS dept_budget,
    projects_cost,
    budget - projects_cost AS remaining,
    avg_salary,
    CASE
        WHEN projects_cost > budget THEN 'OVER BUDGET'
        WHEN projects_cost > budget * 0.8 THEN 'WARNING'
        ELSE 'OK'
    END AS budget_status
FROM dept_stats
ORDER BY remaining;

-- ── Cleanup (uncomment to drop) ──

-- DROP TABLE IF EXISTS salaries_log CASCADE;
-- DROP TABLE IF EXISTS employee_projects CASCADE;
-- DROP TABLE IF EXISTS projects CASCADE;
-- DROP TABLE IF EXISTS employees CASCADE;
-- DROP TABLE IF EXISTS departments CASCADE;
