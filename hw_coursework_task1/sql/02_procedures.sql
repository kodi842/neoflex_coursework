-- Процедуры расчёта витрин.

-- 1.2.a Витрина оборотов.
-- Логика: берём проводки за i_OnDate, складываем в один проход кредитовые и
-- дебетовые обороты по каждому account_rk. Курс — из md_exchange_rate_d, для
-- активного интервала актуальности счёта (md_account_d). Если курса нет, берём 1.
-- В витрину попадают ТОЛЬКО счета, по которым были проводки в этот день.
CREATE OR REPLACE PROCEDURE ds.fill_account_turnover_f(i_OnDate DATE)
LANGUAGE plpgsql AS $$
DECLARE
    v_log_id  BIGINT;
    v_started TIMESTAMP := clock_timestamp();
    v_finished TIMESTAMP;
    v_rows    BIGINT;
BEGIN
    -- Идемпотентность: чистим записи за дату, чтобы можно было перезапускать.
    INSERT INTO logs.etl_log(process, object_name, event, started_at, extra)
    VALUES ('fill_account_turnover_f', 'dm.dm_account_turnover_f', 'START',
            v_started, 'on_date=' || i_OnDate)
    RETURNING log_id INTO v_log_id;

    DELETE FROM dm.dm_account_turnover_f WHERE on_date = i_OnDate;

    WITH posting AS (
        SELECT account_rk,
               SUM(credit_amount) AS credit_amount,
               SUM(debet_amount)  AS debet_amount
          FROM (
                SELECT credit_account_rk AS account_rk,
                       credit_amount,
                       0::numeric        AS debet_amount
                  FROM ds.ft_posting_f
                 WHERE oper_date = i_OnDate
                UNION ALL
                SELECT debet_account_rk AS account_rk,
                       0::numeric       AS credit_amount,
                       debet_amount
                  FROM ds.ft_posting_f
                 WHERE oper_date = i_OnDate
               ) u
         GROUP BY account_rk
    ),
    rate AS (
        SELECT a.account_rk, COALESCE(er.reduced_cource, 1) AS rate
          FROM ds.md_account_d a
          LEFT JOIN ds.md_exchange_rate_d er
            ON er.currency_rk = a.currency_rk
           AND i_OnDate BETWEEN er.data_actual_date
                            AND COALESCE(er.data_actual_end_date, DATE '9999-12-31')
         WHERE i_OnDate BETWEEN a.data_actual_date AND a.data_actual_end_date
    )
    INSERT INTO dm.dm_account_turnover_f(on_date, account_rk,
                                         credit_amount, credit_amount_rub,
                                         debet_amount,  debet_amount_rub)
    SELECT i_OnDate,
           p.account_rk,
           p.credit_amount,
           p.credit_amount * COALESCE(r.rate, 1),
           p.debet_amount,
           p.debet_amount  * COALESCE(r.rate, 1)
      FROM posting p
      LEFT JOIN rate r USING (account_rk);

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_finished := clock_timestamp();

    INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, rows_affected, extra)
    VALUES ('fill_account_turnover_f', 'dm.dm_account_turnover_f', 'END',
            v_started, v_finished, v_rows,
            format('on_date=%s; parent_log_id=%s; duration_sec=%s',
                   i_OnDate, v_log_id,
                   round(EXTRACT(EPOCH FROM v_finished - v_started)::numeric, 3)));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, extra)
    VALUES ('fill_account_turnover_f', 'dm.dm_account_turnover_f', 'ERROR',
            v_started, clock_timestamp(),
            format('on_date=%s; parent_log_id=%s; sqlerrm=%s',
                   i_OnDate, v_log_id, SQLERRM));
    RAISE;
END;
$$;

-- 1.2.b Витрина остатков.
-- Логика: для всех счетов, действующих на i_OnDate, считаем остаток как
-- остаток за предыдущий день +/- обороты (debet_amount/credit_amount). Знак
-- зависит от характеристики счёта: 'А' (активный) +debet−credit,
-- 'П' (пассивный) −debet+credit. Если оборотов в этот день не было, остаток
-- всё равно «протягивается» с предыдущего дня (LEFT JOIN turn + COALESCE 0).
CREATE OR REPLACE PROCEDURE ds.fill_account_balance_f(i_OnDate DATE)
LANGUAGE plpgsql AS $$
DECLARE
    v_log_id  BIGINT;
    v_started TIMESTAMP := clock_timestamp();
    v_finished TIMESTAMP;
    v_rows    BIGINT;
