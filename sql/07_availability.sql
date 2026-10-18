-- 07_availability.sql
-- What does the forward calendar (26 Sep 2026 - 25 Sep 2027) show?
-- IMPORTANT: available = 0 means booked OR blocked by the host. The data cannot
-- separate the two, so "unavailable" is an upper bound for bookings, not occupancy.
-- "Bookable listings" below excludes the listings that are blocked for the whole year.

-- name: available_nights_distribution
WITH bucketed AS (
    SELECT CASE WHEN available_nights = 0   THEN '1  0 nights (blocked all year)'
                WHEN available_nights <= 30  THEN '2  1-30 nights'
                WHEN available_nights <= 90  THEN '3  31-90 nights'
                WHEN available_nights <= 180 THEN '4  91-180 nights'
                WHEN available_nights < 365  THEN '5  181-364 nights'
                ELSE                              '6  365+ nights (never booked or blocked)' END AS available_nights_band
    FROM listing_availability
)
SELECT available_nights_band,
       COUNT(*)                                           AS listings,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM bucketed
GROUP BY available_nights_band
ORDER BY available_nights_band;

-- name: unavailable_share_by_month
SELECT strftime('%Y-%m', c.date)                                                    AS month,
       COUNT(DISTINCT c.date)                                                       AS days_covered,
       ROUND(100.0 * (1 - AVG(c.available)), 1)                                     AS unavailable_pct_all_listings,
       ROUND(100.0 * (1 - AVG(CASE WHEN e.is_blocked = 0 THEN c.available END)), 1) AS unavailable_pct_bookable_listings
FROM calendar c
JOIN listings_enriched e ON e.id = c.listing_id
GROUP BY month
ORDER BY month;

-- name: unavailable_share_by_weekday
SELECT CASE strftime('%w', c.date)
         WHEN '1' THEN 'Monday'  WHEN '2' THEN 'Tuesday'  WHEN '3' THEN 'Wednesday'
         WHEN '4' THEN 'Thursday' WHEN '5' THEN 'Friday'   WHEN '6' THEN 'Saturday'
         ELSE 'Sunday' END                                           AS weekday,
       ROUND(100.0 * (1 - AVG(c.available)), 1)                      AS unavailable_pct_bookable_listings
FROM calendar c
JOIN listings_enriched e ON e.id = c.listing_id
WHERE e.is_blocked = 0
GROUP BY strftime('%w', c.date)
ORDER BY (CAST(strftime('%w', c.date) AS INTEGER) + 6) % 7;

-- name: availability_by_neighbourhood
SELECT neighbourhood,
       COUNT(*)                                                           AS listings,
       ROUND(100.0 * SUM(is_blocked) / COUNT(*), 1)                       AS blocked_all_year_pct,
       ROUND(AVG(CASE WHEN is_blocked = 0 THEN available_nights END), 0)  AS avg_available_nights_bookable,
       RANK() OVER (ORDER BY AVG(CASE WHEN is_blocked = 0 THEN available_nights END)) AS tightest_rank
FROM listings_enriched
GROUP BY neighbourhood
HAVING COUNT(*) >= 50
ORDER BY avg_available_nights_bookable;

-- name: tightest_weeks_ahead
-- The ten complete weeks with the highest unavailable share among bookable listings.
WITH weekly AS (
    -- Monday of each date's week; grouping by it (not by year-week) keeps the New Year week whole
    SELECT date(c.date, '-' || ((CAST(strftime('%w', c.date) AS INTEGER) + 6) % 7) || ' days') AS week_start,
           COUNT(DISTINCT c.date)                                  AS days,
           ROUND(100.0 * (1 - AVG(c.available)), 1)                AS unavailable_pct
    FROM calendar c
    JOIN listings_enriched e ON e.id = c.listing_id
    WHERE e.is_blocked = 0
    GROUP BY week_start
    HAVING COUNT(DISTINCT c.date) = 7
)
SELECT week_start, unavailable_pct,
       RANK() OVER (ORDER BY unavailable_pct DESC) AS tightness_rank
FROM weekly
ORDER BY tightness_rank, week_start      -- week_start breaks ties so the order is deterministic
LIMIT 10;
