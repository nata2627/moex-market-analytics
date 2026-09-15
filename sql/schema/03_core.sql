-- CORE — очищенный слой.
-- Каждое ограничение фиксирует утверждение «такого в данных быть не может»:
-- нарушение роняет загрузку вместо того, чтобы тихо испортить витрину.

-- ---------------------------------------------------------------------------
-- Справочник бумаг
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.security (
    secid       text PRIMARY KEY,
    shortname   text NOT NULL,
    secname     text,
    isin        text,
    lotsize     integer,
    issuesize   bigint,
    listlevel   smallint,
    sectype     text,
    updated_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT security_lotsize_positive CHECK (lotsize IS NULL OR lotsize > 0),
    CONSTRAINT security_listlevel_range  CHECK (listlevel IS NULL OR listlevel BETWEEN 1 AND 3)
);
COMMENT ON TABLE core.security IS 'Бумаги режима TQBR (T+: акции и ДР)';
COMMENT ON COLUMN core.security.listlevel IS 'Уровень листинга MOEX: 1 — высший, 3 — некотировальная часть';

-- ---------------------------------------------------------------------------
-- Сектора
-- ---------------------------------------------------------------------------
-- Поле SECTORID в API у всех 506 бумаг TQBR равно NULL, поэтому сектор
-- выводится из состава отраслевых индексов MOEX: бумага из MOEXOG относится
-- к нефти и газу.
CREATE TABLE IF NOT EXISTS core.sector (
    sector_id   text PRIMARY KEY,   -- MOEXOG, MOEXFN, ...
    sector_name text NOT NULL
);

INSERT INTO core.sector (sector_id, sector_name) VALUES
    ('MOEXOG', 'Нефть и газ'),
    ('MOEXEU', 'Электроэнергетика'),
    ('MOEXTL', 'Телекоммуникации'),
    ('MOEXMM', 'Металлы и добыча'),
    ('MOEXFN', 'Финансы'),
    ('MOEXCN', 'Потребительский сектор'),
    ('MOEXCH', 'Химия и нефтехимия'),
    ('MOEXTN', 'Транспорт'),
    ('MOEXIT', 'Информационные технологии'),
    ('MOEXRE', 'Строительство'),
    ('OTHER',  'Прочее')
ON CONFLICT (sector_id) DO NOTHING;

-- Первичный ключ на одном secid, а не на паре (secid, sector_id): 45 из 46
-- бумаг индекса входят ровно в один отраслевой индекс. Ключ превращает это
-- наблюдение в гарантию — связь «многие ко многим» дублировала бы бумагу
-- в рейтинге сектора и сдвигала границы квартилей NTILE.
CREATE TABLE IF NOT EXISTS core.security_sector (
    secid      text PRIMARY KEY REFERENCES core.security(secid),
    sector_id  text NOT NULL REFERENCES core.sector(sector_id)
);
CREATE INDEX IF NOT EXISTS security_sector_sector_idx ON core.security_sector (sector_id);

-- ---------------------------------------------------------------------------
-- Котировки акций — главная таблица
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.quote (
    secid       text NOT NULL REFERENCES core.security(secid),
    trade_date  date NOT NULL,

    -- numeric, а не double precision: на 47 тысячах строк накопленная
    -- доходность через произведение расходится уже в третьем знаке.
    open        numeric(18,6) NOT NULL,
    high        numeric(18,6) NOT NULL,
    low         numeric(18,6) NOT NULL,
    close       numeric(18,6) NOT NULL,
    waprice     numeric(18,6),              -- средневзвешенная, может отсутствовать
    volume      bigint        NOT NULL,     -- штуки — целое по природе
    value       numeric(20,4) NOT NULL,     -- рубли — деньги, значит numeric
    numtrades   integer,

    -- Одна бумага в один день торгуется один раз. Вместе с
    -- ON CONFLICT DO NOTHING в ETL ключ даёт идемпотентность загрузки.
    CONSTRAINT quote_pk PRIMARY KEY (secid, trade_date),

    CONSTRAINT quote_price_positive CHECK (open > 0 AND high > 0 AND low > 0 AND close > 0),
    CONSTRAINT quote_high_low       CHECK (high >= low),
    -- Согласованность OHLC. Ловит перепутанные колонки: в ответе API
    -- LOW идёт раньше HIGH.
    CONSTRAINT quote_ohlc_coherent  CHECK (high >= open AND high >= close
                                       AND low  <= open AND low  <= close),
    CONSTRAINT quote_volume_nonneg  CHECK (volume >= 0 AND value >= 0)
);
COMMENT ON TABLE core.quote IS 'Дневные котировки акций TQBR';

