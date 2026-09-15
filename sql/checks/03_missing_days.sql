-- Пропуски торговых дней относительно календаря индекса.
-- Эталон — core.trading_day. Границы берутся по каждой бумаге отдельно:
-- бумаги с поздним началом торгов иначе дали бы сотни ложных пропусков.
WITH granitsy AS (
    SELECT secid,
           min(trade_date) AS nachalo,
           max(trade_date) AS konets
      FROM core.quote
     GROUP BY secid
),
propuski AS (
    SELECT g.secid,
           td.trade_date
      FROM granitsy g
      JOIN core.trading_day td
        ON td.trade_date BETWEEN g.nachalo AND g.konets
      -- NOT EXISTS, а не LEFT JOIN ... IS NULL: читается как «нет такой
      -- котировки» и планировщику проще — он останавливается на первом
      -- найденном совпадении, а не строит полное соединение.
     WHERE NOT EXISTS (
               SELECT 1 FROM core.quote q
                WHERE q.secid = g.secid AND q.trade_date = td.trade_date
           )
)
SELECT secid,
       count(*)      AS propuscheno_dney,
       min(trade_date) AS pervyy,
       max(trade_date) AS posledniy
  FROM propuski
 GROUP BY secid
 ORDER BY propuscheno_dney DESC
 LIMIT 20;
