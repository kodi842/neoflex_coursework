"""Задача 1.1. Загрузка CSV в детальный слой DS с логированием в logs.etl_log.

Алгоритм:
    1. Логируем событие START всего процесса.
    2. Пауза 5 секунд (по требованию задания).
    3. По каждому файлу:
       - START строки в логе,
       - COPY во временную stage-таблицу (TEMP),
       - INSERT ... ON CONFLICT DO UPDATE в ds.* (для ft_posting_f - TRUNCATE+INSERT),
       - END строки с количеством строк.
    4. Логируем END всего процесса.

Запуск:  python load_csv.py [path_to_data_dir]
"""
from __future__ import annotations

import os
import sys
import time
from datetime import datetime

import psycopg2

from db import DB_CONFIG

DATA_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), "..", "data"
)

# (csv-имя, целевая таблица, формат даты для on_date/oper_date/etc, маппинг колонок)
# Все колонки CSV - в верхнем регистре, в Postgres - в нижнем.
# Стейдж заводим как TEMP с теми же типами text, чтобы не зависеть от формата дат.

LOAD_PLAN = [
    # (csv,                      target,                date_cols)
    ("ft_balance_f.csv",         "ds.ft_balance_f",         {"on_date": "DD.MM.YYYY"}),
    ("ft_posting_f.csv",         "ds.ft_posting_f",         {"oper_date": "DD-MM-YYYY"}),
    ("md_account_d.csv",         "ds.md_account_d",         {"data_actual_date": None,
                                                              "data_actual_end_date": None}),
    ("md_currency_d.csv",        "ds.md_currency_d",        {"data_actual_date": None,
                                                              "data_actual_end_date": None}),
    ("md_exchange_rate_d.csv",   "ds.md_exchange_rate_d",   {"data_actual_date": None,
                                                              "data_actual_end_date": None}),
    ("md_ledger_account_s.csv",  "ds.md_ledger_account_s",  {"start_date": None,
                                                              "end_date": None}),
]

