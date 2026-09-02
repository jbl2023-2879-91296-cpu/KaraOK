import json
import os
import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch


os.environ.setdefault(
    "JWT_SECRET",
    "test-only-secret-that-is-at-least-32-characters",
)

import app as api


api.app.config["TESTING"] = True


def account_row():
    return {
        "role": "user",
        "is_active": True,
        "email_verified_at": datetime.now(timezone.utc),
        "security_updated_at_epoch": None,
        "requires_password_change": False,
    }


def profile_row(**overrides):
    row = {
        "amplifier_profile_id": 12,
        "user_id": 7,
        "name": "My Amplifier",
        "scale_min": 0.0,
        "scale_max": 10.0,
        "scale_step": 0.5,
        "last_positions": json.dumps(
            {
                "volume": 5.0,
                "bass": 4.0,
                "treble": 6.0,
                "sharpness": 5.0,
                "flatness": 5.0,
            }
        ),
        "created_at": datetime(2026, 9, 2, tzinfo=timezone.utc),
        "updated_at": datetime(2026, 9, 2, tzinfo=timezone.utc),
    }
    row.update(overrides)
    return row


def recommendation_row(**overrides):
    row = {
        "recommendation_id": 41,
        "user_id": 7,
        "assessment_id": 31,
        "amplifier_profile_id": 12,
        "parent_recommendation_id": None,
        "genre": "rock",
        "current_positions": json.dumps(
            {
                "volume": 5.0,
                "bass": 4.0,
                "treble": 6.0,
                "sharpness": 5.0,
                "flatness": 5.0,
            }
        ),
        "recommended_positions": json.dumps(
            {
                "volume": 5.5,
                "bass": 5.5,
                "treble": 5.5,
                "sharpness": 5.0,
                "flatness": 4.5,
            }
        ),
        "adjustments": json.dumps(
            {
                "volume": {"delta": 0.5, "reason_code": "below_genre_range"},
                "bass": {"delta": 1.5, "reason_code": "below_genre_range"},
                "treble": {"delta": -0.5, "reason_code": "above_genre_range"},
                "sharpness": {"delta": 0.0, "reason_code": "within_genre_range"},
                "flatness": {"delta": -0.5, "reason_code": "above_genre_range"},
            }
        ),
        "original_score": 72.4,
        "verification_score": None,
        "overall_confidence": "medium",
        "algorithm_version": "1.0.0",
        "genre_profile_version": "2026.09.1",
        "recommendation_status": "generated",
        "created_at": datetime(2026, 9, 2, tzinfo=timezone.utc),
        "applied_at": None,
        "scale_min": 0.0,
        "scale_max": 10.0,
        "scale_step": 0.5,
    }
    row.update(overrides)
    return row


