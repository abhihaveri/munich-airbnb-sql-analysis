-- 04_pricing.sql
-- What do listings cost?
--
-- IMPORTANT: the price in the Inside Airbnb file is NOT a standard nightly rate. It is the
-- per-night price of a sample stay quoted for each listing's EARLIEST AVAILABLE dates, so
-- the check-in date and the length of that stay differ from listing to listing.
-- The first two queries measure how much that distorts prices. Every query after them
-- uses the priced_listings view (stays of up to 7 nights, check-in from 5 Oct 2026).
--
-- SQLite has no MEDIAN(), so medians are computed with ROW_NUMBER() and COUNT() window
-- functions: the median is the average of the middle one or two rows. Medians rather
-- than means, because prices are strongly right-skewed.

-- name: price_by_quote_window
-- Same room type, different quote dates: Oktoberfest quotes are far more expensive.
-- (Different listings fall into each window, so this shows the size of the distortion,
-- not the price change of one listing.)
WITH base AS (
    SELECT room_type,
           CASE WHEN price_quote_checkin <= '2026-10-04' THEN '1 check-in 26 Sep - 4 Oct 2026 (Oktoberfest)'
                WHEN price_quote_checkin <= '2026-12-31' THEN '2 check-in 5 Oct - 31 Dec 2026'
                ELSE                                          '3 check-in Jan - Sep 2027' END AS quote_window,
           price_clean AS price
    FROM priced_all_quotes
    WHERE price_quote_nights <= 7
      AND room_type IN ('Entire home/apt', 'Private room')
),
ranked AS (
    SELECT room_type, quote_window, price,
           ROW_NUMBER() OVER (PARTITION BY room_type, quote_window ORDER BY price) AS rn,
           COUNT(*)     OVER (PARTITION BY room_type, quote_window)                AS n
    FROM base
)
SELECT room_type,
       quote_window,
       MAX(n)                                                              AS listings,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur
FROM ranked
GROUP BY room_type, quote_window
ORDER BY room_type, quote_window;

-- name: entire_home_price_by_stay_length
-- Per-night price falls with the length of the quoted stay (length-of-stay discounts).
-- Quotes are limited to check-in from 5 Oct 2026 so the date effect does not interfere.
WITH base AS (
    SELECT CASE WHEN price_quote_nights = 1 THEN '1 night'
                WHEN price_quote_nights = 2 THEN '2 nights'
                WHEN price_quote_nights = 3 THEN '3 nights'
                WHEN price_quote_nights <= 7 THEN '4-7 nights'
                ELSE '8+ nights' END AS stay_length,
           CASE WHEN price_quote_nights = 1 THEN 1
                WHEN price_quote_nights = 2 THEN 2
                WHEN price_quote_nights = 3 THEN 3
                WHEN price_quote_nights <= 7 THEN 4
                ELSE 5 END AS sort_order,
           price_clean AS price
    FROM priced_all_quotes
    WHERE room_type = 'Entire home/apt'
      AND price_quote_checkin >= '2026-10-05'
),
ranked AS (
    SELECT stay_length, sort_order, price,
           ROW_NUMBER() OVER (PARTITION BY stay_length ORDER BY price) AS rn,
           COUNT(*)     OVER (PARTITION BY stay_length)                AS n
    FROM base
)
SELECT stay_length,
       MAX(n)                                                              AS listings,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur
FROM ranked
GROUP BY stay_length
ORDER BY MIN(sort_order);

-- name: median_price_by_room_type
WITH ranked AS (
    SELECT room_type,
           price_clean AS price,
           ROW_NUMBER() OVER (PARTITION BY room_type ORDER BY price_clean) AS rn,
           COUNT(*)     OVER (PARTITION BY room_type)                      AS n
    FROM priced_listings
)
SELECT room_type,
       MAX(n)                                                   AS listings,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur,
       ROUND(AVG(price), 0)                                     AS mean_price_eur
FROM ranked
GROUP BY room_type
ORDER BY median_price_eur DESC;

