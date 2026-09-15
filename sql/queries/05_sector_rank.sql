-- Рейтинг бумаг по доходности внутри сектора.
--
-- PARTITION BY sector_id делает рейтинг внутриотраслевым: сравнивать
-- доходность нефтяника с айтишником мало смысла, отраслевые циклы разные.
--
-- Три функции ранжирования различаются только при равных значениях:
--   row_number — сквозная нумерация, всегда уникальная
--   rank       — равным значениям один ранг, следующий номер пропускается
--   dense_rank — равным значениям один ранг, без пропусков
--
-- ntile(4) режет сектор на четыре группы равного размера. Рядом выводится
-- размер сектора: в секторе из одной бумаги квартиль не интерпретируется.

SELECT sector_name,
       secid,
       shortname,
       round((dohodnost_total * 100)::numeric, 1) AS dohodnost_pct,
       row_number() OVER w AS row_number,
       rank()       OVER w AS rank,
       dense_rank() OVER w AS dense_rank,
       ntile(4)     OVER w AS kvartil,
       count(*)     OVER (PARTITION BY sector_id) AS bumag_v_sektore,
       round((percent_rank() OVER w)::numeric, 2) AS percent_rank
  FROM marts.mv_security_stats
 WHERE sector_id IS NOT NULL
WINDOW w AS (PARTITION BY sector_id ORDER BY dohodnost_total DESC)
 ORDER BY sector_name, dohodnost_total DESC;
