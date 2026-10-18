-- 00_schema.sql
-- Tables for the Munich Airbnb case study (Inside Airbnb snapshot, 25-26 Sep 2026).
-- Only the columns the analysis needs are loaded. Reviewer names, review text,
-- host names/descriptions and picture URLs are deliberately NOT loaded (personal data).

CREATE TABLE listings (
    id                              INTEGER PRIMARY KEY,
    host_id                         INTEGER NOT NULL,
    neighbourhood                   TEXT    NOT NULL,   -- Munich Stadtbezirk (neighbourhood_cleansed)
    room_type                       TEXT    NOT NULL,
    property_type                   TEXT,
    accommodates                    INTEGER,
    bedrooms                        REAL,
    beds                            REAL,
    price                           REAL,               -- EUR per night of a SAMPLE STAY (see the two columns below); NULL = no price quoted
    price_quote_checkin             TEXT,               -- check-in date of that sample stay (earliest available dates, differs per listing)
    price_quote_nights              INTEGER,            -- length of that sample stay (per-night price includes length-of-stay discounts)
    minimum_nights                  INTEGER,
    maximum_nights                  INTEGER,
    has_availability                INTEGER,            -- 1 / 0 / NULL (unknown)
    availability_365                INTEGER,
    number_of_reviews               INTEGER,
    number_of_reviews_ltm           INTEGER,            -- reviews in the last 12 months
    first_review                    TEXT,               -- ISO date
    last_review                     TEXT,
    review_scores_rating            REAL,
    host_is_superhost               INTEGER,
    hosts_time_as_host_years        REAL,
    calculated_host_listings_count  INTEGER,
    instant_bookable                INTEGER,
    estimated_occupancy_l365d       INTEGER,            -- Inside Airbnb's own modelled estimate
    last_scraped                    TEXT
);

-- One row per listing per future night (next 365 days from the scrape).
-- available = 0 means booked OR blocked by the host; the data cannot tell them apart.
CREATE TABLE calendar (
    listing_id      INTEGER NOT NULL REFERENCES listings(id),
    date            TEXT    NOT NULL,
    available       INTEGER NOT NULL,
    minimum_nights  INTEGER,
    PRIMARY KEY (listing_id, date)
);

-- A review id can appear under more than one listing, so the key is (listing_id, id).
-- Use the reviews_dedup view for market-level counts.
CREATE TABLE reviews (
    listing_id  INTEGER NOT NULL REFERENCES listings(id),
    id          INTEGER NOT NULL,
    date        TEXT    NOT NULL,
    PRIMARY KEY (listing_id, id)
);

CREATE INDEX idx_listings_host      ON listings(host_id);
CREATE INDEX idx_listings_hood      ON listings(neighbourhood);
CREATE INDEX idx_calendar_date      ON calendar(date);
CREATE INDEX idx_reviews_date       ON reviews(date);
