-- Бета бумаги к индексу МосБиржи, двумя независимыми способами.
--
--   covar_samp / var_samp  — по определению беты
--   regr_slope(Y, X)       — наклон регрессии МНК, зависимая переменная первая
--
-- Считается по доходностям, а не по ценам: цены нестационарны и зависят от
-- масштаба, после дробления 1:100 бета по ценам изменилась бы в 100 раз.
-- Соединение по trade_date отбирает пары наблюдений за один и тот же день.
--
-- Последние две колонки — заведомо неверные варианты, оставлены для сравнения.

WITH pary AS (
    SELECT d.secid,
           d.trade_date,
           d.ret_d     AS ret_bumagi,
           i.ret_d     AS ret_rynka,
           d.close_adj AS tsena_bumagi,
           i.close     AS znachenie_indeksa
      FROM marts.mv_daily_return d
      JOIN marts.mv_index_return i
        ON i.trade_date = d.trade_date
       AND i.index_id   = 'IMOEX'
     WHERE d.ret_d IS NOT NULL
       AND i.ret_d IS NOT NULL
)
SELECT p.secid,
       s.shortname,
       count(*) AS nablyudeniy,
       round((covar_samp(ret_bumagi, ret_rynka) / var_samp(ret_rynka))::numeric, 6) AS beta_cov,
       round(regr_slope(ret_bumagi, ret_rynka)::numeric, 6)                          AS beta_regr,
       round(abs(covar_samp(ret_bumagi, ret_rynka) / var_samp(ret_rynka)
                 - regr_slope(ret_bumagi, ret_rynka))::numeric, 15)                  AS raznitsa,
       round(regr_r2(ret_bumagi, ret_rynka)::numeric, 3)                             AS r2,
       round(regr_slope(ret_rynka, ret_bumagi)::numeric, 6)                          AS oshibka_argumenty_naoborot,
       round(regr_slope(tsena_bumagi, znachenie_indeksa)::numeric, 6)                AS oshibka_beta_po_tsenam
  FROM pary p
  JOIN core.security s ON s.secid = p.secid
 GROUP BY p.secid, s.shortname
 ORDER BY beta_cov DESC;
