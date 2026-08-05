"""MySQL connection adapter."""

import mysql.connector

from ..config import ADMIN_DB_CONFIG, ADMIN_DATA_API_QUERY_TIMEOUT_MS, DB_CONFIG


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def get_admin_db():
    """Connect with the independently managed data-administration identity."""
    if not ADMIN_DB_CONFIG["user"] or not ADMIN_DB_CONFIG["password"]:
        raise RuntimeError("Data Administration API database credentials are not configured")
    connection = mysql.connector.connect(**ADMIN_DB_CONFIG)
    cursor = connection.cursor()
    try:
        timeout = max(500, min(30_000, ADMIN_DATA_API_QUERY_TIMEOUT_MS))
        cursor.execute(f"SET SESSION MAX_EXECUTION_TIME = {timeout}")
    finally:
        cursor.close()
    return connection
