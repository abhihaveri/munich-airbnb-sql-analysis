"""
run_queries.py
--------------
Runs every query in sql/02_*.sql ... sql/07_*.sql against data/munich_airbnb.db and
writes each result to results/<query name>.csv.

A query starts with a line "-- name: <result_name>" and ends at the next
"-- name:" line (or the end of the file).

Run (after build_database.py):
    python run_queries.py
"""

import glob
import os
import re
import sqlite3

import pandas as pd

DB = "../data/munich_airbnb.db"
SQL_DIR = "../sql"
OUT_DIR = "../results"


def split_queries(text: str) -> dict:
    parts = re.split(r"^-- name:\s*(\w+)\s*$", text, flags=re.M)
    # parts = [preamble, name1, body1, name2, body2, ...]
    return {parts[i]: parts[i + 1].strip() for i in range(1, len(parts), 2)}


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    con = sqlite3.connect(DB)
    total = 0
    for path in sorted(glob.glob(f"{SQL_DIR}/0[2-7]_*.sql")):
        queries = split_queries(open(path).read())
        print(f"\n{os.path.basename(path)}")
        for name, body in queries.items():
            df = pd.read_sql(body, con)
            df.to_csv(f"{OUT_DIR}/{name}.csv", index=False)
            print(f"  {name:45s} {len(df):>4} rows")
            total += 1
    print(f"\n{total} queries run, results in {OUT_DIR}/")
