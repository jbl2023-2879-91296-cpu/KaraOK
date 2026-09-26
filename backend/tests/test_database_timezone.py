"""Database timestamps must already be UTC before JSON serialization."""

from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import os
import unittest
from unittest.mock import patch

from flask import Flask

from karaok.core import database


class DatabaseTimezoneTests(unittest.TestCase):
    def test_application_connections_request_utc(self):
        with patch.object(database.mysql.connector, "connect") as connect:
            database.get_db()
        self.assertEqual(connect.call_args.kwargs.get("time_zone"), "+00:00")

    def test_admin_connections_request_utc(self):
        with patch.dict(database.ADMIN_DB_CONFIG, user="test", password="test"), patch.object(
            database.mysql.connector, "connect"
        ) as connect:
            database.get_admin_db()
        self.assertEqual(connect.call_args.kwargs.get("time_zone"), "+00:00")


@unittest.skipUnless(os.environ.get("KARAOK_TEST_MYSQL") == "1", "requires local MySQL")
class MySQLTimestampIntegrationTests(unittest.TestCase):
    def test_timestamp_json_round_trip_preserves_manila_time(self):
        connection = database.get_db()
        self.addCleanup(connection.close)
        cursor = connection.cursor()
        self.addCleanup(cursor.close)
        # Temporary data only; the table disappears when this connection closes.
        cursor.execute("CREATE TEMPORARY TABLE timezone_regression (created_at TIMESTAMP)")
        instant = datetime(2026, 9, 26, 13, 40, 38, tzinfo=timezone.utc)
        cursor.execute(
            "INSERT INTO timezone_regression VALUES (FROM_UNIXTIME(%s))",
            (int(instant.timestamp()),),
        )
        cursor.execute("SELECT created_at FROM timezone_regression")
        timestamp = cursor.fetchone()[0]
        payload = Flask(__name__).json.loads(
            Flask(__name__).json.dumps({"created_at": timestamp})
        )
        decoded = parsedate_to_datetime(payload["created_at"])
        self.assertEqual(decoded, instant)
        self.assertEqual(
            decoded.astimezone(timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M"),
            "2026-09-26 21:40",
        )