-- name: price_by_neighbourhood
-- Median and interquartile range per neighbourhood (30+ priced listings only),
-- compared with the city-wide median. top_host_share_pct shows how much of a
-- neighbourhood's priced listings belong to its single largest host: where it is
-- high, "the neighbourhood price" is really one operator's pricing.
WITH ranked AS (
    SELECT neighbourhood,
           price_clean AS price,
           ROW_NUMBER() OVER (PARTITION BY neighbourhood ORDER BY price_clean) AS rn,
           COUNT(*)     OVER (PARTITION BY neighbourhood)                      AS n
    FROM priced_listings
),
hood AS (
    SELECT neighbourhood,
           MAX(n)                                                              AS listings,
           ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur,
           MAX(CASE WHEN rn = CAST(0.25 * (n - 1) AS INTEGER) + 1 THEN price END) AS p25_price_eur,
           MAX(CASE WHEN rn = CAST(0.75 * (n - 1) AS INTEGER) + 1 THEN price END) AS p75_price_eur
    FROM ranked
    GROUP BY neighbourhood
    HAVING MAX(n) >= 30
),
host_share AS (
    SELECT neighbourhood,
           ROUND(100.0 * MAX(host_listings) / SUM(host_listings), 0) AS top_host_share_pct
    FROM (
        SELECT neighbourhood, host_id, COUNT(*) AS host_listings
        FROM priced_listings
        GROUP BY neighbourhood, host_id
    )
    GROUP BY neighbourhood
),
city AS (
    SELECT ROUND(AVG(price), 0) AS city_median
    FROM (
        SELECT price_clean AS price,
               ROW_NUMBER() OVER (ORDER BY price_clean) AS rn,
               COUNT(*) OVER ()                         AS n
        FROM priced_listings
    )
    WHERE rn IN ((n + 1) / 2, (n + 2) / 2)
)
SELECT h.neighbourhood,
       h.listings,
       h.median_price_eur,
       h.p25_price_eur,
       h.p75_price_eur,
       ROUND(100.0 * (h.median_price_eur - c.city_median) / c.city_median, 0) AS vs_city_median_pct,
       RANK() OVER (ORDER BY h.median_price_eur DESC)                         AS price_rank,
       s.top_host_share_pct
FROM hood h
CROSS JOIN city c
JOIN host_share s ON s.neighbourhood = h.neighbourhood
ORDER BY h.median_price_eur DESC;

-- name: entire_home_price_by_bedrooms
WITH base AS (
    SELECT CASE WHEN bedrooms IS NULL THEN 'unknown'
                WHEN bedrooms >= 4    THEN '4+'
                ELSE CAST(CAST(bedrooms AS INTEGER) AS TEXT) END AS bedrooms_group,
           price_clean AS price
    FROM priced_listings
    WHERE room_type = 'Entire home/apt'
),
ranked AS (
    SELECT bedrooms_group, price,
           ROW_NUMBER() OVER (PARTITION BY bedrooms_group ORDER BY price) AS rn,
           COUNT(*)     OVER (PARTITION BY bedrooms_group)                AS n
    FROM base
)
SELECT bedrooms_group,
       MAX(n)                                                              AS listings,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur
FROM ranked
GROUP BY bedrooms_group
ORDER BY bedrooms_group;

-- name: median_price_per_guest_by_room_type
WITH ranked AS (
    SELECT room_type,
           price_clean * 1.0 / accommodates AS price_per_guest,
           ROW_NUMBER() OVER (PARTITION BY room_type ORDER BY price_clean * 1.0 / accommodates) AS rn,
           COUNT(*)     OVER (PARTITION BY room_type)                                           AS n
    FROM priced_listings
    WHERE accommodates > 0
)
SELECT room_type,
       MAX(n)                                                                      AS listings,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price_per_guest END), 0) AS median_price_per_guest_eur
FROM ranked
GROUP BY room_type
ORDER BY median_price_per_guest_eur DESC;

-- name: entire_home_price_by_rating
-- Do better-rated homes charge more? Entire homes only (controls for room type),
-- and only listings with at least 5 reviews so the rating means something.
WITH base AS (
    SELECT CASE WHEN review_scores_rating >= 4.9 THEN '4.9 - 5.0'
                WHEN review_scores_rating >= 4.7 THEN '4.7 - 4.89'
                WHEN review_scores_rating >= 4.5 THEN '4.5 - 4.69'
                ELSE 'below 4.5' END AS rating_band,
           CASE WHEN review_scores_rating >= 4.9 THEN 1
                WHEN review_scores_rating >= 4.7 THEN 2
                WHEN review_scores_rating >= 4.5 THEN 3
                ELSE 4 END AS band_order,
           price_clean AS price
    FROM priced_listings
    WHERE room_type = 'Entire home/apt'
      AND number_of_reviews >= 5
      AND review_scores_rating IS NOT NULL
),
ranked AS (
    SELECT rating_band, band_order, price,
           ROW_NUMBER() OVER (PARTITION BY rating_band ORDER BY price) AS rn,
           COUNT(*)     OVER (PARTITION BY rating_band)                AS n
    FROM base
)
SELECT rating_band,
       MAX(n)                                                              AS listings,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN price END), 0) AS median_price_eur
FROM ranked
GROUP BY rating_band
ORDER BY MIN(band_order);
