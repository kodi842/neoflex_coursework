"""Задача 1.4. Импорт CSV обратно в dm.dm_f101_round_f_v2.

Импорт идёт через серверный COPY ... FROM STDIN: psycopg2.cursor.copy_expert
читает файл блоками и стримит их в Postgres — это самый быстрый путь
загрузки CSV. Перед COPY делаем TRUNCATE целевой таблицы — расчёт
идемпотентен, скрипт можно запускать многократно. Для произвольного
файла можно передать путь аргументом командной строки.
"""
from __future__ import annotations

import os
import sys
from datetime import datetime

import psycopg2

from db import DB_CONFIG

DEFAULT_FILE = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "out", "dm_f101_round_f.csv")
)


def main() -> None:
    src = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FILE)
    started = datetime.now()

    with psycopg2.connect(**DB_CONFIG) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO logs.etl_log(process,object_name,event,started_at,extra) "
            "VALUES (%s,%s,%s,%s,%s)",
            ("import_f101", "dm.dm_f101_round_f_v2", "START", started, src),
        )
        cur.execute("TRUNCATE TABLE dm.dm_f101_round_f_v2;")
        with open(src, "r", encoding="utf-8") as fh:
            cur.copy_expert(
                "COPY dm.dm_f101_round_f_v2 FROM STDIN WITH (FORMAT CSV, HEADER true, DELIMITER ';', NULL '')",
                fh,
            )
        cur.execute("SELECT count(*) FROM dm.dm_f101_round_f_v2;")
        n = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO logs.etl_log(process,object_name,event,started_at,finished_at,rows_affected,extra) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s)",
            ("import_f101", "dm.dm_f101_round_f_v2", "END",
             started, datetime.now(), n, src),
        )

    print(f"[OK] импортировано в dm.dm_f101_round_f_v2: {n} строк из {src}")


if __name__ == "__main__":
    main()
