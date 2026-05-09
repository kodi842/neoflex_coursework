# Видео-демонстрация задачи 1.1

ETL-загрузка шести банковских CSV в детальный слой DS на PostgreSQL
(`load_csv.py`).

Все четыре видео по курсовой (1.1 / 1.2 / 1.3 / 1.4) — в общей папке
Google Drive:
https://drive.google.com/drive/folders/1ZMhXnrIE3nR8zUqTHC2uECeeShwDaIFG?usp=sharing

В видео по этой задаче показано:
- Postgres в Docker и три рабочих схемы (`ds`, `logs`, `dm`) в DBeaver;
- DDL шести таблиц `ds.*` + универсальной таблицы логов `logs.etl_log`;
- разбор `load_csv.py` (CSV → COPY → INSERT в `ds.*`, логирование, обработка ошибок);
- запуск `python load_csv.py` и контрольная сводка по 6 таблицам;
- журнал `logs.etl_log` — пары `START`/`END` для каждого CSV.
