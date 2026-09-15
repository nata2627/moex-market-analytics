-- Дубли «одна бумага — один день» внутри одного батча.
-- В core они невозможны из-за первичного ключа, поэтому смотрим в staging.
-- Дубли между батчами нормальны, внутри батча — признак сбоя пагинации.
SELECT _batch_id,
       secid,
       tradedate,
       count(*) AS povtorov
  FROM staging.quote_raw
 GROUP BY _batch_id, secid, tradedate
HAVING count(*) > 1
 ORDER BY povtorov DESC, secid
 LIMIT 20;