# Каждой целевой таблице - SQL для записи или замены из stage.
UPSERT_SQL = {
    "ds.ft_balance_f": """
        INSERT INTO ds.ft_balance_f (on_date, account_rk, currency_rk, balance_out)
        SELECT DISTINCT ON (to_date("ON_DATE",'DD.MM.YYYY'), "ACCOUNT_RK"::bigint)
               to_date("ON_DATE",'DD.MM.YYYY'),
               "ACCOUNT_RK"::bigint,
               NULLIF("CURRENCY_RK",'')::bigint,
               NULLIF("BALANCE_OUT",'')::numeric
          FROM stg
         WHERE "ON_DATE" IS NOT NULL AND "ACCOUNT_RK" IS NOT NULL
        ON CONFLICT (on_date, account_rk) DO UPDATE
           SET currency_rk = EXCLUDED.currency_rk,
               balance_out = EXCLUDED.balance_out;
    """,
    # ft_posting_f - без PK, всегда полная загрузка.
    "ds.ft_posting_f": """
        TRUNCATE TABLE ds.ft_posting_f;
        INSERT INTO ds.ft_posting_f
              (oper_date, credit_account_rk, debet_account_rk, credit_amount, debet_amount)
        SELECT to_date("OPER_DATE",'DD-MM-YYYY'),
               "CREDIT_ACCOUNT_RK"::bigint,
               "DEBET_ACCOUNT_RK"::bigint,
               NULLIF("CREDIT_AMOUNT",'')::numeric,
               NULLIF("DEBET_AMOUNT",'')::numeric
          FROM stg
         WHERE "OPER_DATE" IS NOT NULL;
    """,
    "ds.md_account_d": """
        INSERT INTO ds.md_account_d (data_actual_date, data_actual_end_date,
                                     account_rk, account_number, char_type,
                                     currency_rk, currency_code)
        SELECT DISTINCT ON ("DATA_ACTUAL_DATE","ACCOUNT_RK")
               "DATA_ACTUAL_DATE"::date,
               "DATA_ACTUAL_END_DATE"::date,
               "ACCOUNT_RK"::bigint,
               "ACCOUNT_NUMBER",
               "CHAR_TYPE",
               "CURRENCY_RK"::bigint,
               "CURRENCY_CODE"
          FROM stg
        ON CONFLICT (data_actual_date, account_rk) DO UPDATE
           SET data_actual_end_date = EXCLUDED.data_actual_end_date,
               account_number       = EXCLUDED.account_number,
               char_type            = EXCLUDED.char_type,
               currency_rk          = EXCLUDED.currency_rk,
               currency_code        = EXCLUDED.currency_code;
    """,
    "ds.md_currency_d": """
        INSERT INTO ds.md_currency_d (currency_rk, data_actual_date,
                                       data_actual_end_date, currency_code, code_iso_char)
        SELECT DISTINCT ON ("CURRENCY_RK","DATA_ACTUAL_DATE")
               "CURRENCY_RK"::bigint,
               "DATA_ACTUAL_DATE"::date,
               NULLIF("DATA_ACTUAL_END_DATE",'')::date,
               "CURRENCY_CODE",
               "CODE_ISO_CHAR"
          FROM stg
        ON CONFLICT (currency_rk, data_actual_date) DO UPDATE
           SET data_actual_end_date = EXCLUDED.data_actual_end_date,
               currency_code        = EXCLUDED.currency_code,
               code_iso_char        = EXCLUDED.code_iso_char;
    """,
    "ds.md_exchange_rate_d": """
        INSERT INTO ds.md_exchange_rate_d (data_actual_date, data_actual_end_date,
                                            currency_rk, reduced_cource, code_iso_num)
        SELECT DISTINCT ON ("DATA_ACTUAL_DATE", "CURRENCY_RK")
               "DATA_ACTUAL_DATE"::date,
               NULLIF("DATA_ACTUAL_END_DATE",'')::date,
               "CURRENCY_RK"::bigint,
               NULLIF("REDUCED_COURCE",'')::numeric,
               "CODE_ISO_NUM"
          FROM stg
        ON CONFLICT (data_actual_date, currency_rk) DO UPDATE
           SET data_actual_end_date = EXCLUDED.data_actual_end_date,
               reduced_cource       = EXCLUDED.reduced_cource,
               code_iso_num         = EXCLUDED.code_iso_num;
    """,
    "ds.md_ledger_account_s": """
        INSERT INTO ds.md_ledger_account_s (chapter, chapter_name, section_number,
            section_name, subsection_name, ledger1_account, ledger1_account_name,
            ledger_account, ledger_account_name, characteristic, start_date, end_date)
        SELECT DISTINCT ON ("LEDGER_ACCOUNT","START_DATE")
               "CHAPTER",
               "CHAPTER_NAME",
               NULLIF("SECTION_NUMBER",'')::int,
               "SECTION_NAME",
               "SUBSECTION_NAME",
               NULLIF("LEDGER1_ACCOUNT",'')::int,
               "LEDGER1_ACCOUNT_NAME",
               "LEDGER_ACCOUNT"::int,
               "LEDGER_ACCOUNT_NAME",
               "CHARACTERISTIC",
               "START_DATE"::date,
               NULLIF("END_DATE",'')::date
          FROM stg
        ON CONFLICT (ledger_account, start_date) DO UPDATE
           SET chapter              = EXCLUDED.chapter,
               chapter_name         = EXCLUDED.chapter_name,
               section_number       = EXCLUDED.section_number,
               section_name         = EXCLUDED.section_name,
               subsection_name      = EXCLUDED.subsection_name,
               ledger1_account      = EXCLUDED.ledger1_account,
               ledger1_account_name = EXCLUDED.ledger1_account_name,
               ledger_account_name  = EXCLUDED.ledger_account_name,
               characteristic       = EXCLUDED.characteristic,
               end_date             = EXCLUDED.end_date;
    """,
}