-- Индекса на (secid, trade_date) здесь нет: его уже создал первичный ключ.
-- Нужен обратный порядок колонок — составной индекс работает слева направо,
-- и по (secid, trade_date) нельзя отобрать все бумаги за конкретную дату.
-- Именно такие запросы основные: расчёт беты соединяет котировки с историей
-- индекса по дате.
CREATE INDEX IF NOT EXISTS quote_date_secid_idx ON core.quote (trade_date, secid);

-- ---------------------------------------------------------------------------
-- Котировки индексов
-- ---------------------------------------------------------------------------
-- Отдельная таблица, а не общая с акциями: у индекса нет объёма в штуках и
-- числа сделок, зато есть капитализация.
CREATE TABLE IF NOT EXISTS core.index_quote (
    index_id        text NOT NULL,
    trade_date      date NOT NULL,
    open            numeric(18,6),
    high            numeric(18,6),
    low             numeric(18,6),
    close           numeric(18,6) NOT NULL,
    value           numeric(20,4),          -- оборот по корзине индекса
    capitalization  numeric(24,4),

    CONSTRAINT index_quote_pk PRIMARY KEY (index_id, trade_date),
    CONSTRAINT index_quote_close_positive CHECK (close > 0),
    CONSTRAINT index_quote_high_low CHECK (high IS NULL OR low IS NULL OR high >= low)
);
COMMENT ON TABLE core.index_quote IS 'История индексов: IMOEX, MCFTR и отраслевые';
COMMENT ON COLUMN core.index_quote.index_id IS 'IMOEX — ценовой индекс, MCFTR — полной доходности (с реинвестированием дивидендов)';

-- ---------------------------------------------------------------------------
-- Веса бумаг в индексе
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.index_weight (
    index_id     text NOT NULL,
    weight_date  date NOT NULL,
    secid        text NOT NULL REFERENCES core.security(secid),
    weight       numeric(8,4) NOT NULL,

    CONSTRAINT index_weight_pk PRIMARY KEY (index_id, weight_date, secid),
    CONSTRAINT index_weight_range CHECK (weight >= 0 AND weight <= 100)
);
COMMENT ON COLUMN core.index_weight.weight IS 'Вес в процентах; сумма по индексу на дату ≈ 100';

-- ---------------------------------------------------------------------------
-- Торговый календарь
-- ---------------------------------------------------------------------------
-- Представление, а не таблица: даты уже лежат в index_quote, дублировать их
-- значит завести второй источник правды. День считается торговым, если биржа
-- рассчитала по нему индекс МосБиржи.
CREATE OR REPLACE VIEW core.trading_day AS
SELECT trade_date
FROM core.index_quote
WHERE index_id = 'IMOEX';

COMMENT ON VIEW core.trading_day IS 'Эталонный торговый календарь: даты, по которым рассчитан IMOEX';

-- ---------------------------------------------------------------------------
-- Дробления акций (сплиты)
-- ---------------------------------------------------------------------------
-- MOEX отдаёт цены без ретроспективной корректировки. За 2022-2026 пять
-- бумаг индекса прошли дробление; без поправки доходность Норникеля
-- выглядит как -99.4%, а ВТБ — как +105 845%.
--
-- Единственная таблица в core, содержащая вывод из данных, а не факт от
-- биржи: открытый ISS корпоративные действия не отдаёт. Дробления
-- определяются по котировкам — день, когда цена изменилась более чем вдвое.
-- Коэффициент округляется до стандартной пропорции, остаток остаётся
-- в доходности как реальное движение цены.
CREATE TABLE IF NOT EXISTS core.split (
    secid       text NOT NULL REFERENCES core.security(secid),
    split_date  date NOT NULL,          -- первый день торгов в новом масштабе
    ratio       numeric(18,8) NOT NULL, -- сколько новых акций даёт одна старая
    ratio_raw   numeric(18,8) NOT NULL, -- наблюдаемое отношение цен, до округления

    CONSTRAINT split_pk PRIMARY KEY (secid, split_date),
    CONSTRAINT split_ratio_positive CHECK (ratio > 0 AND ratio <> 1),
    -- Если округление уезжает от наблюдения более чем на 20%, это, скорее
    -- всего, не дробление.
    CONSTRAINT split_ratio_close_to_raw CHECK (abs(ln(ratio) - ln(ratio_raw)) < 0.2)
);
COMMENT ON TABLE core.split IS 'Дробления акций, выведенные из котировок: открытый ISS корпоративные действия не отдаёт';
COMMENT ON COLUMN core.split.ratio IS 'Во сколько раз упала цена: 100 — дробление 1:100, 0.0002 — обратное дробление 5000:1';
