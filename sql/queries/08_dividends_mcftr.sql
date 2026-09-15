-- Доходность с учётом дивидендов против «чистой».
--
-- Источник: пара индексов МосБиржи.
--   IMOEX — ценовой, считается только по ценам акций
--   MCFTR — полной доходности, дивиденды реинвестируются
-- Их расхождение и есть вклад дивидендов. Дивиденды по отдельным бумагам
-- открытый ISS API больше не отдаёт: /iss/cci/corp-actions/dividends
-- требует подписки.
--
-- Падение цены в день отсечки — не убыток: деньги ушли акционеру. Ценовой
-- индекс считает это потерей, индекс полной доходности — нет.
--
-- Вклад дивидендов = (1+r_полн)/(1+r_цен) - 1, то есть отношение, а не
-- разность процентов. Разность посчитана рядом для сравнения.
--
-- Оба индекса берутся на общих датах: у MCFTR данные публикуются с задержкой
-- на день, и сравнение по собственным последним датам исказило бы результат.

WITH obshchie_daty AS (
    SELECT i.trade_date
      FROM core.index_quote i
      JOIN core.index_quote m ON m.trade_date = i.trade_date AND m.index_id = 'MCFTR'
     WHERE i.index_id = 'IMOEX'
),
granitsy AS (
    SELECT index_id, min(trade_date) AS d1, max(trade_date) AS d2
      FROM core.index_quote
     WHERE index_id IN ('IMOEX', 'MCFTR')
       AND trade_date IN (SELECT trade_date FROM obshchie_daty)
     GROUP BY index_id
),
znacheniya AS (
    SELECT g.index_id,
           g.d1, g.d2,
           q1.close AS nachalo,
           q2.close AS konets,
           q2.close / q1.close - 1 AS dohodnost
      FROM granitsy g
      JOIN core.index_quote q1 ON q1.index_id = g.index_id AND q1.trade_date = g.d1
      JOIN core.index_quote q2 ON q2.index_id = g.index_id AND q2.trade_date = g.d2
)
SELECT index_id,
       CASE index_id WHEN 'IMOEX' THEN 'без дивидендов (ценовой)'
                     WHEN 'MCFTR' THEN 'с дивидендами (полной доходности)' END AS chto_eto,
       d1 AS s, d2 AS po,
       round(nachalo, 2) AS znachenie_nachalo,
       round(konets, 2)  AS znachenie_konets,
       round((dohodnost * 100), 1) AS dohodnost_pct
  FROM znacheniya
 ORDER BY index_id;

-- Чистый вклад дивидендов за весь период.
WITH obshchie_daty AS (
    SELECT i.trade_date
      FROM core.index_quote i
      JOIN core.index_quote m ON m.trade_date = i.trade_date AND m.index_id = 'MCFTR'
     WHERE i.index_id = 'IMOEX'
),
period AS (
    SELECT min(trade_date) AS d1, max(trade_date) AS d2 FROM obshchie_daty
),
po_indeksam AS (
    SELECT i.index_id,
           max(i.close) FILTER (WHERE i.trade_date = p.d1) AS nachalo,
           max(i.close) FILTER (WHERE i.trade_date = p.d2) AS konets
      FROM core.index_quote i
     CROSS JOIN period p
     WHERE i.index_id IN ('IMOEX', 'MCFTR')
     GROUP BY i.index_id
),
svod AS (
    SELECT max(konets / nachalo) FILTER (WHERE index_id = 'IMOEX') AS rost_tsenovoy,
           max(konets / nachalo) FILTER (WHERE index_id = 'MCFTR') AS rost_polnyy
      FROM po_indeksam
)
SELECT round((rost_tsenovoy - 1) * 100, 1) AS tsenovaya_dohodnost_pct,
       round((rost_polnyy   - 1) * 100, 1) AS polnaya_dohodnost_pct,
       round((rost_polnyy / rost_tsenovoy - 1) * 100, 1) AS vklad_dividendov_pct,
       round(((rost_polnyy - 1) - (rost_tsenovoy - 1)) * 100, 1) AS oshibochno_raznost_pp
  FROM svod;

-- Вклад дивидендов по годам.
WITH dnevnye AS (
    SELECT p.trade_date,
           p.ret_d AS ret_polnyy,
           c.ret_d AS ret_tsenovoy
      FROM marts.mv_index_return p
      JOIN marts.mv_index_return c ON c.trade_date = p.trade_date AND c.index_id = 'IMOEX'
     WHERE p.index_id = 'MCFTR'
       AND p.ret_d IS NOT NULL AND c.ret_d IS NOT NULL
)
SELECT extract(year FROM trade_date)::int AS god,
       round(((exp(sum(ln(1 + ret_tsenovoy))) - 1) * 100)::numeric, 1) AS bez_dividendov_pct,
       round(((exp(sum(ln(1 + ret_polnyy)))   - 1) * 100)::numeric, 1) AS s_dividendami_pct,
       round(((exp(sum(ln(1 + ret_polnyy))) / exp(sum(ln(1 + ret_tsenovoy))) - 1) * 100)::numeric, 1)
           AS vklad_dividendov_pct
  FROM dnevnye
 GROUP BY god
 ORDER BY god;
