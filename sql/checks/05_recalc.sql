-- Ретроспективный пересчёт итогов торгов биржей.
-- Возможна благодаря append-only staging: сравниваем, что источник отдавал
-- за одну дату в разные прогоны. Найденные расхождения подтягиваются
-- командой `make refresh` — обычный прогон их в core не пустит.
WITH versii AS (
    SELECT secid,
           tradedate,
           nullif(btrim(close), '')::numeric AS close,
           _batch_id,
           _loaded_at
      FROM staging.quote_raw
)
SELECT secid,
       tradedate,
       count(DISTINCT close)          AS raznyh_znacheniy,
       min(close)                     AS min_close,
       max(close)                     AS max_close,
       count(DISTINCT _batch_id)      AS batchey
  FROM versii
 GROUP BY secid, tradedate
HAVING count(DISTINCT close) > 1
 ORDER BY secid, tradedate
 LIMIT 20;
