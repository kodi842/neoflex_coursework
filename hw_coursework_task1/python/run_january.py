"""Прогон витрин оборотов и остатков за каждый день января 2018.

Коммитим после каждого дня (а не один раз в конце), чтобы:
1. в логах logs.etl_log для каждой даты были реальные started_at/finished_at;
2. при сбое промежуточные дни оставались зафиксированы.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta

import psycopg2

from db import DB_CONFIG


def main() -> None:
    start = date(2018, 1, 1)
    end   = date(2018, 1, 31)

    t0 = datetime.now()
    with psycopg2.connect(**DB_CONFIG) as conn:
        d = start
        while d <= end:
            with conn.cursor() as cur:
                cur.execute("CALL ds.fill_account_turnover_f(%s);", (d,))
                cur.execute("CALL ds.fill_account_balance_f(%s);",  (d,))
            conn.commit()
            print(f"[OK] {d}")
            d += timedelta(days=1)
    print(f"[DONE] Январь 2018 рассчитан за {(datetime.now()-t0).total_seconds():.2f} с.")


if __name__ == "__main__":
    main()
