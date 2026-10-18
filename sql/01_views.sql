-- 01_views.sql
-- Reusable cleaned views. Every analysis query builds on these, so each
-- data-cleaning decision lives in exactly one place.

-- Per-listing summary of the forward calendar.
CREATE VIEW listing_availability AS
SELECT
    listing_id,
    COUNT(*)            AS calendar_days,
    SUM(available)      AS available_nights,
    MIN(minimum_nights) AS calendar_min_nights
FROM calendar
GROUP BY listing_id;

-- Market-level review counts must not count the same review twice:
-- 819 review ids appear under more than one listing.
CREATE VIEW reviews_dedup AS
SELECT listing_id, id, date
FROM (
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY id ORDER BY listing_id) AS rn
    FROM reviews r
)
WHERE rn = 1;

-- Listings with calendar-derived flags and cleaned price.
--   price_clean : NULL for the 2 implausible prices above 5,000 EUR per night
--   is_midterm  : minimum stay of 30+ nights (not tourist short-term supply).
--                 35 listings have no minimum_nights value; for them the calendar's
--                 minimum stay is used (it is 1-6 nights, so they count as short-term).
--   is_blocked  : no available night at all in the next 365 days
CREATE VIEW listings_enriched AS
SELECT
    l.*,
    CASE WHEN l.price BETWEEN 10 AND 5000 THEN l.price END AS price_clean,
    CASE WHEN COALESCE(l.minimum_nights, a.calendar_min_nights) >= 30 THEN 1 ELSE 0 END AS is_midterm,
    a.available_nights,
    CASE WHEN a.available_nights = 0 THEN 1 ELSE 0 END      AS is_blocked
FROM listings l
JOIN listing_availability a ON a.listing_id = l.id;

-- Short-term listings with a plausible price, whatever stay the price was quoted for.
CREATE VIEW priced_all_quotes AS
SELECT * FROM listings_enriched
WHERE price_clean IS NOT NULL
  AND is_midterm = 0;

-- Like-for-like price base used by the pricing queries.
-- The listed price is the per-night price of a sample stay, so two filters make prices comparable:
--   price_quote_nights <= 7           : longer stays carry weekly/monthly discounts
--   price_quote_checkin >= 2026-10-05 : earlier quotes fall in Oktoberfest (19 Sep - 4 Oct 2026)
-- (see price_by_quote_window and entire_home_price_by_stay_length in 04_pricing.sql)
CREATE VIEW priced_listings AS
SELECT * FROM priced_all_quotes
WHERE price_quote_nights <= 7
  AND price_quote_checkin >= '2026-10-05';
