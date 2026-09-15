-- Отрицательные и нулевые значения в staging.
-- Нулевая цена при нулевом объёме — день без торгов, это нормально.
-- Нулевая цена при ненулевом объёме — аномалия.
SELECT count(*) FILTER (WHERE tsena_ne_polozhitelnaya)                          AS vsego_s_nulevoy_tsenoy,
       count(*) FILTER (WHERE tsena_ne_polozhitelnaya AND net_torgov)            AS iz_nih_dney_bez_torgov,
       count(*) FILTER (WHERE tsena_ne_polozhitelnaya AND NOT net_torgov)        AS podozritelnyh,
       count(*) FILTER (WHERE otritsatelnyy_obyom)                               AS otritsatelnyy_obyom
  FROM (
        SELECT coalesce(nullif(btrim(close), '')::numeric, 0) <= 0
                 OR coalesce(nullif(btrim(open), '')::numeric, 0) <= 0  AS tsena_ne_polozhitelnaya,
               coalesce(nullif(btrim(volume), '')::numeric, 0) = 0
                 AND coalesce(nullif(btrim(numtrades), '')::numeric, 0) = 0 AS net_torgov,
               coalesce(nullif(btrim(volume), '')::numeric, 0) < 0
                 OR coalesce(nullif(btrim(value), '')::numeric, 0) < 0     AS otritsatelnyy_obyom
          FROM staging.quote_raw
       ) t;
