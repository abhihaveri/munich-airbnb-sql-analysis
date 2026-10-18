-- 02_data_quality.sql
-- Data-quality checks run BEFORE any analysis. Each check explains a cleaning
-- decision made in 01_views.sql.
-- Convention: every query starts with "-- name: <result_name>"; python/run_queries.py
-- runs them and writes results/<result_name>.csv.

-- name: dq_row_counts
SELECT 'listings' AS table_name, COUNT(*) AS row_count FROM listings
UNION ALL
SELECT 'calendar', COUNT(*) FROM calendar
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews;

-- name: dq_orphan_checks
-- Anti-joins: rows that point at a listing that does not exist (and the reverse).
SELECT 'calendar rows without a listing' AS check_name, COUNT(*) AS violations
FROM calendar c
LEFT JOIN listings l ON l.id = c.listing_id
WHERE l.id IS NULL
UNION ALL
SELECT 'reviews without a listing', COUNT(*)
FROM reviews r
LEFT JOIN listings l ON l.id = r.listing_id
WHERE l.id IS NULL
UNION ALL
SELECT 'listings without a calendar', COUNT(*)
FROM listings l
LEFT JOIN listing_availability a ON a.listing_id = l.id
WHERE a.listing_id IS NULL;

-- name: dq_null_rates
SELECT 'price' AS column_name,
       COUNT(*) - COUNT(price) AS null_count,
       ROUND(100.0 * (COUNT(*) - COUNT(price)) / COUNT(*), 1) AS null_pct
FROM listings
UNION ALL
SELECT 'review_scores_rating', COUNT(*) - COUNT(review_scores_rating),
       ROUND(100.0 * (COUNT(*) - COUNT(review_scores_rating)) / COUNT(*), 1) FROM listings
UNION ALL
SELECT 'first_review', COUNT(*) - COUNT(first_review),
       ROUND(100.0 * (COUNT(*) - COUNT(first_review)) / COUNT(*), 1) FROM listings
UNION ALL
SELECT 'has_availability', COUNT(*) - COUNT(has_availability),
       ROUND(100.0 * (COUNT(*) - COUNT(has_availability)) / COUNT(*), 1) FROM listings
UNION ALL
SELECT 'bedrooms', COUNT(*) - COUNT(bedrooms),
       ROUND(100.0 * (COUNT(*) - COUNT(bedrooms)) / COUNT(*), 1) FROM listings
UNION ALL
SELECT 'minimum_nights (filled from calendar)', COUNT(*) - COUNT(minimum_nights),
       ROUND(100.0 * (COUNT(*) - COUNT(minimum_nights)) / COUNT(*), 1) FROM listings
ORDER BY null_pct DESC;

-- name: dq_duplicate_review_ids
-- A review id can be attached to more than one listing. Counting reviews at
-- market level without de-duplicating would count those reviews twice.
WITH dup AS (
    SELECT id, COUNT(*) AS n
    FROM reviews
    GROUP BY id
    HAVING COUNT(*) > 1
)
SELECT COUNT(*)                                                   AS review_ids_affected,
       SUM(n)                                                     AS rows_involved,
       SUM(n - 1)                                                 AS excess_rows,
       ROUND(100.0 * SUM(n - 1) / (SELECT COUNT(*) FROM reviews), 2) AS excess_pct_of_reviews
FROM dup;

-- name: dq_price_missing_by_calendar_status
-- Is a missing price random? No: it is missing for every listing with no bookable night.
SELECT CASE WHEN a.available_nights = 0 THEN 'no available night in next 365 days'
            ELSE 'has available nights' END                       AS calendar_status,
       COUNT(*)                                                   AS listings,
       SUM(CASE WHEN l.price IS NULL THEN 1 ELSE 0 END)           AS without_price,
       ROUND(100.0 * SUM(CASE WHEN l.price IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_without_price
FROM listings l
JOIN listing_availability a ON a.listing_id = l.id
GROUP BY calendar_status
ORDER BY listings DESC;

-- name: dq_price_outliers
-- The two prices far above everything else are excluded from price statistics (price_clean).
SELECT room_type, neighbourhood, minimum_nights, ROUND(price, 0) AS price_eur
FROM listings
WHERE price IS NOT NULL
ORDER BY price DESC
LIMIT 10;

-- name: dq_calendar_completeness
SELECT calendar_days, COUNT(*) AS listings
FROM listing_availability
GROUP BY calendar_days
ORDER BY calendar_days;

-- name: dq_availability_365_vs_calendar
-- Cross-check two independent sources of the same fact.
WITH compare AS (
    SELECT l.id, ABS(l.availability_365 - a.available_nights) AS diff
    FROM listings l
    JOIN listing_availability a ON a.listing_id = l.id
)
SELECT COUNT(*)                                  AS listings,
       SUM(diff = 0)                             AS exact_match,
       SUM(diff BETWEEN 1 AND 3)                 AS off_by_1_to_3_nights,
       SUM(diff > 3)                             AS off_by_more,
       MAX(diff)                                 AS max_difference
FROM compare;

-- name: dq_host_listing_count_check
-- calculated_host_listings_count should equal the number of listings we see per host.
WITH actual AS (
    SELECT host_id, COUNT(*) AS n FROM listings GROUP BY host_id
)
SELECT COUNT(*)                                              AS listings,
       SUM(l.calculated_host_listings_count = a.n)           AS matching
FROM listings l
JOIN actual a ON a.host_id = l.host_id;
