# Видео-демонстрация задачи 1.4

Экспорт `dm.dm_f101_round_f` в CSV (`export_f101.py`) и импорт изменённого
CSV в `dm.dm_f101_round_f_v2` (`import_f101.py`).

Все четыре видео по курсовой (1.1 / 1.2 / 1.3 / 1.4) — в общей папке
Google Drive:
https://drive.google.com/drive/folders/1ZMhXnrIE3nR8zUqTHC2uECeeShwDaIFG?usp=sharing

В видео по этой задаче показано:
- запуск `python export_f101.py` → `out/dm_f101_round_f.csv`
  (18 строк, разделитель `;`, первая строка — имена колонок);
- ручная подмена двух значений (для счетов 30102 и 30220) в копии файла
  `out/dm_f101_round_f_modified.csv`;
- запуск `python import_f101.py ../out/dm_f101_round_f_modified.csv`
  → загрузка в `dm.dm_f101_round_f_v2` (TRUNCATE + COPY FROM STDIN);
- сверка: 4 поля diff между `dm.dm_f101_round_f` и `dm.dm_f101_round_f_v2`
  ровно соответствуют двум подменённым значениям;
- логирование старта/окончания каждого скрипта в `logs.etl_log`
  (process = `export_f101` / `import_f101`).
