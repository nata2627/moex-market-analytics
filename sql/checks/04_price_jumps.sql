-- Скачки цены больше 30% за день.
-- Порог не означает ошибку: на рынке 2022 года такие движения реальны.
-- Задача проверки — дать список для просмотра глазами, чтобы отличить
-- настоящий обвал от дробления акций.
WITH dohodnosti AS (
    SELECT secid,
           trade_date,
           close,
           lag(close) OVER (PARTITION BY secid ORDER BY trade_date) AS close_vchera
      FROM core.quote
)
SELECT secid,
       trade_date,
       close_vchera,
       close,
       round((close / close_vchera - 1) * 100, 1) AS izmenenie_pct
  FROM dohodnosti
 WHERE close_vchera IS NOT NULL
   AND abs(close / close_vchera - 1) > 0.30
 ORDER BY abs(close / close_vchera - 1) DESC
 LIMIT 20;
