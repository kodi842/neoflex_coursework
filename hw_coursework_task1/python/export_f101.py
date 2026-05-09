"""Задача 1.4. Экспорт dm.dm_f101_round_f в CSV (с заголовком).

Формат: разделитель ';' (чтобы запятые в десятичных значениях, если
вдруг появятся, не ломали парсинг), кодировка utf-8, первая строка —
имена колонок таблицы. Decimal-значения форматируются как обычные
числа с фиксированной точкой ('0.00000000'), без научной нотации
('0E-8'), чтобы CSV был читаемым в любом редакторе.
"""
from __future__ import annotations

import csv
import os
from datetime import datetime
from decimal import Decimal

import psycopg2

from db import DB_CONFIG

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "out"))
OUT_FILE = os.path.join(OUT_DIR, "dm_f101_round_f.csv")


def fmt(value):
    """Привести Decimal к обычной строке с фиксированной точкой."""
    if isinstance(value, Decimal):
        return format(value, "f")
    return value


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    started = datetime.now()

    with psycopg2.connect(**DB_CONFIG) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO logs.etl_log(process,object_name,event,started_at,extra) "
            "VALUES (%s,%s,%s,%s,%s)",
            ("export_f101", "dm.dm_f101_round_f", "START", started, OUT_FILE),
        )
        cur.execute("SELECT * FROM dm.dm_f101_round_f ORDER BY ledger_account;")
        cols = [c.name for c in cur.description]
        rows = cur.fetchall()

        with open(OUT_FILE, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter=";")
            w.writerow(cols)
            for r in rows:
                w.writerow([fmt(v) for v in r])

        cur.execute(
            "INSERT INTO logs.etl_log(process,object_name,event,started_at,finished_at,rows_affected,extra) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s)",
            ("export_f101", "dm.dm_f101_round_f", "END",
             started, datetime.now(), len(rows), OUT_FILE),
        )

    print(f"[OK] {OUT_FILE}: {len(rows)} строк")


if __name__ == "__main__":
    main()
