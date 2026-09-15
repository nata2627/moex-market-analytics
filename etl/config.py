"""Настройки ETL. Значения берутся из .env, дефолты совпадают с docker-compose."""
import os
from dotenv import load_dotenv

load_dotenv()

DB = {
    "host": os.getenv("POSTGRES_HOST", "localhost"),
    "port": int(os.getenv("POSTGRES_PORT", "5432")),
    "dbname": os.getenv("POSTGRES_DB", "moex"),
    "user": os.getenv("POSTGRES_USER", "moex"),
    "password": os.getenv("POSTGRES_PASSWORD", "moex"),
}

LOAD_FROM = os.getenv("LOAD_FROM", "2022-01-01")

ISS_BASE = "https://iss.moex.com/iss"

# Пауза между запросами к открытому API.
REQUEST_PAUSE_SEC = 0.25

# IMOEX — ценовой индекс (без дивидендов), MCFTR — полной доходности
# (дивиденды реинвестируются). Их расхождение даёт вклад дивидендов.
INDEX_IDS = ["IMOEX", "MCFTR"]

# Отраслевые индексы — источник секторов: поле SECTORID в справочнике
# у всех бумаг TQBR равно NULL.
SECTOR_INDEX_IDS = [
    "MOEXOG", "MOEXEU", "MOEXTL", "MOEXMM", "MOEXFN",
    "MOEXCN", "MOEXCH", "MOEXTN", "MOEXIT", "MOEXRE",
]

BOARD = "TQBR"   # Т+: акции и ДР — основной режим торгов акциями