def get_csv_header_columns(path: str) -> list[str]:
    with open(path, "rb") as f:
        line = f.readline()
    try:
        header = line.decode("utf-8").rstrip("\r\n")
    except UnicodeDecodeError:
        header = line.decode("latin-1").rstrip("\r\n")
    return header.split(";")


def log_event(cur, process: str, object_name: str, event: str,
              started_at: datetime | None = None,
              finished_at: datetime | None = None,
              rows: int | None = None, extra: str | None = None) -> int:
    cur.execute(
        """
        INSERT INTO logs.etl_log(process, object_name, event,
                                  started_at, finished_at, rows_affected, extra)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING log_id
        """,
        (process, object_name, event, started_at, finished_at, rows, extra),
    )
    return cur.fetchone()[0]


def read_csv_text(path: str) -> "io.StringIO":
    """Читает CSV в StringIO (UTF-8). Если файл невалидный UTF-8 -
    декодируем как latin-1 (устойчивость к одиночным «битым» байтам).
    """
    import io
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
    return io.StringIO(text)


def load_one(conn, csv_name: str, target: str) -> int:
    """Грузит один CSV в target. Возвращает количество строк."""
    csv_path = os.path.join(DATA_DIR, csv_name)
    columns = get_csv_header_columns(csv_path)

    with conn.cursor() as cur:
        # 1. Стейдж - временная таблица с text-колонками по заголовку.
        cur.execute("DROP TABLE IF EXISTS stg;")
        cols_def = ", ".join(f'"{c}" text' for c in columns)
        cur.execute(f"CREATE TEMP TABLE stg ({cols_def}) ON COMMIT DROP;")

        # 2. COPY: читаем в память с авто-выбором кодировки.
        buf = read_csv_text(csv_path)
        cur.copy_expert(
            sql=("COPY stg FROM STDIN WITH "
                 "(FORMAT CSV, HEADER true, DELIMITER ';', NULL '')"),
            file=buf,
        )

        # 3. UPSERT/REPLACE в ds.*.
        cur.execute(UPSERT_SQL[target])
        cur.execute(f"SELECT count(*) FROM {target};")
        total_rows = cur.fetchone()[0]
    return total_rows


def main() -> None:
    print(f"DATA_DIR={DATA_DIR}")
    started = datetime.now()

    with psycopg2.connect(**DB_CONFIG) as conn:
        with conn.cursor() as cur:
            log_event(cur, "load_csv_to_ds", "ALL",
                      "START", started_at=started,
                      extra=f"plan={[t for _,t,_ in LOAD_PLAN]}")
        conn.commit()

        print("[INFO] Логирована START всего процесса. Пауза 5 секунд...")
        time.sleep(5)

        for csv_name, target, _ in LOAD_PLAN:
            t0 = datetime.now()
            print(f"[LOAD] {csv_name:32s} -> {target}")
            with conn.cursor() as cur:
                log_event(cur, "load_csv_to_ds", target, "START",
                          started_at=t0, extra=csv_name)
            conn.commit()

            try:
                rows = load_one(conn, csv_name, target)
                conn.commit()
            except Exception as exc:
                conn.rollback()
                with conn.cursor() as cur:
                    log_event(cur, "load_csv_to_ds", target, "ERROR",
                              started_at=t0, finished_at=datetime.now(),
                              extra=str(exc)[:500])
                conn.commit()
                raise

            t1 = datetime.now()
            with conn.cursor() as cur:
                log_event(cur, "load_csv_to_ds", target, "END",
                          started_at=t0, finished_at=t1,
                          rows=rows,
                          extra=f"duration_sec={(t1-t0).total_seconds():.3f}")
            conn.commit()
            print(f"[OK]   {target} rows={rows} {(t1-t0).total_seconds():.2f}s")

        finished = datetime.now()
        with conn.cursor() as cur:
            log_event(cur, "load_csv_to_ds", "ALL", "END",
                      started_at=started, finished_at=finished,
                      extra=f"duration_sec={(finished-started).total_seconds():.2f}")
        conn.commit()

    print(f"[DONE] Загрузка завершена за {(finished-started).total_seconds():.2f} сек.")


if __name__ == "__main__":
    main()
