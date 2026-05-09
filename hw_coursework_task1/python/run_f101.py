"""Запуск процедуры расчёта 101 формы за январь 2018 (i_OnDate=2018-02-01)."""
from __future__ import annotations

from datetime import date

import psycopg2

from db import DB_CONFIG


def main() -> None:
    on_date = date(2018, 2, 1)
    with psycopg2.connect(**DB_CONFIG) as conn, conn.cursor() as cur:
        cur.execute("CALL dm.fill_f101_round_f(%s);", (on_date,))
        cur.execute("SELECT count(*) FROM dm.dm_f101_round_f;")
        n = cur.fetchone()[0]
    print(f"[OK] dm.dm_f101_round_f - строк: {n}")


if __name__ == "__main__":
    main()
