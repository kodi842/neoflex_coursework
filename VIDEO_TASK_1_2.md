# Видео-демонстрация задачи 1.2

Расчёт двух витрин в схеме DM на основе DS из задачи 1.1:
`dm.dm_account_turnover_f` (обороты) и `dm.dm_account_balance_f` (остатки).

Все четыре видео по курсовой (1.1 / 1.2 / 1.3 / 1.4) — в общей папке
Google Drive:
https://drive.google.com/drive/folders/1ZMhXnrIE3nR8zUqTHC2uECeeShwDaIFG?usp=sharing

В видео по этой задаче показано:
- DDL целевых витрин в `01_ddl.sql`;
- разбор процедур `ds.fill_account_turnover_f` и `ds.fill_account_balance_f`
  (`02_procedures.sql`) — CTE-логика, `DELETE` для идемпотентности,
  расчёт по правилу А/П, логирование `START`/`END`/`ERROR`;
- запуск seed-скрипта `seed_balance_2017_12_31.py` (114 строк остатков на 31.12.2017);
- прогон витрин за каждый день января 2018 (`run_january.py`);
- результаты: 17 дат с проводками в обороте, 32 даты в остатках;
- логирование в `logs.etl_log` — 31 пара `START`/`END` для каждой процедуры;
- идемпотентность: повторный `CALL` за 15.01.2018 не создаёт дубликатов.
