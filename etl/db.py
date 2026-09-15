"""Подключение к базе и выполнение SQL-файлов перелива."""
import re
from pathlib import Path

import psycopg

from etl.config import DB

SQL_DIR = Path(__file__).resolve().parent.parent / "sql" / "etl"


def connect() -> psycopg.Connection:
    return psycopg.connect(**DB)


def split_statements(sql: str) -> list[str]:
    """Разбивает файл на отдельные SQL-операторы по точке с запятой.

    psycopg с параметрами использует расширенный протокол, где за вызов
    разрешена одна команда. Наивный split(';') не подходит: точка с запятой
    встречается внутри строковых литералов, комментариев и тела DO $$ ... $$,
    поэтому они пропускаются при разборе.
    """
    out, buf, i, n = [], [], 0, len(sql)
    while i < n:
        ch = sql[i]
        if ch == "'" or ch == '"':
            quote = ch
            buf.append(ch); i += 1
            while i < n:
                buf.append(sql[i])
                if sql[i] == quote:
                    if i + 1 < n and sql[i + 1] == quote:   # удвоенная кавычка внутри литерала
                        buf.append(sql[i + 1]); i += 2; continue
                    i += 1; break
                i += 1
            continue
        if sql.startswith("--", i):
            end = sql.find("\n", i)
            end = n if end == -1 else end
            buf.append(sql[i:end]); i = end; continue
        if sql.startswith("/*", i):
            end = sql.find("*/", i)
            end = n if end == -1 else end + 2
            buf.append(sql[i:end]); i = end; continue
        m = re.match(r"\$[A-Za-z_]*\$", sql[i:])
        if m:
            tag = m.group(0)
            end = sql.find(tag, i + len(tag))
            end = n if end == -1 else end + len(tag)
            buf.append(sql[i:end]); i = end; continue
        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []; i += 1; continue
        buf.append(ch); i += 1

    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def run_sql_file(conn: psycopg.Connection, filename: str, params: dict) -> int:
    """Выполняет файл из sql/etl, возвращает число затронутых строк.

    batch_id дополнительно кладётся в настройку сессии etl.batch_id: её
    читает PL/pgSQL-блок проверки секторов, куда параметры psycopg подставить
    нельзя.
    """
    sql = (SQL_DIR / filename).read_text(encoding="utf-8")
    affected = 0
    with conn.cursor() as cur:
        cur.execute("SELECT set_config('etl.batch_id', %s, false)", (str(params["batch_id"]),))
        for stmt in split_statements(sql):
            # Параметры подставляются только операторам, где они есть:
            # DO-блок читает batch_id из настройки сессии.
            if "%(" in stmt:
                cur.execute(stmt, params)
            else:
                cur.execute(stmt)
            if cur.rowcount and cur.rowcount > 0:
                affected += cur.rowcount
    return affected
