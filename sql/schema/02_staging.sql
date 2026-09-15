-- STAGING — сырой слой.
--
-- Все содержательные колонки text: типизация отложена до перелива в core,
-- чтобы неожиданный формат в ответе API не ронял загрузку.
--
-- Первичных ключей нет намеренно. Staging append-only: каждый прогон
-- дописывает батч, что позволяет сравнить ответы API за разные дни и поймать
-- ретроспективный пересчёт итогов торгов. Защита от дублей — на переливе.
--
-- Имена колонок соответствуют columns из JSON-ответа.

CREATE TABLE IF NOT EXISTS staging.load_log (
    batch_id       uuid PRIMARY KEY,
    entity         text        NOT NULL,   -- quote / index_quote / index_weight / security
    started_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz,
    rows_fetched   integer,
    rows_inserted  integer,                -- сколько реально дошло до core
    status         text        NOT NULL DEFAULT 'running',
    error_text     text
);
COMMENT ON TABLE staging.load_log IS 'Журнал прогонов ETL: что, когда, сколько строк, чем закончилось';

-- Дневные котировки акций: /history/.../boards/TQBR/securities/{SECID}.json
CREATE TABLE IF NOT EXISTS staging.quote_raw (
    boardid           text,
    tradedate         text,
    shortname         text,
    secid             text,
    numtrades         text,
    value             text,
    open              text,
    low               text,
    high              text,
    legalcloseprice   text,
    waprice           text,
    close             text,
    volume            text,
    _batch_id         uuid        NOT NULL,
    _loaded_at        timestamptz NOT NULL DEFAULT now(),
    _source_url       text        NOT NULL
);

-- История индексов: /history/.../markets/index/securities/{INDEXID}.json
CREATE TABLE IF NOT EXISTS staging.index_quote_raw (
    boardid           text,
    secid             text,
    tradedate         text,
    shortname         text,
    name              text,
    close             text,
    open              text,
    high              text,
    low               text,
    value             text,
    capitalization    text,
    divisor           text,
    currencyid        text,
    _batch_id         uuid        NOT NULL,
    _loaded_at        timestamptz NOT NULL DEFAULT now(),
    _source_url       text        NOT NULL
);

-- Состав индексов с весами: /statistics/.../index/analytics/{INDEXID}.json
-- Один и тот же эндпоинт даёт и IMOEX (веса), и отраслевые индексы (сектора).
CREATE TABLE IF NOT EXISTS staging.index_weight_raw (
    indexid           text,
    tradedate         text,
    ticker            text,
    shortnames        text,
    secids            text,
    weight            text,
    _batch_id         uuid        NOT NULL,
    _loaded_at        timestamptz NOT NULL DEFAULT now(),
    _source_url       text        NOT NULL
);

-- Справочник бумаг: /engines/stock/markets/shares/boards/TQBR/securities.json
CREATE TABLE IF NOT EXISTS staging.security_raw (
    secid             text,
    boardid           text,
    shortname         text,
    secname           text,
    latname           text,
    isin              text,
    regnumber         text,
    lotsize           text,
    facevalue         text,
    faceunit          text,
    issuesize         text,
    listlevel         text,
    sectype           text,
    sectorid          text,      -- в API всегда null, сохраняем как есть
    status            text,
    decimals          text,
    minstep           text,
    prevdate          text,
    _batch_id         uuid        NOT NULL,
    _loaded_at        timestamptz NOT NULL DEFAULT now(),
    _source_url       text        NOT NULL
);

-- Индексы по _batch_id: чистка батчей и сравнение версий строк идут по нему.
CREATE INDEX IF NOT EXISTS quote_raw_batch_idx       ON staging.quote_raw (_batch_id);
CREATE INDEX IF NOT EXISTS index_quote_raw_batch_idx ON staging.index_quote_raw (_batch_id);
