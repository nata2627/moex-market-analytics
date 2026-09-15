-- Ликвидность: распределение дневного оборота в рублях по бумагам.
--
-- Медиана, а не среднее: оборот сильно скошен, редкие дни отчётности
-- поднимают среднее выше типичного дня. Обе величины выводятся для сравнения.
-- percentile_cont интерполирует между наблюдениями, percentile_disc
-- возвращает реально существовавшее значение.
-- Межквартильный размах показывает, торгуется ли бумага ровно или рывками.
--
-- Приведения ::numeric нужны потому, что percentile_cont возвращает
-- double precision, а функции round(double, int) в PostgreSQL нет.

SELECT d.secid,
       s.shortname,
       count(*) AS torgovyh_dney,

       round((percentile_cont(0.25) WITHIN GROUP (ORDER BY d.value) / 1e6)::numeric, 1) AS q1_mln_rub,
       round((percentile_cont(0.50) WITHIN GROUP (ORDER BY d.value) / 1e6)::numeric, 1) AS mediana_mln_rub,
       round((percentile_cont(0.75) WITHIN GROUP (ORDER BY d.value) / 1e6)::numeric, 1) AS q3_mln_rub,

       round(((percentile_cont(0.75) WITHIN GROUP (ORDER BY d.value)
               - percentile_cont(0.25) WITHIN GROUP (ORDER BY d.value)) / 1e6)::numeric, 1) AS iqr_mln_rub,

       round(avg(d.value) / 1e6, 1) AS srednee_mln_rub,
       round(avg(d.value) / nullif(percentile_cont(0.50) WITHIN GROUP (ORDER BY d.value)::numeric, 0), 2)
           AS srednee_k_mediane,
       round(percentile_disc(0.50) WITHIN GROUP (ORDER BY d.value) / 1e6, 1) AS mediana_disc_mln_rub,
       round(max(d.value) / 1e6, 1) AS maksimum_mln_rub
  FROM marts.mv_daily_return d
  JOIN core.security s ON s.secid = d.secid
 GROUP BY d.secid, s.shortname
 ORDER BY mediana_mln_rub DESC
 LIMIT 15;
