-- Проверка допущения схемы: бумага входит ровно в один отраслевой индекс.
-- Нарушение роняет загрузку — иначе дублирующаяся бумага тихо исказила бы
-- рейтинги по секторам и границы квартилей NTILE.
--
-- Знаки процента здесь одинарные: файл выполняется без параметров psycopg,
-- batch_id читается из настройки сессии.
DO $$
DECLARE
    bad text;
BEGIN
    SELECT string_agg(ticker || ' -> ' || idx, '; ')
      INTO bad
      FROM (SELECT ticker, string_agg(DISTINCT indexid, ',') AS idx
              FROM staging.index_weight_raw
             WHERE _batch_id = current_setting('etl.batch_id')::uuid
               AND indexid LIKE 'MOEX%'
               AND indexid <> 'IMOEX'
             GROUP BY ticker
            HAVING count(DISTINCT indexid) > 1) t;

    IF bad IS NOT NULL THEN
        RAISE EXCEPTION
            'Бумага входит в несколько отраслевых индексов: %. Допущение "один сектор на бумагу" нарушено, схему надо пересматривать.',
            bad;
    END IF;
END $$;