class SettingsRecommendationApiTests(unittest.TestCase):
    def setUp(self):
        self.client = api.app.test_client()
        self.token, _ = api.issue_access_token(
            {"user_id": 7, "user_type": "user"}
        )
        self.headers = {"Authorization": f"Bearer {self.token}"}

    def request_with_database(
        self,
        method,
        path,
        *,
        fetchone=(),
        fetchall=None,
        lastrowid=None,
        rowcount=1,
        json_body=None,
    ):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.side_effect = [None, account_row(), *fetchone]
        cursor.fetchall.return_value = fetchall or []
        cursor.lastrowid = lastrowid
        cursor.rowcount = rowcount
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "audit"
        ), patch.object(
            api, "SETTINGS_RECOMMENDATIONS_ENABLED", True, create=True
        ):
            response = self.client.open(
                path,
                method=method,
                headers=self.headers,
                json=json_body,
            )
        return response, connection, cursor

    def test_profile_routes_require_user_auth(self):
        with patch.object(api, "audit"), patch.object(
            api, "SETTINGS_RECOMMENDATIONS_ENABLED", True, create=True
        ):
            response = self.client.get("/api/amplifier-profiles")
        self.assertEqual(response.status_code, 401)

    def test_settings_routes_are_hidden_before_auth_while_feature_is_disabled(self):
        with patch.object(api, "audit") as audit, patch.object(
            api, "SETTINGS_RECOMMENDATIONS_ENABLED", False, create=True
        ):
            responses = (
                self.client.get("/api/settings-profile-metadata"),
                self.client.get("/api/amplifier-profiles"),
                self.client.post("/api/amplifier-profiles", json={}),
                self.client.get("/api/amplifier-profiles/12"),
                self.client.patch("/api/amplifier-profiles/12", json={}),
                self.client.delete("/api/amplifier-profiles/12"),
                self.client.get("/api/settings-recommendations/41"),
                self.client.post("/api/settings-recommendations/41/apply"),
            )

        self.assertTrue(all(response.status_code == 404 for response in responses))
        audit.assert_not_called()

    def test_public_metadata_returns_only_enabled_genres_and_version(self):
        with patch.object(
            api, "SETTINGS_RECOMMENDATIONS_ENABLED", True, create=True
        ):
            response = self.client.get("/api/settings-profile-metadata")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(set(response.get_json()), {"profile_version", "enabled_genres"})
        self.assertEqual(
            response.get_json()["enabled_genres"],
            ["hip-hop", "pop", "rock"],
        )

    def test_lists_only_the_authenticated_users_profiles(self):
        response, connection, cursor = self.request_with_database(
            "GET",
            "/api/amplifier-profiles",
            fetchall=[profile_row()],
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()[0]["id"], 12)
        self.assertEqual(response.get_json()[0]["last_positions"]["bass"], 4.0)
        profile_query = next(
            call
            for call in cursor.execute.call_args_list
            if "FROM amplifier_profile" in call.args[0]
        )
        self.assertIn("WHERE user_id = %s", profile_query.args[0])
        self.assertEqual(profile_query.args[1], (7,))
        connection.commit.assert_not_called()

    def test_get_profile_is_owner_scoped(self):
        response, connection, cursor = self.request_with_database(
            "GET",
            "/api/amplifier-profiles/12",
            fetchone=[profile_row()],
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["id"], 12)
        owner_query = next(
            call
            for call in cursor.execute.call_args_list
            if "FROM amplifier_profile" in call.args[0]
        )
        self.assertIn("amplifier_profile_id = %s AND user_id = %s", owner_query.args[0])
        self.assertEqual(owner_query.args[1], (12, 7))
        connection.commit.assert_not_called()

    def test_create_profile_validates_strict_payload_and_five_positions(self):
        invalid_payloads = (
            {
                "name": "Amp",
                "scale_min": 0,
                "scale_max": 10,
                "scale_step": 0.5,
                "unexpected": True,
            },
            {
                "name": "Amp",
                "scale_min": 0,
                "scale_max": 10,
                "scale_step": 11,
            },
            {
                "name": "Amp",
                "scale_min": 0,
                "scale_max": 10,
                "scale_step": 0.5,
                "last_positions": {"volume": 5},
            },
            {
                "name": "Amp",
                "scale_min": 0,
                "scale_max": 10,
                "scale_step": 0.5,
                "last_positions": {
                    "volume": 5,
                    "bass": 4,
                    "treble": 6,
                    "sharpness": 5,
                    "flatness": 11,
                },
            },
        )
        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                response, connection, _ = self.request_with_database(
                    "POST",
                    "/api/amplifier-profiles",
                    json_body=payload,
                )
                self.assertEqual(response.status_code, 400)
                connection.commit.assert_not_called()

    def test_create_profile_trims_name_and_commits_owned_row(self):
        created = profile_row(name="Stage Amp")
        response, connection, cursor = self.request_with_database(
            "POST",
            "/api/amplifier-profiles",
            fetchone=[created],
            lastrowid=12,
            json_body={
                "name": "  Stage   Amp  ",
                "scale_min": 0,
                "scale_max": 10,
                "scale_step": 0.5,
                "last_positions": None,
            },
        )
        self.assertEqual(response.status_code, 201)
        insert = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO amplifier_profile" in call.args[0]
        )
        self.assertEqual(insert.args[1][0:2], (7, "Stage Amp"))
        connection.commit.assert_called_once()

    def test_profile_update_is_owner_scoped(self):
        response, connection, cursor = self.request_with_database(
            "PATCH",
            "/api/amplifier-profiles/99",
            fetchone=[None],
            json_body={"name": "Stage Amp"},
        )

        self.assertEqual(response.status_code, 404)
        owner_query = next(
            call
            for call in cursor.execute.call_args_list
            if "FROM amplifier_profile" in call.args[0]
        )
        self.assertIn("user_id = %s", owner_query.args[0])
        self.assertIn(7, owner_query.args[1])
        connection.rollback.assert_called_once()

    def test_profile_update_validates_merged_scale_and_commits_partial_change(self):
        current = profile_row()
        updated = profile_row(name="Stage Amp")
        response, connection, cursor = self.request_with_database(
            "PATCH",
            "/api/amplifier-profiles/12",
            fetchone=[current, updated],
            json_body={"name": "  Stage   Amp  "},
        )

        self.assertEqual(response.status_code, 200)
        update = next(
            call
            for call in cursor.execute.call_args_list
            if "UPDATE amplifier_profile SET" in call.args[0]
        )
        self.assertIn("WHERE amplifier_profile_id = %s AND user_id = %s", update.args[0])
        self.assertEqual(update.args[1], ("Stage Amp", 12, 7))
        connection.commit.assert_called_once()
        connection.rollback.assert_not_called()

    def test_profile_update_rejects_scale_that_invalidates_saved_positions(self):
        response, connection, _ = self.request_with_database(
            "PATCH",
            "/api/amplifier-profiles/12",
            fetchone=[profile_row()],
            json_body={"scale_max": 5.0},
        )

        self.assertEqual(response.status_code, 400)
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()

    def test_profile_delete_is_owner_scoped(self):
        response, connection, cursor = self.request_with_database(
            "DELETE",
            "/api/amplifier-profiles/99",
            rowcount=0,
        )

        self.assertEqual(response.status_code, 404)
        delete = next(
            call
            for call in cursor.execute.call_args_list
            if "DELETE FROM amplifier_profile" in call.args[0]
        )
        self.assertIn("user_id = %s", delete.args[0])
        self.assertEqual(delete.args[1], (99, 7))
        connection.rollback.assert_called_once()

    def test_get_recommendation_is_owner_scoped_and_decodes_json(self):
        response, _, cursor = self.request_with_database(
            "GET",
            "/api/settings-recommendations/41",
            fetchone=[recommendation_row()],
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["recommended"]["bass"], 5.5)
        query = next(
            call
            for call in cursor.execute.call_args_list
            if "FROM settings_recommendation" in call.args[0]
        )
        self.assertIn("user_id = %s", query.args[0])
        self.assertEqual(query.args[1], (41, 7, 7))

    def test_apply_updates_profile_positions_atomically(self):
        response, connection, cursor = self.request_with_database(
            "POST",
            "/api/settings-recommendations/41/apply",
            fetchone=[recommendation_row()],
            rowcount=1,
        )

        self.assertEqual(response.status_code, 200)
        statements = "\n".join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn("FOR UPDATE", statements)
        self.assertIn("UPDATE amplifier_profile", statements)
        self.assertIn("recommendation_status = 'applied'", statements)
        self.assertIn(7, cursor.execute.call_args_list[-1].args[1])
        connection.commit.assert_called_once()
        connection.rollback.assert_not_called()
        self.assertEqual(response.get_json()["status"], "applied")

    def test_apply_rejects_non_generated_recommendation_without_partial_commit(self):
        response, connection, _ = self.request_with_database(
            "POST",
            "/api/settings-recommendations/41/apply",
            fetchone=[recommendation_row(recommendation_status="applied")],
        )

        self.assertEqual(response.status_code, 409)
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()

    def test_apply_rolls_back_profile_update_when_status_update_loses_race(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.side_effect = [None, account_row(), recommendation_row()]

        def execute(statement, parameters=None):
            cursor.rowcount = (
                0 if "UPDATE settings_recommendation" in statement else 1
            )

        cursor.execute.side_effect = execute
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "audit"
        ), patch.object(api, "SETTINGS_RECOMMENDATIONS_ENABLED", True, create=True):
            response = self.client.post(
                "/api/settings-recommendations/41/apply",
                headers=self.headers,
            )

        self.assertEqual(response.status_code, 409)
        statements = "\n".join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn("UPDATE amplifier_profile", statements)
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()

    def test_environment_examples_keep_feature_disabled_by_default(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        repository = os.path.dirname(root)
        paths = (
            os.path.join(root, ".env.example"),
            os.path.join(repository, "deploy", "ovh", "backend.env.example"),
        )
        for path in paths:
            with self.subTest(path=path):
                with open(path, encoding="utf-8") as environment_file:
                    self.assertIn(
                        "SETTINGS_RECOMMENDATIONS_ENABLED=false",
                        environment_file.read(),
                    )


if __name__ == "__main__":
    unittest.main()
