-- staging.index_quote_raw -> core.index_quote
INSERT INTO core.index_quote (index_id, trade_date, open, high, low, close, value, capitalization)
SELECT DISTINCT ON (secid, tradedate)
       secid,
       tradedate::date,
       NULLIF(btrim(open),  '')::numeric,
       NULLIF(btrim(high),  '')::numeric,
       NULLIF(btrim(low),   '')::numeric,
       NULLIF(btrim(close), '')::numeric,
       NULLIF(btrim(value), '')::numeric,
       NULLIF(btrim(capitalization), '')::numeric
  FROM staging.index_quote_raw
 WHERE _batch_id = %(batch_id)s
   AND NULLIF(btrim(close), '')::numeric > 0
 ORDER BY secid, tradedate, _loaded_at DESC
    ON CONFLICT (index_id, trade_date) DO UPDATE
   SET close          = EXCLUDED.close,
       open           = EXCLUDED.open,
       high           = EXCLUDED.high,
       low            = EXCLUDED.low,
       value          = EXCLUDED.value,
       capitalization = EXCLUDED.capitalization
 WHERE %(refresh)s;
