-- MARTS — витрины.
-- core хранит факты от биржи, marts — производные величины: доходности,
-- волатильность, беты, просадки.

-- ---------------------------------------------------------------------------
-- Дневные доходности акций (со скорректированными ценами)
-- ---------------------------------------------------------------------------
-- Материализованное представление: оконная функция по 47 тысячам строк,
-- результат меняется раз в сутки после загрузки. Обновляется вызовом
-- marts.refresh_all() в конце ETL.
DROP MATERIALIZED VIEW IF EXISTS marts.mv_security_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS marts.mv_index_return CASCADE;
DROP MATERIALIZED VIEW IF EXISTS marts.mv_daily_return CASCADE;

CREATE MATERIALIZED VIEW marts.mv_daily_return AS
WITH skorrektirovannye AS (
    SELECT q.secid,
           q.trade_date,
           q.close AS close_raw,
           -- Цена делится на произведение коэффициентов всех дроблений,
           -- случившихся после этого дня.
           q.close / coalesce(f.koef_droblenia, 1) AS close_adj,
           q.volume,
           q.value,
           q.numtrades
      FROM core.quote q
      -- LATERAL даёт подзапросу доступ к колонкам текущей строки.
      LEFT JOIN LATERAL (
            SELECT exp(sum(ln(s.ratio))) AS koef_droblenia
              FROM core.split s
             WHERE s.secid = q.secid
               AND s.split_date > q.trade_date
           ) f ON true
)
SELECT secid,
       trade_date,
       close_raw,
       close_adj,
       volume,
       value,
       numtrades,
       lag(close_adj) OVER w AS close_adj_vchera,
       -- PARTITION BY secid обязателен: иначе на стыке бумаг «вчерашней»
       -- ценой станет последняя цена предыдущей бумаги.
       close_adj / lag(close_adj) OVER w - 1 AS ret_d
  FROM skorrektirovannye
WINDOW w AS (PARTITION BY secid ORDER BY trade_date);

-- Уникальный индекс обязателен для REFRESH ... CONCURRENTLY.
CREATE UNIQUE INDEX mv_daily_return_pk   ON marts.mv_daily_return (secid, trade_date);
CREATE INDEX        mv_daily_return_date ON marts.mv_daily_return (trade_date);

COMMENT ON MATERIALIZED VIEW marts.mv_daily_return IS
    'Дневные доходности акций по ценам, скорректированным на дробления';

-- ---------------------------------------------------------------------------
-- Дневные доходности индексов
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW marts.mv_index_return AS
SELECT index_id,
       trade_date,
       close,
       close / lag(close) OVER (PARTITION BY index_id ORDER BY trade_date) - 1 AS ret_d
  FROM core.index_quote;

CREATE UNIQUE INDEX mv_index_return_pk   ON marts.mv_index_return (index_id, trade_date);
CREATE INDEX        mv_index_return_date ON marts.mv_index_return (trade_date);

