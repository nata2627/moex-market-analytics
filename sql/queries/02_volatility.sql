-- Скользящая волатильность за 30 торговых дней, в годовом выражении.
--
-- Годовая волатильность = дневная * sqrt(252): стандартное отклонение растёт
-- как корень из времени.
-- stddev_samp (деление на n-1), а не stddev_pop: это выборка наблюдений.
-- Рамка ROWS, а не RANGE: нужны 30 торговых дней, а не 30 календарных.

WITH volatilnost AS (
    SELECT secid,
           trade_date,
           ret_d,
           stddev_samp(ret_d) OVER (
               PARTITION BY secid ORDER BY trade_date
               ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
           ) AS vol_dnevnaya,
           count(*) OVER (
               PARTITION BY secid ORDER BY trade_date
               ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
           ) AS nablyudeniy_v_okne
      FROM marts.mv_daily_return
     WHERE ret_d IS NOT NULL
)
SELECT secid,
       trade_date,
       round((vol_dnevnaya * 100)::numeric, 2)             AS vol_dnevnaya_pct,
       round((vol_dnevnaya * sqrt(252) * 100)::numeric, 1) AS vol_godovaya_pct
  FROM volatilnost
 WHERE nablyudeniy_v_okne = 30      -- отбрасываем неполные окна
   AND secid = 'SBER'
 ORDER BY trade_date DESC
 LIMIT 10;

-- Самые волатильные бумаги на последнюю дату торгов каждой бумаги.
WITH volatilnost AS (
    SELECT secid,
           trade_date,
           stddev_samp(ret_d) OVER (
               PARTITION BY secid ORDER BY trade_date
               ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
           ) * sqrt(252) AS vol_god,
           count(*) OVER (
               PARTITION BY secid ORDER BY trade_date
               ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
           ) AS n,
           row_number() OVER (PARTITION BY secid ORDER BY trade_date DESC) AS rn
      FROM marts.mv_daily_return
     WHERE ret_d IS NOT NULL
)
SELECT v.secid,
       s.shortname,
       v.trade_date,
       round((v.vol_god * 100)::numeric, 1) AS vol_godovaya_pct
  FROM volatilnost v
  JOIN core.security s ON s.secid = v.secid
 WHERE v.rn = 1 AND v.n = 30
 ORDER BY v.vol_god DESC
 LIMIT 10;
