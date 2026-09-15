"""Загрузка данных Московской биржи: ISS API -> staging -> core.

Запуск:
    python -m etl.load              обычный прогон (повтор не создаёт дублей)
    python -m etl.load --refresh    подтянуть пересчитанные биржей строки
    python -m etl.load --from 2023-01-01

Модуль только переносит строки. Все расчёты выполняются в SQL.
"""
import argparse
import logging
import sys
import uuid
from datetime import date

import psycopg

from etl import db
from etl.config import LOAD_FROM, INDEX_IDS, SECTOR_INDEX_IDS
from etl.moex_client import MoexClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("etl")


# ---------------------------------------------------------------------------
# запись в staging
# ---------------------------------------------------------------------------
def copy_to_staging(conn, table: str, columns: list[str], rows: list[dict], batch_id: uuid.UUID) -> int:
    """Пишет строки в staging через COPY.

    COPY, а не пачка INSERT: данные идут одним потоком, без разбора каждой
    строки как отдельной команды. Значения приводятся к str — в staging
    колонки текстовые, типизация отложена до перелива в core.
    """
    if not rows:
        return 0
    cols = columns + ["_batch_id", "_source_url"]
    copy_sql = f"COPY {table} ({', '.join(cols)}) FROM STDIN"
    with conn.cursor() as cur, cur.copy(copy_sql) as copy:
        for row in rows:
            values = [row.get(c) for c in columns]
            values = [None if v is None else str(v) for v in values]
            copy.write_row(values + [str(batch_id), row.get("_source_url", "")])
    return len(rows)


def log_start(conn, batch_id: uuid.UUID, entity: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO staging.load_log (batch_id, entity) VALUES (%s, %s)",
            (str(batch_id), entity),
        )


def log_finish(conn, batch_id: uuid.UUID, fetched: int, inserted: int,
               status: str = "ok", error: str | None = None) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """UPDATE staging.load_log
                  SET finished_at = now(), rows_fetched = %s, rows_inserted = %s,
                      status = %s, error_text = %s
                WHERE batch_id = %s""",
            (fetched, inserted, status, error, str(batch_id)),
        )


# ---------------------------------------------------------------------------
# шаги загрузки
# ---------------------------------------------------------------------------
SECURITY_COLS = ["secid", "boardid", "shortname", "secname", "latname", "isin",
                 "regnumber", "lotsize", "facevalue", "faceunit", "issuesize",
                 "listlevel", "sectype", "sectorid", "status", "decimals",
                 "minstep", "prevdate"]

INDEX_QUOTE_COLS = ["boardid", "secid", "tradedate", "shortname", "name", "close",
                    "open", "high", "low", "value", "capitalization", "divisor",
                    "currencyid"]

INDEX_WEIGHT_COLS = ["indexid", "tradedate", "ticker", "shortnames", "secids", "weight"]

QUOTE_COLS = ["boardid", "tradedate", "shortname", "secid", "numtrades", "value",
              "open", "low", "high", "legalcloseprice", "waprice", "close", "volume"]


def load_securities(conn, client: MoexClient, refresh: bool) -> None:
    batch = uuid.uuid4()
    log_start(conn, batch, "security")
    rows = client.securities()
    fetched = copy_to_staging(conn, "staging.security_raw", SECURITY_COLS, rows, batch)
    inserted = db.run_sql_file(conn, "10_security.sql", {"batch_id": batch, "refresh": refresh})
    log_finish(conn, batch, fetched, inserted)
    conn.commit()
    log.info("Справочник: получено %s, в core %s", fetched, inserted)


def load_index_composition(conn, client: MoexClient, refresh: bool) -> list[str]:
    """Грузит состав IMOEX (веса) и отраслевых индексов (сектора).

    Возвращает список бумаг индекса МосБиржи — периметр проекта.
    """
    batch = uuid.uuid4()
    log_start(conn, batch, "index_weight")
    rows: list[dict] = []
    for index_id in ["IMOEX"] + SECTOR_INDEX_IDS:
        part = client.index_composition(index_id)
        log.info("  состав %-7s : %s бумаг", index_id, len(part))
        rows.extend(part)

    fetched = copy_to_staging(conn, "staging.index_weight_raw", INDEX_WEIGHT_COLS, rows, batch)
    db.run_sql_file(conn, "11_check_one_sector.sql", {"batch_id": batch, "refresh": refresh})
    db.run_sql_file(conn, "12_security_sector.sql", {"batch_id": batch, "refresh": refresh})
    inserted = db.run_sql_file(conn, "14_index_weight.sql", {"batch_id": batch, "refresh": refresh})
    log_finish(conn, batch, fetched, inserted)
    conn.commit()

    with conn.cursor() as cur:
        cur.execute("""SELECT secid FROM core.index_weight
                        WHERE index_id = 'IMOEX'
                          AND weight_date = (SELECT max(weight_date) FROM core.index_weight
                                              WHERE index_id = 'IMOEX')
                        ORDER BY secid""")
        secids = [r[0] for r in cur.fetchall()]
    log.info("Состав индекса: %s бумаг в core", len(secids))
    return secids