-- ---------------------------------------------------------------------------
-- Сводка по бумаге: доходность, риск, бета, ликвидность
-- ---------------------------------------------------------------------------
-- Основа дашборда: таблица бет, диаграмма «доходность против волатильности»,
-- топ по доходности.
CREATE MATERIALIZED VIEW marts.mv_security_stats AS
WITH dohodnosti AS (
    SELECT secid, trade_date, ret_d, close_adj, value
      FROM marts.mv_daily_return
     WHERE ret_d IS NOT NULL
),
-- Бета считается по парам «доходность бумаги — доходность рынка» за один
-- и тот же день.
s_rynkom AS (
    SELECT d.secid,
           d.trade_date,
           d.ret_d           AS ret_bumagi,
           i.ret_d           AS ret_rynka
      FROM dohodnosti d
      JOIN marts.mv_index_return i
        ON i.trade_date = d.trade_date
       AND i.index_id = 'IMOEX'
     WHERE i.ret_d IS NOT NULL
),
granitsy AS (
    SELECT secid,
           min(trade_date) AS data_nachala,
           max(trade_date) AS data_kontsa,
           count(*)        AS torgovyh_dney
      FROM marts.mv_daily_return
     GROUP BY secid
),
tseny AS (
    SELECT g.secid,
           g.data_nachala,
           g.data_kontsa,
           g.torgovyh_dney,
           p1.close_adj AS tsena_nachalo,
           p2.close_adj AS tsena_konets
      FROM granitsy g
      JOIN marts.mv_daily_return p1 ON p1.secid = g.secid AND p1.trade_date = g.data_nachala
      JOIN marts.mv_daily_return p2 ON p2.secid = g.secid AND p2.trade_date = g.data_kontsa
),
-- Просадка относительно максимума, достигнутого до текущего дня.
prosadka AS (
    SELECT secid,
           min(close_adj / max_do_segodnya - 1) AS max_prosadka
      FROM (
            SELECT secid,
                   close_adj,
                   max(close_adj) OVER (PARTITION BY secid ORDER BY trade_date
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS max_do_segodnya
              FROM marts.mv_daily_return
           ) t
     GROUP BY secid
),
risk AS (
    SELECT secid,
           stddev_samp(ret_bumagi) * sqrt(252)            AS volatilnost_god,
           -- Две независимые оценки беты: по определению cov/var...
           covar_samp(ret_bumagi, ret_rynka)
               / nullif(var_samp(ret_rynka), 0)           AS beta_cov,
           -- ...и как наклон регрессии, regr_slope(Y, X).
           regr_slope(ret_bumagi, ret_rynka)              AS beta_regr,
           regr_r2(ret_bumagi, ret_rynka)                 AS r2,
           count(*)                                       AS nablyudeniy
      FROM s_rynkom
     GROUP BY secid
),
likvidnost AS (
    SELECT secid,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY value) AS mediana_oborota
      FROM dohodnosti
     GROUP BY secid
)
SELECT t.secid,
       sec.shortname,
       sect.sector_id,
       sect.sector_name,
       w.weight                                              AS ves_v_indekse,
       t.data_nachala,
       t.data_kontsa,
       t.torgovyh_dney,
       t.tsena_nachalo,
       t.tsena_konets,
       t.tsena_konets / t.tsena_nachalo - 1                   AS dohodnost_total,
       -- Годовая доходность через 252 торговых дня. Степень, а не деление
       -- на число лет: доходность накапливается произведением.
       power(t.tsena_konets / t.tsena_nachalo, 252.0 / t.torgovyh_dney) - 1 AS dohodnost_god,
       r.volatilnost_god,
       p.max_prosadka,
       r.beta_cov,
       r.beta_regr,
       r.r2,
       r.nablyudeniy,
       l.mediana_oborota
  FROM tseny t
  JOIN core.security      sec  ON sec.secid  = t.secid
  LEFT JOIN core.security_sector ss ON ss.secid = t.secid
  LEFT JOIN core.sector   sect ON sect.sector_id = ss.sector_id
  LEFT JOIN core.index_weight w ON w.secid = t.secid AND w.index_id = 'IMOEX'
  JOIN risk               r    ON r.secid   = t.secid
  JOIN prosadka           p    ON p.secid   = t.secid
  JOIN likvidnost         l    ON l.secid   = t.secid;

CREATE UNIQUE INDEX mv_security_stats_pk ON marts.mv_security_stats (secid);

COMMENT ON MATERIALIZED VIEW marts.mv_security_stats IS
    'Сводка по бумаге: доходность, годовая волатильность, максимальная просадка, бета двумя способами, медианный оборот';

-- ---------------------------------------------------------------------------
-- Накопленная доходность по дням
-- ---------------------------------------------------------------------------
-- Обычное представление: запрос лёгкий, а данные должны быть свежими сразу
-- после загрузки.
CREATE OR REPLACE VIEW marts.v_cumulative_return AS
SELECT secid,
       trade_date,
       ret_d,
       -- Накопленная доходность — произведение (1 + r). Оператора
       -- произведения в SQL нет, поэтому exp(sum(ln(...))).
       exp(sum(ln(1 + ret_d)) OVER (PARTITION BY secid ORDER BY trade_date
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) - 1
           AS dohodnost_nakoplennaya
  FROM marts.mv_daily_return
 WHERE ret_d IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Обновление всех витрин
-- ---------------------------------------------------------------------------
-- mv_security_stats читает две другие витрины, поэтому обновляется последней.
CREATE OR REPLACE FUNCTION marts.refresh_all() RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY marts.mv_daily_return;
    REFRESH MATERIALIZED VIEW CONCURRENTLY marts.mv_index_return;
    REFRESH MATERIALIZED VIEW CONCURRENTLY marts.mv_security_stats;
END $$ LANGUAGE plpgsql;

COMMENT ON FUNCTION marts.refresh_all() IS 'Пересборка витрин';
