# Data

The raw data is **not** in this repository. It is about 180 MB, and the review and listing
files contain personal data (reviewer names, free-text review comments, host names). The
build script reads only the columns the analysis needs and never loads those fields.

## Source

[Inside Airbnb](https://insideairbnb.com/get-the-data/), Munich, Germany.
Snapshot scraped on **25-26 September 2026**. Licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). This project is an independent
analysis and is not affiliated with Airbnb or Inside Airbnb.

## Download

On the page above, find **Munich, Bavaria, Germany** and download the three *detailed* files:

| Download | Save as |
|---|---|
| Listings (`listings.csv.gz`) | `data/raw/listings.csv.gz` |
| Calendar (`calendar.csv.gz`) | `data/raw/calendar.csv.gz` |
| Reviews (`reviews.csv.gz`) | `data/raw/reviews.csv.gz` |

Unzipped `.csv` files work as well. Do not use the smaller "summary" files; they lack the columns used here.

Inside Airbnb publishes a new snapshot every few months. A different snapshot gives different
numbers, and the dates in `sql/01_views.sql` and `sql/04_pricing.sql` (the Oktoberfest window
of the 2026 snapshot) belong to this snapshot and must be adjusted for another one.

## Columns used

| File | Columns loaded |
|---|---|
| listings | id, host_id, neighbourhood_cleansed, room_type, property_type, accommodates, bedrooms, beds, price, price_quote_checkin_date, price_quote_checkout_date, minimum_nights, maximum_nights, has_availability, availability_365, number_of_reviews, number_of_reviews_ltm, first_review, last_review, review_scores_rating, host_is_superhost, hosts_time_as_host_years, calculated_host_listings_count, instant_bookable, estimated_occupancy_l365d, last_scraped |
| calendar | listing_id, date, available, minimum_nights |
| reviews | listing_id, id, date |

Deliberately **not** loaded: reviewer_id, reviewer_name, comments, host_name, host descriptions,
picture URLs, listing text.

## What the price column really is

`price` is not a standard nightly rate. It is the per-night price of a sample stay quoted for
each listing's earliest available dates (`price_quote_checkin_date` / `price_quote_checkout_date`),
so the check-in date and stay length differ per listing. See the README for how this is handled.
