-- Сектор бумаги — отраслевой индекс MOEX, в который она входит.
-- Поле SECTORID в справочнике у всех бумаг TQBR равно NULL.
--
-- Знаки процента удвоены: операторы выполняются с параметрами psycopg,
-- который трактует одиночный процент как свой плейсхолдер. Правило
-- распространяется и на комментарии — драйвер разбирает текст целиком.
INSERT INTO core.security_sector (secid, sector_id)
SELECT DISTINCT ON (w.ticker) w.ticker, w.indexid
  FROM staging.index_weight_raw w
  JOIN core.security s ON s.secid = w.ticker      -- только бумаги из справочника
 WHERE w._batch_id = %(batch_id)s
   AND w.indexid LIKE 'MOEX%%'
   AND w.indexid <> 'IMOEX'                       -- IMOEX не сектор, а весь рынок
 ORDER BY w.ticker, w.indexid
    ON CONFLICT (secid) DO UPDATE
   SET sector_id = EXCLUDED.sector_id;

-- Бумаги, не попавшие ни в один отраслевой индекс (АФК «Система» —
-- многопрофильный холдинг), уходят в «Прочее»: иначе они выпадут из
-- рейтингов и сумма по секторам не сойдётся с рынком.
INSERT INTO core.security_sector (secid, sector_id)
SELECT DISTINCT w.ticker, 'OTHER'
  FROM staging.index_weight_raw w
  JOIN core.security s ON s.secid = w.ticker
 WHERE w._batch_id = %(batch_id)s
   AND w.indexid = 'IMOEX'
   AND NOT EXISTS (SELECT 1 FROM core.security_sector ss WHERE ss.secid = w.ticker)
    ON CONFLICT (secid) DO NOTHING;
