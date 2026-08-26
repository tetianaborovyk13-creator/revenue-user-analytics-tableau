with date_grid as (
-- Генеруємо список усіх унікальних місяців з платежів
    SELECT DISTINCT DATE_TRUNC('month', payment_date)::DATE AS payment_month
    FROM games_payments
),
user_lifetime AS (
    -- Знаходимо перший і останній місяць активності кожного юзера
    SELECT 
        user_id,
        MIN(DATE_TRUNC('month', payment_date)::DATE) AS first_month,
        MAX(DATE_TRUNC('month', payment_date)::DATE) AS last_month
    FROM games_payments
    GROUP BY user_id
    ),
user_monthly_grid AS (
    -- Створюємо сітку місяців для кожного юзера (від першої оплати до останнього місяця в базі + 1 місяць для відтоку)
    SELECT 
        l.user_id,
        g.payment_month
    FROM user_lifetime l
    JOIN date_grid g 
      ON g.payment_month >= l.first_month 
     AND g.payment_month <= (SELECT MAX(payment_month) FROM date_grid)
),
monthly_user_revenue AS (
    -- Агрегуємо реальні платежі
    SELECT
        user_id,
        DATE_TRUNC('month', payment_date)::DATE AS payment_month,
        SUM(revenue_amount_usd) AS mrr
    FROM games_payments
    GROUP BY 1, 2
),
full_monthly_data AS (
    -- Об'єднуємо сітку з реальним MRR (якщо немає платежу — ставимо 0)
    SELECT 
        g.user_id,
        g.payment_month,
        COALESCE(r.mrr, 0) AS mrr
    FROM user_monthly_grid g
    LEFT JOIN monthly_user_revenue r 
           ON g.user_id = r.user_id AND g.payment_month = r.payment_month
),
lagged_data AS (
    -- Беремо значення за попередній місяць
    SELECT 
        f.*,
        u.game_name,
        u.language,
        u.has_older_device_model,
        u.age,
        LAG(mrr, 1, 0) OVER (PARTITION BY f.user_id ORDER BY f.payment_month) AS prev_mrr,
        MIN(f.payment_month) OVER (PARTITION BY f.user_id) AS first_payment_month
    FROM full_monthly_data f
    LEFT JOIN games_paid_users u ON f.user_id = u.user_id
)
           
SELECT 
    user_id,
    game_name,
    language,
    has_older_device_model,
    age,
    payment_month,
    mrr,
    prev_mrr,
case
        WHEN payment_month = first_payment_month THEN 'New'
        WHEN mrr > 0 AND prev_mrr = 0 AND payment_month > first_payment_month THEN 'Back from Churn'
        WHEN mrr > prev_mrr AND prev_mrr > 0 THEN 'Revenue Expansion'
        WHEN mrr < prev_mrr AND mrr > 0 THEN 'Revenue Contraction'
        WHEN mrr = 0 AND prev_mrr > 0 THEN 'Churn'
        WHEN mrr = prev_mrr AND mrr > 0 THEN 'Retained'
        ELSE 'Inactive'
    END AS mrr_category,

-- Розрахунок дельти MRR (зміни доходу)
CASE 
        WHEN payment_month = first_payment_month THEN mrr
        WHEN mrr > 0 AND prev_mrr = 0 THEN mrr
        WHEN mrr > prev_mrr THEN mrr - prev_mrr
        WHEN mrr < prev_mrr AND mrr > 0 THEN mrr - prev_mrr
        WHEN mrr = 0 AND prev_mrr > 0 THEN -prev_mrr -- Churned revenue (від'ємне)
        ELSE 0
    END AS mrr_change
from lagged_data
WHERE NOT (mrr = 0 AND prev_mrr = 0); -- прибираємо місяці, де юзер не активний і не був активним минулого місяця;














