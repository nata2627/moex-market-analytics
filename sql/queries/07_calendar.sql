-- Торговый календарь и поиск пропусков.
--
-- Отсутствующую строку нельзя найти запросом к таблице, где её нет, поэтому
-- нужен внешний список дат: generate_series даёт полный календарь, а эталоном
-- торговых дней служит core.trading_day — даты, по которым рассчитан IMOEX.

-- Календарь с пометкой торговых дней.
SELECT d::date AS data,
       to_char(d, 'TMDay') AS den_nedeli,
       (td.trade_date IS NOT NULL) AS birzha_rabotala
  FROM generate_series(DATE '2022-02-18', DATE '2022-03-31', INTERVAL '1 day') AS g(d)
  LEFT JOIN core.trading_day td ON td.trade_date = d::date
 ORDER BY d;

-- Непрерывные периоды закрытия биржи (приём «острова и промежутки»):
-- у подряд идущих дат разность «дата минус номер строки» постоянна.
WITH kalendar AS (
    SELECT d::date AS data,
           (td.trade_date IS NOT NULL) AS torgoval
      FROM generate_series(DATE '2022-01-01', DATE '2022-12-31', INTERVAL '1 day') AS g(d)
      LEFT JOIN core.trading_day td ON td.trade_date = d::date
),
nerabochie AS (
    SELECT data,
           data - (row_number() OVER (ORDER BY data))::int AS gruppa
      FROM kalendar
     WHERE NOT torgoval
)
SELECT min(data) AS s,
       max(data) AS po,
       count(*)  AS kalendarnyh_dney,
       count(*) FILTER (WHERE extract(isodow FROM data) <= 5) AS iz_nih_budnih
  FROM nerabochie
 GROUP BY gruppa
HAVING count(*) FILTER (WHERE extract(isodow FROM data) <= 5) >= 3
 ORDER BY 1;

-- Пропуски по бумагам: биржа работала, а бумага не торговалась.
-- Границы берутся по каждой бумаге отдельно, иначе бумаги с поздним началом
-- торгов дали бы сотни ложных пропусков.
WITH granitsy AS (
    SELECT secid, min(trade_date) AS nachalo, max(trade_date) AS konets
      FROM core.quote
     GROUP BY secid
),
propuski AS (
    SELECT g.secid, td.trade_date
      FROM granitsy g
      JOIN core.trading_day td ON td.trade_date BETWEEN g.nachalo AND g.konets
     WHERE NOT EXISTS (SELECT 1 FROM core.quote q
                        WHERE q.secid = g.secid AND q.trade_date = td.trade_date)
)
SELECT p.secid,
       s.shortname,
       count(*)        AS propuscheno_dney,
       min(trade_date) AS pervyy_propusk,
       max(trade_date) AS posledniy_propusk
  FROM propuski p
  JOIN core.security s ON s.secid = p.secid
 GROUP BY p.secid, s.shortname
 ORDER BY propuscheno_dney DESC
 LIMIT 10;
