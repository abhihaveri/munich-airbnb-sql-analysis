-- 06_reviews_trends.sql
-- How has demand developed? A review is left after a stay, so review counts are a
-- proxy for guest stays (not a count of bookings). Market-level counts use
-- reviews_dedup so a review attached to two listings is counted once.

-- name: reviews_per_year_yoy
WITH yearly AS (
    SELECT CAST(strftime('%Y', date) AS INTEGER) AS review_year, COUNT(*) AS reviews
    FROM reviews_dedup
    GROUP BY review_year
)
SELECT review_year,
       reviews,
       LAG(reviews) OVER (ORDER BY review_year)                                              AS previous_year,
       CASE WHEN review_year = 2026 THEN NULL      -- partial year: see reviews_year_to_date_comparison
            ELSE ROUND(100.0 * (reviews - LAG(reviews) OVER (ORDER BY review_year))
                             / LAG(reviews) OVER (ORDER BY review_year), 1) END              AS yoy_change_pct,
       CASE WHEN review_year = 2026 THEN 'partial (to 25 Sep)' ELSE 'full year' END           AS coverage
FROM yearly
ORDER BY review_year;

-- name: reviews_year_to_date_comparison
-- Like-for-like: reviews from 1 Jan to 25 Sep of every year (2026 is only complete to 25 Sep).
WITH ytd AS (
    SELECT CAST(strftime('%Y', date) AS INTEGER) AS review_year,
           COUNT(*)                              AS reviews_1jan_to_25sep
    FROM reviews_dedup
    WHERE strftime('%m-%d', date) <= '09-25'
    GROUP BY review_year
)
SELECT review_year,
       reviews_1jan_to_25sep,
       LAG(reviews_1jan_to_25sep) OVER (ORDER BY review_year) AS previous_year,
       ROUND(100.0 * (reviews_1jan_to_25sep - LAG(reviews_1jan_to_25sep) OVER (ORDER BY review_year))
                   / LAG(reviews_1jan_to_25sep) OVER (ORDER BY review_year), 1) AS yoy_change_pct
FROM ytd
WHERE review_year >= 2018
ORDER BY review_year;

-- name: reviews_monthly_rolling_12m
-- Monthly reviews with a rolling 12-month total (window frame of 12 rows).
WITH monthly AS (
    SELECT strftime('%Y-%m', date) AS month, COUNT(*) AS reviews
    FROM reviews_dedup
    WHERE date >= '2018-01-01'
    GROUP BY month
),
rolled AS (
    SELECT month, reviews,
           SUM(reviews) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS rolling_12m_reviews
    FROM monthly
)
SELECT month, reviews, rolling_12m_reviews
FROM rolled
WHERE month >= '2019-01'
ORDER BY month;

-- name: review_seasonality_2022_2025
-- Which months are busiest? Share of each year's reviews, averaged over the four full years 2022-2025.
WITH monthly AS (
    SELECT CAST(strftime('%Y', date) AS INTEGER) AS review_year,
           CAST(strftime('%m', date) AS INTEGER) AS month_number,
           COUNT(*) AS reviews
    FROM reviews_dedup
    WHERE date BETWEEN '2022-01-01' AND '2025-12-31'
    GROUP BY review_year, month_number
),
shares AS (
    SELECT review_year, month_number,
           100.0 * reviews / SUM(reviews) OVER (PARTITION BY review_year) AS share_of_year
    FROM monthly
)
SELECT month_number,
       ROUND(AVG(share_of_year), 1)                          AS avg_share_of_year_pct,
       ROUND(MIN(share_of_year), 1)                          AS min_share_pct,
       ROUND(MAX(share_of_year), 1)                          AS max_share_pct,
       RANK() OVER (ORDER BY AVG(share_of_year) DESC)        AS busiest_rank
FROM shares
GROUP BY month_number
ORDER BY month_number;

-- name: covid_recovery_by_quarter
-- Reviews per quarter as a percentage of the same quarter in 2019 (FIRST_VALUE over each quarter).
WITH quarterly AS (
    SELECT CAST(strftime('%Y', date) AS INTEGER)               AS review_year,
           (CAST(strftime('%m', date) AS INTEGER) + 2) / 3     AS quarter,
           COUNT(*)                                            AS reviews
    FROM reviews_dedup
    WHERE date BETWEEN '2019-01-01' AND '2022-12-31'
    GROUP BY review_year, quarter
)
SELECT review_year, quarter, reviews,
       ROUND(100.0 * reviews / FIRST_VALUE(reviews) OVER (PARTITION BY quarter ORDER BY review_year), 0) AS pct_of_2019_same_quarter
FROM quarterly
ORDER BY review_year, quarter;

-- name: listing_cohorts_by_first_review_year
-- Of today's listings, how many of each entry cohort were still reviewed in the last 12 months?
-- Caveat: the snapshot only contains listings that exist today (survivorship).
SELECT CAST(strftime('%Y', first_review) AS INTEGER)                              AS first_review_year,
       COUNT(*)                                                                   AS listings,
       SUM(CASE WHEN number_of_reviews_ltm > 0 THEN 1 ELSE 0 END)                 AS reviewed_last_12m,
       ROUND(100.0 * SUM(CASE WHEN number_of_reviews_ltm > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS reviewed_last_12m_pct,
       ROUND(100.0 * SUM(is_blocked) / COUNT(*), 1)                               AS blocked_all_year_pct
FROM listings_enriched
WHERE first_review IS NOT NULL
GROUP BY first_review_year
ORDER BY first_review_year;
