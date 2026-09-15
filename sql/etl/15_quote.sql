-- staging.quote_raw -> core.quote
--
-- Идемпотентность загрузки: первичный ключ (secid, trade_date) ловит
-- повторную вставку, поведение при конфликте зависит от режима.
--   refresh = false — WHERE false отключает UPDATE, конструкция работает как
--       DO NOTHING: прошлое не переписывается. Это режим по умолчанию.
--   refresh = true  — строка обновляется, если значения действительно
--       изменились. Нужен, потому что биржа пересчитывает итоги задним числом.
--
-- IS DISTINCT FROM, а не <>: NULL <> NULL даёт NULL, и через <> две одинаково
-- пустые waprice считались бы различными.

INSERT INTO core.quote (secid, trade_date, open, high, low, close, waprice, volume, value, numtrades)
SELECT DISTINCT ON (secid, tradedate)
       secid,
       tradedate::date,
       NULLIF(btrim(open),    '')::numeric,
       NULLIF(btrim(high),    '')::numeric,
       NULLIF(btrim(low),     '')::numeric,
       NULLIF(btrim(close),   '')::numeric,
       NULLIF(btrim(waprice), '')::numeric,
       COALESCE(NULLIF(btrim(volume), '')::numeric, 0)::bigint,
       COALESCE(NULLIF(btrim(value),  '')::numeric, 0),
       NULLIF(btrim(numtrades), '')::integer
  FROM staging.quote_raw
 WHERE _batch_id = %(batch_id)s
   -- Дни без сделок биржа отдаёт с пустыми или нулевыми ценами. Отсеиваем
   -- здесь, чтобы они не упирались в CHECK price > 0. Количество видно
   -- в load_log как разница rows_fetched и rows_inserted.
   AND NULLIF(btrim(open),  '')::numeric > 0
   AND NULLIF(btrim(high),  '')::numeric > 0
   AND NULLIF(btrim(low),   '')::numeric > 0
   AND NULLIF(btrim(close), '')::numeric > 0
 ORDER BY secid, tradedate, _loaded_at DESC
    ON CONFLICT ON CONSTRAINT quote_pk DO UPDATE
   SET open      = EXCLUDED.open,
       high      = EXCLUDED.high,
       low       = EXCLUDED.low,
       close     = EXCLUDED.close,
       waprice   = EXCLUDED.waprice,
       volume    = EXCLUDED.volume,
       value     = EXCLUDED.value,
       numtrades = EXCLUDED.numtrades
 WHERE %(refresh)s
   AND (core.quote.open, core.quote.high, core.quote.low, core.quote.close,
        core.quote.waprice, core.quote.volume, core.quote.value, core.quote.numtrades)
       IS DISTINCT FROM
       (EXCLUDED.open, EXCLUDED.high, EXCLUDED.low, EXCLUDED.close,
        EXCLUDED.waprice, EXCLUDED.volume, EXCLUDED.value, EXCLUDED.numtrades);
