-- Детектирование дроблений акций по котировкам.
--
-- Работает по core.quote, а не по staging: нужны типизированные цены и
-- гарантия «одна бумага — один день».
--
-- Находим дни с изменением цены более чем вдвое, подбираем ближайший
-- стандартный коэффициент дробления, сохраняем и наблюдаемое отношение,
-- и округлённое.
WITH dvizheniya AS (
    SELECT secid,
           trade_date,
           close,
           -- PARTITION BY secid: цена предыдущего торгового дня этой же бумаги.
           lag(close) OVER (PARTITION BY secid ORDER BY trade_date) AS close_vchera
      FROM core.quote
),
kandidaty AS (
    SELECT secid,
           trade_date,
           close_vchera / close AS ratio_raw
      FROM dvizheniya
     WHERE close_vchera IS NOT NULL
       -- Порог: цена изменилась более чем вдвое в любую сторону.
       AND (close_vchera / close >= 2 OR close_vchera / close <= 0.5)
),
-- Стандартные пропорции дробления и обратного дробления.
standartnye AS (
    SELECT k AS koef FROM unnest(ARRAY[2,3,4,5,10,20,25,50,100,200,500,1000,2000,5000,10000]::numeric[]) AS k
    UNION ALL
    SELECT 1 / k     FROM unnest(ARRAY[2,3,4,5,10,20,25,50,100,200,500,1000,2000,5000,10000]::numeric[]) AS k
)
INSERT INTO core.split (secid, split_date, ratio, ratio_raw)
SELECT k.secid,
       k.trade_date,
       b.koef,
       k.ratio_raw
  FROM kandidaty k
  -- LATERAL: для каждого кандидата ищем свой ближайший коэффициент.
  CROSS JOIN LATERAL (
        SELECT s.koef
          FROM standartnye s
         -- Расстояние по логарифмам: иначе крупные коэффициенты всегда
         -- оказывались бы «ближе» друг к другу, чем мелкие.
         ORDER BY abs(ln(s.koef) - ln(k.ratio_raw))
         LIMIT 1
       ) b
    ON CONFLICT (secid, split_date) DO NOTHING;
