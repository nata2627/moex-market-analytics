-- staging.index_weight_raw -> core.index_weight (только веса IMOEX)
INSERT INTO core.index_weight (index_id, weight_date, secid, weight)
SELECT DISTINCT ON (indexid, tradedate, ticker)
       w.indexid,
       w.tradedate::date,
       w.ticker,
       NULLIF(btrim(w.weight), '')::numeric
  FROM staging.index_weight_raw w
  JOIN core.security s ON s.secid = w.ticker
 WHERE w._batch_id = %(batch_id)s
   AND w.indexid = 'IMOEX'
   AND NULLIF(btrim(w.weight), '')::numeric IS NOT NULL
 ORDER BY indexid, tradedate, ticker, _loaded_at DESC
    ON CONFLICT (index_id, weight_date, secid) DO UPDATE
   SET weight = EXCLUDED.weight
 WHERE %(refresh)s;
