-- 03_market_overview.sql
-- How big is Munich's Airbnb market and what does supply look like?

-- name: listings_by_room_type
SELECT room_type,
       COUNT(*)                                          AS listings,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM listings
GROUP BY room_type
ORDER BY listings DESC;

-- name: listings_by_neighbourhood
-- Share of supply and cumulative share, using window functions over the grouped result.
SELECT neighbourhood,
       COUNT(*)                                                       AS listings,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS share_pct,
       RANK() OVER (ORDER BY COUNT(*) DESC)                           AS supply_rank,
       ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC, neighbourhood
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   / SUM(COUNT(*)) OVER (), 1)                        AS cumulative_share_pct
FROM listings
GROUP BY neighbourhood
ORDER BY listings DESC, neighbourhood;

-- name: listing_status_overview
-- A listing in the snapshot is not necessarily alive: 28% have no bookable night at all.
WITH status AS (
    SELECT CASE
             WHEN is_blocked = 1                  THEN '1 Blocked all year (no available night)'
             WHEN number_of_reviews_ltm > 0       THEN '2 Bookable and reviewed in last 12 months'
             ELSE                                      '3 Bookable but no review in last 12 months'
           END AS listing_status
    FROM listings_enriched
)
SELECT listing_status,
       COUNT(*)                                           AS listings,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM status
GROUP BY listing_status
ORDER BY listing_status;

-- name: listing_status_by_room_type
SELECT room_type,
       COUNT(*)                                                        AS listings,
       ROUND(100.0 * SUM(is_blocked) / COUNT(*), 1)                    AS blocked_all_year_pct,
       ROUND(100.0 * SUM(CASE WHEN is_blocked = 0 AND number_of_reviews_ltm > 0 THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS active_pct
FROM listings_enriched
GROUP BY room_type
ORDER BY listings DESC;

-- name: top_property_types
SELECT property_type,
       COUNT(*)                                           AS listings,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM listings
GROUP BY property_type
ORDER BY listings DESC
LIMIT 10;
