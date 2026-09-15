-- Срез рынка на одну дату. Ведущее условие — trade_date, secid не задан:
-- случай, ради которого создан индекс (trade_date, secid).
SELECT q.secid, q.close, q.value, q.numtrades
  FROM core.quote q
 WHERE q.trade_date = DATE '2026-09-14'
 ORDER BY q.value DESC;
