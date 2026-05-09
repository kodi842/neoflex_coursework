# Neoflex Coursework — банковское хранилище DS / DM на PostgreSQL

Курсовая работа Neoflex по построению ETL-процессов и витрин данных
в реляционной СУБД.

**Студент:** Орисенко Максим (maksimorisenko9@gmail.com)

## Состав репозитория

В этой ветке (`main`) лежат только итоговые артефакты:

- `README.md` (этот файл) — обзор проекта и навигация по веткам;
- `Курсовая_Задача_1_1_отчет.pdf` — полный отчёт по задаче 1.1 со скриншотами;
- `Курсовая_Задача_1_2_отчет.pdf` — полный отчёт по задаче 1.2 со скриншотами;
- `Курсовая_Задача_1_3_отчет.pdf` — полный отчёт по задаче 1.3 со скриншотами;
- `Курсовая_Задача_1_4_отчет.pdf` — полный отчёт по задаче 1.4 со скриншотами.

Код каждой задачи лежит в своей ветке (см. таблицу ниже).

## Задачи

| Задача | Что делает | Ветка с кодом | Отчёт (PDF в этой ветке) |
|---|---|---|---|
| **1.1** | ETL-загрузка шести банковских CSV в детальный слой DS PostgreSQL | [`1_1`](../../tree/1_1) | [`Курсовая_Задача_1_1_отчет.pdf`](Курсовая_Задача_1_1_отчет.pdf) |
| **1.2** | Расчёт двух витрин в DM на основе DS — обороты `dm.dm_account_turnover_f` и остатки `dm.dm_account_balance_f` за январь 2018 | [`1_2`](../../tree/1_2) | [`Курсовая_Задача_1_2_отчет.pdf`](Курсовая_Задача_1_2_отчет.pdf) |
| **1.3** | Расчёт 101-й формы (`dm.fill_f101_round_f`) за январь 2018 на основе витрин 1.2 | [`1_3`](../../tree/1_3) | [`Курсовая_Задача_1_3_отчет.pdf`](Курсовая_Задача_1_3_отчет.pdf) |
| **1.4** | Экспорт `dm.dm_f101_round_f` в CSV и импорт обратно в копию `dm.dm_f101_round_f_v2` | [`1_4`](../../tree/1_4) | [`Курсовая_Задача_1_4_отчет.pdf`](Курсовая_Задача_1_4_отчет.pdf) |

## Видео-демонстрации

Все четыре видео (по одному на задачу) — в общей папке Google Drive:

**https://drive.google.com/drive/folders/1ZMhXnrIE3nR8zUqTHC2uECeeShwDaIFG?usp=sharing**

В каждом видео — голосовой комментарий, что разработано, как запускается и
как видны результаты в БД (включая логи и идемпотентность).

## Стек

- **PostgreSQL 13** в Docker (порт хоста 5433, БД `airflow`, пользователь `airflow`, пароль `airflow`)
- **Python 3** + `psycopg2-binary` (для всех ETL-скриптов и расчётов витрин)
- **DBeaver** — для просмотра данных и логов

Структура слоёв в БД:

| Схема | Назначение |
|---|---|
| `ds` | Детальный слой — 6 таблиц с исходными данными (заполняется в задаче 1.1) |
| `logs` | Универсальная таблица `logs.etl_log` — журнал всех ETL-процессов курсовой |
| `dm` | Витрины: `dm_account_turnover_f`, `dm_account_balance_f` (1.2), `dm_f101_round_f` и `_v2` (1.3 / 1.4) |

## Как воспроизвести (по веткам, в порядке возрастания)

```bash
# 1. Поднять Postgres
docker run -d --name hw_coursework_postgres -p 5433:5432 \
  -e POSTGRES_DB=airflow -e POSTGRES_USER=airflow -e POSTGRES_PASSWORD=airflow \
  postgres:13

pip install psycopg2-binary

# 2. Задача 1.1 — заполнить DS
git checkout 1_1
docker exec -i hw_coursework_postgres psql -U airflow -d airflow \
  < hw_coursework_task1/sql/01_ddl.sql
cd hw_coursework_task1/python && python load_csv.py && cd -

# 3. Задача 1.2 — рассчитать витрины оборотов и остатков за январь 2018
git checkout 1_2
docker exec -i hw_coursework_postgres psql -U airflow -d airflow \
  < hw_coursework_task1/sql/02_procedures.sql
cd hw_coursework_task1/python
python seed_balance_2017_12_31.py
python run_january.py
cd -

# 4. Задача 1.3 — рассчитать 101 форму за январь 2018
git checkout 1_3
cd hw_coursework_task1/python && python run_f101.py && cd -

# 5. Задача 1.4 — экспорт/импорт CSV
git checkout 1_4
cd hw_coursework_task1/python
python export_f101.py
# (опционально) меняем 2 значения в out/dm_f101_round_f.csv → save as ..._modified.csv
python import_f101.py ../out/dm_f101_round_f_modified.csv
cd -
```

В каждой ветке также лежит `VIDEO_TASK_*.md` — короткое описание соответствующего видео.
