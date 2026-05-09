# Видео-демонстрация задачи 1.3

Расчёт 101-й формы (`dm.fill_f101_round_f`) за январь 2018 г.

Все четыре видео по курсовой (1.1 / 1.2 / 1.3 / 1.4) — в общей папке
Google Drive:
https://drive.google.com/drive/folders/1ZMhXnrIE3nR8zUqTHC2uECeeShwDaIFG?usp=sharing

В видео по этой задаче показано:
- структура витрины `dm.dm_f101_round_f` (DDL);
- разбор процедуры `dm.fill_f101_round_f` — CTE accounts_period / chapters /
  bal_in / bal_out / turn_period / enriched, `SUM(CASE WHEN currency_code IN ('810','643') ...)`
  для разреза `rub` / `val` / `total`;
- запуск расчёта (`python run_f101.py`, `i_OnDate = 2018-02-01`);
- появление 18 строк в `dm.dm_f101_round_f` после расчёта;
- логирование `START`/`END` в `logs.etl_log`;
- идемпотентность: повторный запуск даёт те же 18 строк;
- финальная проверка инварианта `total = rub + val` для всех 18 строк по 4 показателям.