def load_index_history(conn, client: MoexClient, date_from: str, date_till: str, refresh: bool) -> None:
    batch = uuid.uuid4()
    log_start(conn, batch, "index_quote")
    rows: list[dict] = []
    for index_id in INDEX_IDS:
        part = client.index_history(index_id, date_from, date_till)
        log.info("  история %-7s : %s дней", index_id, len(part))
        rows.extend(part)
    fetched = copy_to_staging(conn, "staging.index_quote_raw", INDEX_QUOTE_COLS, rows, batch)
    inserted = db.run_sql_file(conn, "13_index_quote.sql", {"batch_id": batch, "refresh": refresh})
    log_finish(conn, batch, fetched, inserted)
    conn.commit()
    log.info("Индексы: получено %s, в core %s", fetched, inserted)


def load_quotes(conn, client: MoexClient, secids: list[str],
                date_from: str, date_till: str, refresh: bool) -> None:
    batch = uuid.uuid4()
    log_start(conn, batch, "quote")
    total_fetched = 0
    rows: list[dict] = []
    for i, secid in enumerate(secids, 1):
        part = client.quote_history(secid, date_from, date_till)
        rows.extend(part)
        total_fetched += len(part)
        log.info("  [%2d/%d] %-6s %4s дней", i, len(secids), secid, len(part))

    fetched = copy_to_staging(conn, "staging.quote_raw", QUOTE_COLS, rows, batch)
    inserted = db.run_sql_file(conn, "15_quote.sql", {"batch_id": batch, "refresh": refresh})
    log_finish(conn, batch, fetched, inserted)
    conn.commit()
    # Дробления ищем после загрузки котировок: расчёт идёт по core.quote.
    splits = db.run_sql_file(conn, "16_detect_splits.sql", {"batch_id": batch, "refresh": refresh})
    conn.commit()

    log.info("Котировки: получено %s, записано в core %s", fetched, inserted)
    if splits:
        log.warning("Найдено дроблений акций: %s — цены в витринах будут скорректированы", splits)
    if refresh is False and inserted < fetched:
        log.info("  (разница — либо дни без торгов, либо строки, уже лежащие в core)")


# ---------------------------------------------------------------------------
def refresh_marts(conn) -> None:
    """Пересобрать материализованные представления.

    Обязательный шаг в конце загрузки: без REFRESH витрины остаются
    замороженным снимком предыдущего прогона.
    """
    with conn.cursor() as cur:
        cur.execute("SELECT marts.refresh_all()")
    conn.commit()
    log.info("Витрины пересобраны")


def main() -> int:
    parser = argparse.ArgumentParser(description="Загрузка данных MOEX ISS в PostgreSQL")
    parser.add_argument("--from", dest="date_from", default=LOAD_FROM,
                        help=f"начало периода, по умолчанию {LOAD_FROM}")
    parser.add_argument("--till", dest="date_till", default=date.today().isoformat())
    parser.add_argument("--refresh", action="store_true",
                        help="обновлять уже загруженные строки (биржа пересчитывает итоги задним числом)")
    args = parser.parse_args()

    log.info("Период: %s .. %s | режим: %s",
             args.date_from, args.date_till,
             "refresh (DO UPDATE)" if args.refresh else "обычный (DO NOTHING)")

    client = MoexClient()
    try:
        with db.connect() as conn:
            load_securities(conn, client, args.refresh)
            secids = load_index_composition(conn, client, args.refresh)
            load_index_history(conn, client, args.date_from, args.date_till, args.refresh)
            load_quotes(conn, client, secids, args.date_from, args.date_till, args.refresh)
            refresh_marts(conn)
    except psycopg.Error as err:
        log.error("Ошибка базы: %s", err)
        return 1
    except RuntimeError as err:
        log.error("%s", err)
        return 1

    log.info("Готово. Запросов к ISS: %s", client.request_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
