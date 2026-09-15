"""Проверки качества данных.

Каждая проверка — отдельный SQL-файл в sql/checks/. Модуль читает файл,
выполняет и печатает результат; все вычисления делает база.

Запуск:  python -m etl.quality_checks
"""
import sys
from pathlib import Path

from etl import db

CHECKS_DIR = Path(__file__).resolve().parent.parent / "sql" / "checks"

TITLES = {
    "01_duplicates.sql":  "Дубли (одна бумага — один день) внутри батча",
    "02_negative.sql":    "Отрицательные и нулевые значения",
    "03_missing_days.sql": "Пропуски торговых дней относительно календаря индекса",
    "04_price_jumps.sql": "Скачки цены больше 30% за день",
    "05_recalc.sql":      "Биржа пересчитала уже загруженные строки",
}


def print_table(headers: list[str], rows: list[tuple]) -> None:
    if not rows:
        print("    — ничего не найдено")
        return
    widths = [max(len(str(h)), *(len(str(r[i])) for r in rows)) for i, h in enumerate(headers)]
    print("    " + " | ".join(str(h).ljust(w) for h, w in zip(headers, widths)))
    print("    " + "-+-".join("-" * w for w in widths))
    for r in rows:
        print("    " + " | ".join(str(v).ljust(w) for v, w in zip(r, widths)))


def main() -> int:
    with db.connect() as conn, conn.cursor() as cur:
        for path in sorted(CHECKS_DIR.glob("*.sql")):
            title = TITLES.get(path.name, path.name)
            print(f"\n=== {title} ===")
            cur.execute(path.read_text(encoding="utf-8"))
            headers = [d.name for d in cur.description]
            print_table(headers, cur.fetchall())
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
