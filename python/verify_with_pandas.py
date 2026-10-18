"""
verify_with_pandas.py - independent check of the SQL results.

Recomputes 10 key numbers with pandas straight from the raw CSV files (not from the
database) and compares them with results/*.csv. FAIL = SQL and pandas disagree.

Run (after run_queries.py):  python verify_with_pandas.py
"""

import os

import pandas as pd

RAW, RES = "../data/raw", "../results"
passed = failed = 0


def find_file(name):
    for ext in (".csv", ".csv.gz"):
        if os.path.exists(f"{RAW}/{name}{ext}"):
            return f"{RAW}/{name}{ext}"
    raise SystemExit(f"Missing {name}.csv in data/raw/ - see data/README.md")


def result(name):
    return pd.read_csv(f"{RES}/{name}.csv")


def check(name, ok):
    global passed, failed
    passed, failed = passed + ok, failed + (not ok)
    print(("PASS  " if ok else "FAIL  ") + name)


def close(a, b, tol=0.06):
    return abs(a - b) <= tol


# ---- load the raw files -------------------------------------------------
listings = pd.read_csv(find_file("listings"), low_memory=False)
calendar = pd.read_csv(find_file("calendar"), usecols=["listing_id", "date", "available", "minimum_nights"])
reviews = pd.read_csv(find_file("reviews"), usecols=["listing_id", "id", "date"])

# ---- the same cleaning rules as the SQL views ---------------------------
listings["price_num"] = pd.to_numeric(
    listings["price"].astype("string").str.replace("[^0-9.]", "", regex=True), errors="coerce")
checkin = pd.to_datetime(listings["price_quote_checkin_date"])
listings["quote_nights"] = (pd.to_datetime(listings["price_quote_checkout_date"]) - checkin).dt.days
listings["checkin"] = checkin

calendar["free"] = (calendar["available"] == "t").astype(int)
listings["free_nights"] = listings["id"].map(calendar.groupby("listing_id")["free"].sum())
listings["is_blocked"] = listings["free_nights"] == 0

# 35 listings have no minimum_nights: use the smallest minimum stay in the calendar
calendar_min = listings["id"].map(calendar.groupby("listing_id")["minimum_nights"].min())
listings["min_stay"] = listings["minimum_nights"].fillna(calendar_min)

priced = listings[listings["price_num"].between(10, 5000) & (listings["min_stay"] < 30)]
like_for_like = priced[(priced["quote_nights"] <= 7) & (priced["checkin"] >= "2026-10-05")]

# ---- 1-4: data quality and market overview ------------------------------
rows = result("dq_row_counts").set_index("table_name")["row_count"]
check("1  row counts", (rows["listings"], rows["calendar"], rows["reviews"]) ==
      (len(listings), len(calendar), len(reviews)))

dups = result("dq_duplicate_review_ids").iloc[0]
check("2  duplicate review rows", dups.excess_rows == reviews["id"].duplicated().sum())

by_room = result("listings_by_room_type").set_index("room_type")["listings"]
check("3  listings per room type", by_room.to_dict() == listings["room_type"].value_counts().to_dict())

status = result("listing_status_overview").set_index("listing_status")["listings"]
check("4  blocked listings", status.iloc[0] == listings["is_blocked"].sum())

# ---- 5-7: pricing --------------------------------------------------------
room_prices = result("median_price_by_room_type").set_index("room_type")["median_price_eur"]
expected = like_for_like.groupby("room_type")["price_num"].median()
check("5  median price per room type",
      set(room_prices.index) == set(expected.index) and all(close(room_prices[k], expected[k], 0.5) for k in expected.index))

district = result("price_by_neighbourhood").set_index("neighbourhood")
sizes = like_for_like["neighbourhood_cleansed"].value_counts()
check("6  districts with 30+ priced listings", set(district.index) == set(sizes[sizes >= 30].index))

medians = like_for_like.groupby("neighbourhood_cleansed")["price_num"].median()
check("7  median price per district", all(close(district.loc[d, "median_price_eur"], medians[d], 0.5) for d in district.index))

# ---- 8: hosts ------------------------------------------------------------
per_host = listings.groupby("host_id").size()
sizes = result("host_size_distribution").set_index("host_size")
groups = {"1 listing": per_host == 1, "2-5 listings": per_host.between(2, 5),
          "6-20 listings": per_host.between(6, 20), "21+ listings": per_host > 20}
check("8  hosts and listings per host size",
      all(sizes.loc[k, "hosts"] == m.sum() and sizes.loc[k, "listings"] == per_host[m].sum() for k, m in groups.items()))

# ---- 9: reviews (remove duplicate review ids first) ------------------------
reviews = reviews.sort_values(["id", "listing_id"]).drop_duplicates("id")
per_year = pd.to_datetime(reviews["date"]).dt.year.value_counts().sort_index()
check("9  reviews per year", result("reviews_per_year_yoy").set_index("review_year")["reviews"].to_dict() == per_year.to_dict())

# ---- 10: availability ---------------------------------------------------------
bookable = calendar.merge(listings[["id", "is_blocked"]], left_on="listing_id", right_on="id")
bookable = bookable[~bookable["is_blocked"]]
unavailable = (1 - bookable.groupby(bookable["date"].str[:7])["free"].mean()) * 100
table = result("unavailable_share_by_month").set_index("month")["unavailable_pct_bookable_listings"]
check("10 unavailable share per month", all(close(table[m], unavailable[m]) for m in table.index))

print(f"\n{passed} passed, {failed} failed")
