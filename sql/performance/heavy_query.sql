-- Самый тяжёлый запрос проекта: бета всех бумаг к индексу за период.
-- Считается напрямую по core.quote, минуя витрины, чтобы замер показывал
-- работу с основной таблицей: оконная функция по 47 тысячам строк,
-- соединение с историей индекса и агрегаты по каждой бумаге.

WITH dohodnosti AS (
    SELECT secid,
           trade_date,
           close / lag(close) OVER (PARTITION BY secid ORDER BY trade_date) - 1 AS ret_d
      FROM core.quote
     WHERE trade_date >= DATE '2025-01-01'
),
rynok AS (
    SELECT trade_date,
           close / lag(close) OVER (ORDER BY trade_date) - 1 AS ret_rynka
      FROM core.index_quote
     WHERE index_id = 'IMOEX'
       AND trade_date >= DATE '2025-01-01'
)
SELECT d.secid,
       count(*)                                        AS nablyudeniy,
       covar_samp(d.ret_d, r.ret_rynka)
           / nullif(var_samp(r.ret_rynka), 0)          AS beta_cov,
       regr_slope(d.ret_d, r.ret_rynka)                AS beta_regr
  FROM dohodnosti d
  JOIN rynok r ON r.trade_date = d.trade_date
 WHERE d.ret_d IS NOT NULL
   AND r.ret_rynka IS NOT NULL
 GROUP BY d.secid
 ORDER BY beta_cov DESC;