BEGIN
    INSERT INTO logs.etl_log(process, object_name, event, started_at, extra)
    VALUES ('fill_account_balance_f', 'dm.dm_account_balance_f', 'START',
            v_started, 'on_date=' || i_OnDate)
    RETURNING log_id INTO v_log_id;

    DELETE FROM dm.dm_account_balance_f WHERE on_date = i_OnDate;

    WITH active_accounts AS (
        SELECT account_rk, char_type, currency_rk
          FROM ds.md_account_d
         WHERE i_OnDate BETWEEN data_actual_date AND data_actual_end_date
    ),
    prev_bal AS (
        SELECT account_rk, balance_out, balance_out_rub
          FROM dm.dm_account_balance_f
         WHERE on_date = i_OnDate - INTERVAL '1 day'
    ),
    turn AS (
        SELECT account_rk, debet_amount, debet_amount_rub,
               credit_amount, credit_amount_rub
          FROM dm.dm_account_turnover_f
         WHERE on_date = i_OnDate
    )
    INSERT INTO dm.dm_account_balance_f(on_date, account_rk, balance_out, balance_out_rub)
    SELECT i_OnDate,
           a.account_rk,
           CASE a.char_type
                WHEN 'А' THEN COALESCE(p.balance_out,0)     + COALESCE(t.debet_amount,0)     - COALESCE(t.credit_amount,0)
                WHEN 'П' THEN COALESCE(p.balance_out,0)     - COALESCE(t.debet_amount,0)     + COALESCE(t.credit_amount,0)
           END,
           CASE a.char_type
                WHEN 'А' THEN COALESCE(p.balance_out_rub,0) + COALESCE(t.debet_amount_rub,0) - COALESCE(t.credit_amount_rub,0)
                WHEN 'П' THEN COALESCE(p.balance_out_rub,0) - COALESCE(t.debet_amount_rub,0) + COALESCE(t.credit_amount_rub,0)
           END
      FROM active_accounts a
      LEFT JOIN prev_bal p USING (account_rk)
      LEFT JOIN turn     t USING (account_rk);

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_finished := clock_timestamp();

    INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, rows_affected, extra)
    VALUES ('fill_account_balance_f', 'dm.dm_account_balance_f', 'END',
            v_started, v_finished, v_rows,
            format('on_date=%s; parent_log_id=%s; duration_sec=%s',
                   i_OnDate, v_log_id,
                   round(EXTRACT(EPOCH FROM v_finished - v_started)::numeric, 3)));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, extra)
    VALUES ('fill_account_balance_f', 'dm.dm_account_balance_f', 'ERROR',
            v_started, clock_timestamp(),
            format('on_date=%s; parent_log_id=%s; sqlerrm=%s',
                   i_OnDate, v_log_id, SQLERRM));
    RAISE;
END;
$$;

-- 1.3 Расчёт 101 формы.
-- i_OnDate — первый день месяца, следующего за отчётным.
CREATE OR REPLACE PROCEDURE dm.fill_f101_round_f(i_OnDate DATE)
LANGUAGE plpgsql AS $$
DECLARE
    v_started   TIMESTAMP := clock_timestamp();
    v_from_date DATE := (i_OnDate - INTERVAL '1 month')::date;
    v_to_date   DATE := (i_OnDate - INTERVAL '1 day')::date;
    v_prev_date DATE := v_from_date - INTERVAL '1 day';
    v_rows      BIGINT;
