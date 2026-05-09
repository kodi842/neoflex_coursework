"""Заполнение dm.dm_account_balance_f за 31.12.2017 из ds.ft_balance_f.

Обязательный шаг между задачей 1.1 и расчётом остатков задачи 1.2:
balance_out_rub = balance_out * курс на 31.12.2017 (если курса нет - 1).
"""
from __future__ import annotations

from datetime import datetime

import psycopg2

from db import DB_CONFIG

SQL_INIT = """
DELETE FROM dm.dm_account_balance_f WHERE on_date = DATE '2017-12-31';

INSERT INTO dm.dm_account_balance_f(on_date, account_rk, balance_out, balance_out_rub)
SELECT b.on_date,
       b.account_rk,
       b.balance_out,
       b.balance_out * COALESCE(er.reduced_cource, 1)
  FROM ds.ft_balance_f b
  LEFT JOIN ds.md_exchange_rate_d er
    ON er.currency_rk = b.currency_rk
   AND b.on_date BETWEEN er.data_actual_date
                     AND COALESCE(er.data_actual_end_date, DATE '9999-12-31')
 WHERE b.on_date = DATE '2017-12-31';
"""


def main() -> None:
    started = datetime.now()
    with psycopg2.connect(**DB_CONFIG) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO logs.etl_log(process, object_name, event, started_at, extra) "
            "VALUES (%s,%s,%s,%s,%s)",
            ("seed_balance_2017_12_31", "dm.dm_account_balance_f", "START",
             started, "init from ds.ft_balance_f"),
        )
        cur.execute(SQL_INIT)
        cur.execute("SELECT count(*) FROM dm.dm_account_balance_f WHERE on_date = '2017-12-31';")
        rows = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, rows_affected) "
            "VALUES (%s,%s,%s,%s,%s,%s)",
            ("seed_balance_2017_12_31", "dm.dm_account_balance_f", "END",
             started, datetime.now(), rows),
        )
    print(f"[OK] заполнено {rows} строк остатков на 31.12.2017")


if __name__ == "__main__":
    main()
