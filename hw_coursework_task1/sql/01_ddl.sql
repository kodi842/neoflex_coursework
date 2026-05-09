-- DDL: схемы DS, LOGS, DM и все таблицы курсовой работы.

CREATE SCHEMA IF NOT EXISTS ds;
CREATE SCHEMA IF NOT EXISTS logs;
CREATE SCHEMA IF NOT EXISTS dm;

-- Таблица логов ETL/процедур.
CREATE TABLE IF NOT EXISTS logs.etl_log (
    log_id      BIGSERIAL PRIMARY KEY,
    process     TEXT        NOT NULL,
    object_name TEXT,
    event       TEXT        NOT NULL,
    started_at  TIMESTAMP,
    finished_at TIMESTAMP,
    rows_affected BIGINT,
    extra       TEXT,
    created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- DS: детальный слой.
CREATE TABLE IF NOT EXISTS ds.ft_balance_f (
    on_date     DATE   NOT NULL,
    account_rk  BIGINT NOT NULL,
    currency_rk BIGINT,
    balance_out NUMERIC,
    CONSTRAINT pk_ft_balance_f PRIMARY KEY (on_date, account_rk)
);

CREATE TABLE IF NOT EXISTS ds.ft_posting_f (
    oper_date         DATE   NOT NULL,
    credit_account_rk BIGINT NOT NULL,
    debet_account_rk  BIGINT NOT NULL,
    credit_amount     NUMERIC,
    debet_amount      NUMERIC
);

CREATE TABLE IF NOT EXISTS ds.md_account_d (
    data_actual_date     DATE        NOT NULL,
    data_actual_end_date DATE        NOT NULL,
    account_rk           BIGINT      NOT NULL,
    account_number       VARCHAR(20) NOT NULL,
    char_type            VARCHAR(1)  NOT NULL,
    currency_rk          BIGINT      NOT NULL,
    currency_code        VARCHAR(3)  NOT NULL,
    CONSTRAINT pk_md_account_d PRIMARY KEY (data_actual_date, account_rk)
);

CREATE TABLE IF NOT EXISTS ds.md_currency_d (
    currency_rk          BIGINT NOT NULL,
    data_actual_date     DATE   NOT NULL,
    data_actual_end_date DATE,
    currency_code        VARCHAR(3),
    code_iso_char        VARCHAR(3),
    CONSTRAINT pk_md_currency_d PRIMARY KEY (currency_rk, data_actual_date)
);

CREATE TABLE IF NOT EXISTS ds.md_exchange_rate_d (
    data_actual_date     DATE   NOT NULL,
    data_actual_end_date DATE,
    currency_rk          BIGINT NOT NULL,
    reduced_cource       NUMERIC,
    code_iso_num         VARCHAR(3),
    CONSTRAINT pk_md_exchange_rate_d PRIMARY KEY (data_actual_date, currency_rk)
);

CREATE TABLE IF NOT EXISTS ds.md_ledger_account_s (
    chapter              CHAR(1),
    chapter_name         VARCHAR(16),
    section_number       INTEGER,
    section_name         VARCHAR(22),
    subsection_name      VARCHAR(21),
    ledger1_account      INTEGER,
    ledger1_account_name VARCHAR(47),
    ledger_account       INTEGER     NOT NULL,
    ledger_account_name  VARCHAR(153),
    characteristic       CHAR(1),
    start_date           DATE        NOT NULL,
    end_date             DATE,
    CONSTRAINT pk_md_ledger_account_s PRIMARY KEY (ledger_account, start_date)
);

-- DM: витрины.
CREATE TABLE IF NOT EXISTS dm.dm_account_turnover_f (
    on_date           DATE,
    account_rk        BIGINT,
    credit_amount     NUMERIC(23,8),
    credit_amount_rub NUMERIC(23,8),
    debet_amount      NUMERIC(23,8),
    debet_amount_rub  NUMERIC(23,8)
);

CREATE TABLE IF NOT EXISTS dm.dm_account_balance_f (
    on_date          DATE,
    account_rk       BIGINT,
    balance_out      NUMERIC(23,8),
    balance_out_rub  NUMERIC(23,8)
);

CREATE TABLE IF NOT EXISTS dm.dm_f101_round_f (
    from_date         DATE,
    to_date           DATE,
    chapter           CHAR(1),
    ledger_account    CHAR(5),
    characteristic    CHAR(1),
    balance_in_rub    NUMERIC(23,8),
    balance_in_val    NUMERIC(23,8),
    balance_in_total  NUMERIC(23,8),
    turn_deb_rub      NUMERIC(23,8),
    turn_deb_val      NUMERIC(23,8),
    turn_deb_total    NUMERIC(23,8),
    turn_cre_rub      NUMERIC(23,8),
    turn_cre_val      NUMERIC(23,8),
    turn_cre_total    NUMERIC(23,8),
    balance_out_rub   NUMERIC(23,8),
    balance_out_val   NUMERIC(23,8),
    balance_out_total NUMERIC(23,8)
);

-- Копия для проверки импорта в задании 1.4.
CREATE TABLE IF NOT EXISTS dm.dm_f101_round_f_v2 (LIKE dm.dm_f101_round_f INCLUDING ALL);