BEGIN
    INSERT INTO logs.etl_log(process, object_name, event, started_at, extra)
    VALUES ('fill_f101_round_f', 'dm.dm_f101_round_f', 'START',
            v_started, format('period=%s..%s', v_from_date, v_to_date));

    DELETE FROM dm.dm_f101_round_f
     WHERE from_date = v_from_date AND to_date = v_to_date;

    WITH accounts_period AS (
        -- счета, действующие в любой день отчётного периода
        SELECT DISTINCT
               a.account_rk,
               substr(a.account_number,1,5) AS ledger_account,
               a.char_type,
               a.currency_code
          FROM ds.md_account_d a
         WHERE a.data_actual_date     <= v_to_date
           AND a.data_actual_end_date >= v_from_date
    ),
    chapters AS (
        SELECT ledger_account::text AS ledger_account, MAX(chapter) AS chapter
          FROM ds.md_ledger_account_s
         GROUP BY ledger_account
    ),
    bal_in AS (
        SELECT account_rk, balance_out_rub
          FROM dm.dm_account_balance_f
         WHERE on_date = v_prev_date
    ),
    bal_out AS (
        SELECT account_rk, balance_out_rub
          FROM dm.dm_account_balance_f
         WHERE on_date = v_to_date
    ),
    turn_period AS (
        SELECT account_rk,
               SUM(debet_amount_rub)  AS turn_deb_rub_total,
               SUM(credit_amount_rub) AS turn_cre_rub_total
          FROM dm.dm_account_turnover_f
         WHERE on_date BETWEEN v_from_date AND v_to_date
         GROUP BY account_rk
    ),
    enriched AS (
        SELECT a.ledger_account,
               c.chapter,
               a.char_type,
               a.currency_code,
               COALESCE(bi.balance_out_rub, 0) AS bal_in_rub,
               COALESCE(bo.balance_out_rub, 0) AS bal_out_rub,
               COALESCE(tp.turn_deb_rub_total, 0) AS turn_deb_rub_total,
               COALESCE(tp.turn_cre_rub_total, 0) AS turn_cre_rub_total
          FROM accounts_period a
          LEFT JOIN chapters    c ON c.ledger_account = a.ledger_account
          LEFT JOIN bal_in      bi ON bi.account_rk = a.account_rk
          LEFT JOIN bal_out     bo ON bo.account_rk = a.account_rk
          LEFT JOIN turn_period tp ON tp.account_rk = a.account_rk
    )
    INSERT INTO dm.dm_f101_round_f(
        from_date, to_date, chapter, ledger_account, characteristic,
        balance_in_rub, balance_in_val, balance_in_total,
        turn_deb_rub, turn_deb_val, turn_deb_total,
        turn_cre_rub, turn_cre_val, turn_cre_total,
        balance_out_rub, balance_out_val, balance_out_total)
    SELECT v_from_date, v_to_date,
           MAX(chapter), ledger_account, MAX(char_type),
           SUM(CASE WHEN currency_code IN ('810','643') THEN bal_in_rub ELSE 0 END),
           SUM(CASE WHEN currency_code NOT IN ('810','643') THEN bal_in_rub ELSE 0 END),
           SUM(bal_in_rub),
           SUM(CASE WHEN currency_code IN ('810','643') THEN turn_deb_rub_total ELSE 0 END),
           SUM(CASE WHEN currency_code NOT IN ('810','643') THEN turn_deb_rub_total ELSE 0 END),
           SUM(turn_deb_rub_total),
           SUM(CASE WHEN currency_code IN ('810','643') THEN turn_cre_rub_total ELSE 0 END),
           SUM(CASE WHEN currency_code NOT IN ('810','643') THEN turn_cre_rub_total ELSE 0 END),
           SUM(turn_cre_rub_total),
           SUM(CASE WHEN currency_code IN ('810','643') THEN bal_out_rub ELSE 0 END),
           SUM(CASE WHEN currency_code NOT IN ('810','643') THEN bal_out_rub ELSE 0 END),
           SUM(bal_out_rub)
      FROM enriched
     GROUP BY ledger_account;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, rows_affected, extra)
    VALUES ('fill_f101_round_f', 'dm.dm_f101_round_f', 'END',
            v_started, clock_timestamp(), v_rows,
            format('period=%s..%s', v_from_date, v_to_date));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO logs.etl_log(process, object_name, event, started_at, finished_at, extra)
    VALUES ('fill_f101_round_f', 'dm.dm_f101_round_f', 'ERROR',
            v_started, clock_timestamp(), SQLERRM);
    RAISE;
END;
$$;
