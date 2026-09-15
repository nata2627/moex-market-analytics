"""Клиент к ISS API Московской биржи.

Задача модуля — донести строки из API до таблиц staging. Агрегации и расчёты
здесь отсутствуют: они выполняются в SQL.
"""
import time
import logging
from typing import Iterator

import requests

from etl.config import ISS_BASE, REQUEST_PAUSE_SEC, BOARD

log = logging.getLogger(__name__)

# Предохранитель от бесконечного цикла, если ISS вдруг начнёт игнорировать
# параметр start и отдавать одну и ту же страницу.
MAX_PAGES = 200


class MoexClient:
    def __init__(self, pause: float = REQUEST_PAUSE_SEC):
        self.pause = pause
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "moex-sql-portfolio/1.0"
        self.request_count = 0

    # ------------------------------------------------------------------
    # низкий уровень
    # ------------------------------------------------------------------
    def _get(self, path: str, params: dict | None = None) -> tuple[dict, str]:
        """Один GET. Возвращает (json, итоговый url); url пишется в staging."""
        params = dict(params or {})
        params["iss.meta"] = "off"     # метаданные о типах нам не нужны, экономим трафик

        url = f"{ISS_BASE}/{path.lstrip('/')}"
        last_err = None
        for attempt in range(3):
            try:
                resp = self.session.get(url, params=params, timeout=30)
                resp.raise_for_status()
                self.request_count += 1
                time.sleep(self.pause)
                return resp.json(), resp.url
            except (requests.RequestException, ValueError) as err:
                last_err = err
                wait = 2 ** attempt
                log.warning("Запрос %s не удался (%s), повтор через %sс", url, err, wait)
                time.sleep(wait)
        raise RuntimeError(f"ISS не ответил после 3 попыток: {url}") from last_err

    @staticmethod
    def _rows(payload: dict, block: str) -> list[dict]:
        """Блок ISS {"columns": [...], "data": [...]} -> список словарей.

        Маппинг по именам из columns, а не по позициям: в ответе /history
        LOW идёт раньше HIGH, и разбор по индексам перепутал бы максимум
        с минимумом.
        """
        data = payload.get(block, {})
        columns = [c.lower() for c in data.get("columns", [])]
        return [dict(zip(columns, row)) for row in data.get("data", [])]

    def _paginate(self, path: str, block: str, params: dict | None = None) -> Iterator[dict]:
        """Постраничный обход.

        Размер страницы у ресурсов разный (100 у истории торгов, 20 у состава
        индекса), поэтому шаг берётся из самого ответа. Если блока cursor нет,
        ресурс отдаёт всё разом: слепо увеличивать start нельзя, ISS вернёт
        ту же страницу и получится вечный цикл.
        """
        params = dict(params or {})
        start = 0
        for _ in range(MAX_PAGES):
            params["start"] = start
            payload, url = self._get(path, params)
            rows = self._rows(payload, block)
            if not rows:
                return
            for row in rows:
                row["_source_url"] = url
                yield row

            if f"{block}.cursor" not in payload:
                return                       # ресурс без пагинации
            start += len(rows)
        log.warning("Достигнут предел в %s страниц для %s", MAX_PAGES, path)

    # ------------------------------------------------------------------
    # ресурсы
    # ------------------------------------------------------------------
    def securities(self) -> list[dict]:
        """Справочник бумаг режима TQBR (~506 штук, отдаётся одной страницей)."""
        return list(self._paginate(
            f"/engines/stock/markets/shares/boards/{BOARD}/securities.json",
            "securities",
        ))

    def index_composition(self, index_id: str) -> list[dict]:
        """Состав индекса с весами на последнюю доступную дату."""
        return list(self._paginate(
            f"/statistics/engines/stock/markets/index/analytics/{index_id}.json",
            "analytics",
        ))

    def index_history(self, index_id: str, date_from: str, date_till: str) -> list[dict]:
        """Дневная история значений индекса."""
        return list(self._paginate(
            f"/history/engines/stock/markets/index/securities/{index_id}.json",
            "history",
            {"from": date_from, "till": date_till},
        ))

    def quote_history(self, secid: str, date_from: str, date_till: str) -> list[dict]:
        """Дневные котировки акции на TQBR."""
        return list(self._paginate(
            f"/history/engines/stock/markets/shares/boards/{BOARD}/securities/{secid}.json",
            "history",
            {"from": date_from, "till": date_till},
        ))
