"""
make_charts.py - draws the 5 README charts from the results/*.csv files.
Every chart is a direct picture of a SQL result.

Run (after run_queries.py):  python make_charts.py
"""

import matplotlib.pyplot as plt
import pandas as pd

RES, OUT = "../results", "../screenshots"


def save(name, title, xlabel="", ylabel=""):
    """Add the title and axis labels, save the picture, start a fresh chart."""
    plt.title(title, fontweight="bold")
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.tight_layout()
    plt.savefig(f"{OUT}/{name}.png", dpi=150)
    plt.close()


# 1. Oktoberfest effect: median price by check-in window, one bar group per room type
w = pd.read_csv(f"{RES}/price_by_quote_window.csv")
w["window"] = w["quote_window"].str[0].map({"1": "26 Sep-4 Oct\n(Oktoberfest)", "2": "5 Oct-31 Dec", "3": "Jan-Sep 2027"})
w.pivot(index="window", columns="room_type", values="median_price_eur").plot.bar(rot=0, figsize=(9, 5))
save("price_oktoberfest_effect", "Prices quoted for Oktoberfest stays are almost double",
     "Check-in date of the quoted stay", "Median price per night (EUR)")

# 2. Median price per neighbourhood (cheapest at the bottom)
p = pd.read_csv(f"{RES}/price_by_neighbourhood.csv").sort_values("median_price_eur")
p.plot.barh(x="neighbourhood", y="median_price_eur", legend=False, figsize=(9, 7))
save("price_by_neighbourhood", "Median nightly price by neighbourhood", "Median price per night (EUR)")

# 3. Reviews per month, with the 12-month average
r = pd.read_csv(f"{RES}/reviews_monthly_rolling_12m.csv")
r = r[r["month"] < "2026-09"]                  # September 2026 is incomplete, leave it out
r["average"] = r["rolling_12m_reviews"] / 12
r.plot(x="month", y=["reviews", "average"], figsize=(10, 5))
save("reviews_trend", "Guest reviews in Munich: collapse in 2020, then growth to new highs",
     "", "Reviews per month (de-duplicated)")

# 4. Share of future nights already unavailable
a = pd.read_csv(f"{RES}/unavailable_share_by_month.csv")
a.plot.bar(x="month", y="unavailable_pct_bookable_listings", legend=False, figsize=(10, 5))
save("availability_by_month", "Share of future nights already unavailable, by month",
     "", "Nights unavailable (booked or blocked), %")

# 5. Who runs the supply: % of hosts vs % of listings per host size
h = pd.read_csv(f"{RES}/host_size_distribution.csv")
h.plot.bar(x="host_size", y=["hosts_pct", "listings_pct"], rot=0, figsize=(8, 5))
save("host_concentration", "Most hosts have one listing; multi-listing hosts hold a third of supply",
     "", "%")

print("5 charts written to", OUT)
