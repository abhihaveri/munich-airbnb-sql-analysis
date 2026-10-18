"""
build_database.py - loads the three Inside Airbnb files into a SQLite database.

Put listings / calendar / reviews (.csv or .csv.gz) in data/raw/ first (see data/README.md).
Only the columns the analysis needs are read. Reviewer names, review text, host names
and picture URLs are never loaded (personal data).

Run:  python build_database.py
"""

import os
import sqlite3

import pandas as pd

RAW, DB, SQL = "../data/raw", "../data/munich_airbnb.db", "../sql"

LISTING_COLUMNS = [
    "id", "host_id", "neighbourhood_cleansed", "room_type", "property_type",
    "accommodates", "bedrooms", "beds", "price",
    "price_quote_checkin_date", "price_quote_checkout_date",
    "minimum_nights", "maximum_nights", "has_availability", "availability_365",
    "number_of_reviews", "number_of_reviews_ltm", "first_review", "last_review",
    "review_scores_rating", "host_is_superhost", "hosts_time_as_host_years",
    "calculated_host_listings_count", "instant_bookable",
    "estimated_occupancy_l365d", "last_scraped",
]


def find_file(name):
    """Return the path of name.csv or name.csv.gz (pandas reads both)."""
    for ext in (".csv", ".csv.gz"):
        if os.path.exists(f"{RAW}/{name}{ext}"):
            return f"{RAW}/{name}{ext}"
    raise SystemExit(f"Missing {name}.csv in data/raw/ - see data/README.md")


def run_sql_file(con, filename):
    with open(f"{SQL}/{filename}") as f:
        con.executescript(f.read())


# 1. listings -------------------------------------------------------------
listings = pd.read_csv(find_file("listings"), usecols=LISTING_COLUMNS, low_memory=False)
listings = listings.rename(columns={"neighbourhood_cleansed": "neighbourhood"})

# price arrives as text like "$115.00": keep digits and the dot, then convert to a number
listings["price"] = pd.to_numeric(
    listings["price"].astype("string").str.replace("[^0-9.]", "", regex=True),
    errors="coerce",                      # anything unreadable becomes NULL instead of crashing
)

# the price is a quote for a sample stay: remember WHEN and for HOW MANY NIGHTS
checkin = pd.to_datetime(listings["price_quote_checkin_date"])
checkout = pd.to_datetime(listings["price_quote_checkout_date"])
listings["price_quote_checkin"] = checkin.dt.strftime("%Y-%m-%d")
listings["price_quote_nights"] = (checkout - checkin).dt.days.astype("Int64")

# t / f flags -> 1 / 0 (empty stays NULL)
for flag in ["has_availability", "host_is_superhost", "instant_bookable"]:
    listings[flag] = listings[flag].map({"t": 1, "f": 0}).astype("Int64")

listings = listings.drop(columns=["price_quote_checkin_date", "price_quote_checkout_date"])

# 2. calendar and reviews -------------------------------------------------
calendar = pd.read_csv(find_file("calendar"),
                       usecols=["listing_id", "date", "available", "minimum_nights"])
calendar["available"] = (calendar["available"] == "t").astype(int)

reviews = pd.read_csv(find_file("reviews"), usecols=["listing_id", "id", "date"])

# 3. write to SQLite ------------------------------------------------------
if os.path.exists(DB):
    os.remove(DB)
con = sqlite3.connect(DB)
run_sql_file(con, "00_schema.sql")          # tables, types and keys

for name, table in [("listings", listings), ("calendar", calendar), ("reviews", reviews)]:
    table.to_sql(name, con, if_exists="append", index=False, chunksize=100_000)
    print(f"{name:9s} {len(table):>9,} rows loaded")

run_sql_file(con, "01_views.sql")           # cleaned views the queries use
con.commit()
con.close()
print("database written to", DB)
