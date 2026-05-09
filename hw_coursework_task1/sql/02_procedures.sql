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
