"""Параметры подключения к Postgres."""
import os

DB_CONFIG = {
    "host":     os.getenv("PGHOST", "localhost"),
    "port":     int(os.getenv("PGPORT", "5433")),
    "dbname":   os.getenv("PGDATABASE", "airflow"),
    "user":     os.getenv("PGUSER", "airflow"),
    "password": os.getenv("PGPASSWORD", "airflow"),
}
