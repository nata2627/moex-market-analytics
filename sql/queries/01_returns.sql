-- Дневная и накопленная доходность бумаг.
--
-- Накопленная доходность считается как произведение (1 + r), а не сумма r.
-- Оператора произведения в SQL нет, поэтому используется exp(sum(ln(...))).
-- Для сравнения выводится и ошибочный вариант через сумму.

SELECT secid,
       trade_date,
       close_adj,
       round((ret_d * 100)::numeric, 2) AS dohodnost_dnevnaya_pct,
       round((
           (exp(sum(ln(1 + ret_d)) OVER (PARTITION BY secid ORDER BY trade_date
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) - 1)
           * 100)::numeric, 2) AS dohodnost_nakoplennaya_pct,
       round((sum(ret_d) OVER (PARTITION BY secid ORDER BY trade_date
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              * 100)::numeric, 2) AS oshibochno_summa_pct
  FROM marts.mv_daily_return
 WHERE ret_d IS NOT NULL
   AND secid = 'SBER'
 ORDER BY trade_date DESC
 LIMIT 10;

-- Расхождение правильного и ошибочного способов по всем бумагам за период.
SELECT secid,
       round(((exp(sum(ln(1 + ret_d))) - 1) * 100)::numeric, 1) AS pravilno_proizvedenie_pct,
       round((sum(ret_d) * 100)::numeric, 1)                     AS oshibochno_summa_pct,
       round((((exp(sum(ln(1 + ret_d))) - 1) - sum(ret_d)) * 100)::numeric, 1) AS raskhozhdenie_pp
  FROM marts.mv_daily_return
 WHERE ret_d IS NOT NULL
 GROUP BY secid
 ORDER BY abs((exp(sum(ln(1 + ret_d))) - 1) - sum(ret_d)) DESC
 LIMIT 10;
