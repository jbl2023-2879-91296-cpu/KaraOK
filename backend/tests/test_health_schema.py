"""Deployment readiness without a live database or environment credentials."""

from unittest.mock import Mock, patch

import pytest
from flask import Flask
from mysql.connector import Error

from karaok.modules.system.routes import blueprint
from karaok.system import health


@pytest.fixture
def health_client():
    app = Flask(__name__)
    app.register_blueprint(blueprint)
    return app.test_client()


def test_health_checks_required_column_in_active_database(health_client):
    connection = Mock()
    cursor = connection.cursor.return_value
    cursor.fetchone.side_effect = [(1,), (1,), (1,)]
    with patch.object(health, "get_db", return_value=connection):
        response = health_client.get("/api/health")
    assert response.status_code == 200
    assert response.json == {"status": "ok", "db": "connected"}
    column_calls = cursor.execute.call_args_list[1:]
    assert [call.args[1] for call in column_calls] == [
        ("settings_recommendation", "feedback"),
        ("audio_analysis_result", "noise_reliable"),
    ]
    assert all("table_schema = DATABASE()" in call.args[0] for call in column_calls)
    cursor.close.assert_called_once()
    connection.close.assert_called_once()


@pytest.mark.parametrize("missing", [
    "settings_recommendation.feedback", "audio_analysis_result.noise_reliable",
])
def test_missing_column_marks_health_unready_and_logs_fix(health_client, caplog, missing):
    connection = Mock()
    connection.cursor.return_value.fetchone.side_effect = [
        (1,),
        None if missing.startswith("settings_recommendation.") else (1,),
        None if missing.startswith("audio_analysis_result.") else (1,),
    ]
    with patch.object(health, "get_db", return_value=connection):
        response = health_client.get("/api/health")
    assert response.status_code == 503
    assert response.json["schema"] == "missing_required_columns"
    assert missing in caplog.text
    assert "Run the database migrations before deploying the backend" in caplog.text
    connection.cursor.return_value.close.assert_called_once()
    connection.close.assert_called_once()


@pytest.mark.parametrize("failure", ["connect", "cursor", "query", "schema"])
def test_database_errors_fail_health_and_release_open_resources(health_client, failure):
    connection = Mock()
    cursor = connection.cursor.return_value
    with patch.object(health, "get_db", return_value=connection) as connect:
        if failure == "connect":
            connect.side_effect = Error("unavailable")
        elif failure == "cursor":
            connection.cursor.side_effect = Error("unavailable")
        elif failure == "query":
            cursor.execute.side_effect = Error("unavailable")
        else:
            cursor.execute.side_effect = [None, Error("metadata unavailable")]
        response = health_client.get("/api/health")
    assert response.status_code == 503
    assert response.json == {"status": "error", "db": "unavailable"}
    assert connection.close.call_count == (failure != "connect")
    assert cursor.close.call_count == (failure in {"query", "schema"})


def test_health_recovers_after_migration(health_client):
    connection = Mock()
    connection.cursor.return_value.fetchone.side_effect = [
        (1,), None, None, (1,), (1,), (1,),
    ]
    with patch.object(health, "get_db", return_value=connection):
        assert health_client.get("/api/health").status_code == 503
        assert health_client.get("/api/health").status_code == 200
