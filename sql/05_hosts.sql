-- 05_hosts.sql
-- Who runs Munich's Airbnb supply: private hosts or professional operators?
-- Host ids are used only for grouping; no host names or ids appear in the results.

-- name: host_size_distribution
WITH host_counts AS (
    SELECT host_id, COUNT(*) AS n_listings
    FROM listings
    GROUP BY host_id
),
bucketed AS (
    SELECT n_listings,
           CASE WHEN n_listings = 1  THEN '1 listing'
                WHEN n_listings <= 5  THEN '2-5 listings'
                WHEN n_listings <= 20 THEN '6-20 listings'
                ELSE '21+ listings' END AS host_size,
           CASE WHEN n_listings = 1  THEN 1
                WHEN n_listings <= 5  THEN 2
                WHEN n_listings <= 20 THEN 3
                ELSE 4 END AS sort_order
    FROM host_counts
)
SELECT host_size,
       COUNT(*)                                                     AS hosts,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS hosts_pct,
       SUM(n_listings)                                              AS listings,
       ROUND(100.0 * SUM(n_listings) / SUM(SUM(n_listings)) OVER (), 1) AS listings_pct
FROM bucketed
GROUP BY host_size
ORDER BY MIN(sort_order);

-- name: top_host_concentration
-- Cumulative share of listings held by the largest hosts (running-total window).
WITH host_counts AS (
    SELECT host_id, COUNT(*) AS n_listings
    FROM listings
    GROUP BY host_id
),
ranked AS (
    SELECT n_listings,
           ROW_NUMBER() OVER (ORDER BY n_listings DESC, host_id)                       AS host_rank,
           COUNT(*)     OVER ()                                                        AS total_hosts,
           SUM(n_listings) OVER (ORDER BY n_listings DESC, host_id
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)     AS cumulative_listings,
           SUM(n_listings) OVER ()                                                     AS total_listings
    FROM host_counts
)
SELECT '10 largest hosts' AS host_group, host_rank AS hosts, cumulative_listings AS listings,
       ROUND(100.0 * cumulative_listings / total_listings, 1) AS share_of_all_listings_pct
FROM ranked WHERE host_rank = 10
UNION ALL
SELECT 'top 1% of hosts', host_rank, cumulative_listings,
       ROUND(100.0 * cumulative_listings / total_listings, 1)
FROM ranked WHERE host_rank = CAST(total_hosts * 0.01 AS INTEGER)
UNION ALL
SELECT 'top 5% of hosts', host_rank, cumulative_listings,
       ROUND(100.0 * cumulative_listings / total_listings, 1)
FROM ranked WHERE host_rank = CAST(total_hosts * 0.05 AS INTEGER)
UNION ALL
SELECT 'top 10% of hosts', host_rank, cumulative_listings,
       ROUND(100.0 * cumulative_listings / total_listings, 1)
FROM ranked WHERE host_rank = CAST(total_hosts * 0.10 AS INTEGER);

-- name: professional_host_share_by_neighbourhood
SELECT neighbourhood,
       COUNT(*)                                                                  AS listings,
       ROUND(100.0 * SUM(CASE WHEN calculated_host_listings_count >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS multi_listing_host_pct,
       ROUND(100.0 * SUM(CASE WHEN calculated_host_listings_count >= 6 THEN 1 ELSE 0 END) / COUNT(*), 1) AS large_host_pct,
       RANK() OVER (ORDER BY 1.0 * SUM(CASE WHEN calculated_host_listings_count >= 6 THEN 1 ELSE 0 END) / COUNT(*) DESC) AS large_host_rank
FROM listings
GROUP BY neighbourhood
HAVING COUNT(*) >= 50
ORDER BY large_host_pct DESC;

-- name: superhost_comparison
WITH ranked AS (
    SELECT host_is_superhost, price_clean AS price,
           ROW_NUMBER() OVER (PARTITION BY host_is_superhost ORDER BY price_clean) AS rn,
           COUNT(*)     OVER (PARTITION BY host_is_superhost)                      AS n
    FROM priced_listings
),
medians AS (
    SELECT host_is_superhost,
           ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur
    FROM ranked
    GROUP BY host_is_superhost
),
quality AS (
    SELECT host_is_superhost,
           COUNT(*)                                       AS listings,
           ROUND(AVG(review_scores_rating), 2)            AS avg_rating,
           ROUND(AVG(number_of_reviews_ltm), 1)           AS avg_reviews_last_12m
    FROM listings
    GROUP BY host_is_superhost
)
SELECT CASE q.host_is_superhost WHEN 1 THEN 'Superhost' ELSE 'Not a superhost' END AS host_type,
       q.listings, q.avg_rating, q.avg_reviews_last_12m, m.median_price_eur
FROM quality q
JOIN medians m ON m.host_is_superhost = q.host_is_superhost
ORDER BY q.host_is_superhost DESC;
