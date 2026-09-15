-- Максимальная просадка: отклонение цены от максимума, достигнутого до этого дня.
--
-- Наивный вариант min(close)/max(close) - 1 неверен, если минимум был раньше
-- максимума: получится просадка, которую инвестор не мог пережить.
-- Рамка UNBOUNDED PRECEDING .. CURRENT ROW даёт максимум на текущий момент.
-- Окно без ORDER BY вернуло бы максимум за всю историю, включая будущее —
-- вторая колонка показывает этот эффект.

WITH prosadka AS (
    SELECT secid,
           trade_date,
           close_adj,
           max(close_adj) OVER (PARTITION BY secid ORDER BY trade_date
                                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
               AS pik_na_tekushchiy_moment,
           max(close_adj) OVER (PARTITION BY secid) AS pik_za_vsyu_istoriyu
      FROM marts.mv_daily_return
)
SELECT secid,
       trade_date,
       close_adj,
       pik_na_tekushchiy_moment,
       round(((close_adj / pik_na_tekushchiy_moment - 1) * 100)::numeric, 1) AS prosadka_pct,
       round(((close_adj / pik_za_vsyu_istoriyu    - 1) * 100)::numeric, 1) AS prosadka_s_zaglyadyvaniem_pct
  FROM prosadka
 WHERE secid = 'SBER'
 ORDER BY trade_date
 LIMIT 10;

-- Максимальная просадка каждой бумаги и дата дна.
WITH poten AS (
    SELECT secid,
           trade_date,
           close_adj / max(close_adj) OVER (PARTITION BY secid ORDER BY trade_date
                                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) - 1
               AS prosadka
      FROM marts.mv_daily_return
),
dno AS (
    SELECT DISTINCT ON (secid) secid, trade_date, prosadka
      FROM poten
     ORDER BY secid, prosadka
)
SELECT d.secid,
       s.shortname,
       round((d.prosadka * 100)::numeric, 1) AS max_prosadka_pct,
       d.trade_date                          AS data_dna
  FROM dno d
  JOIN core.security s ON s.secid = d.secid
 ORDER BY d.prosadka
 LIMIT 12;
