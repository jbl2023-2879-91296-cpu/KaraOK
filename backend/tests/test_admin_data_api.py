import hashlib
import os
import unittest
from unittest.mock import MagicMock, patch


API_KEY = "test-admin-data-key-with-enough-entropy"
os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")
os.environ["ADMIN_DATA_API_ENABLED"] = "true"
os.environ["ADMIN_DATA_API_KEY_HASH"] = hashlib.sha256(API_KEY.encode()).hexdigest()
os.environ.setdefault("ADMIN_DB_USER", "test_admin")
os.environ.setdefault("ADMIN_DB_PASSWORD", "test_password")

import app as api
from karaok.modules.admin_data import service
from karaok.security import admin_data_auth


api.app.config["TESTING"] = True


class AdminDataApiTests(unittest.TestCase):
    def setUp(self):
        self.client = api.app.test_client()
        self.headers = {"Authorization": f"Bearer {API_KEY}"}
        enabled = patch.object(admin_data_auth, "ADMIN_DATA_API_ENABLED", True)
        key_hash = patch.object(
            admin_data_auth,
            "ADMIN_DATA_API_KEY_HASH",
            hashlib.sha256(API_KEY.encode()).hexdigest(),
        )
        enabled.start()
        key_hash.start()
        self.addCleanup(enabled.stop)
        self.addCleanup(key_hash.stop)

    def test_admin_data_requires_its_machine_key(self):
        response = self.client.get("/api/admin/data/health")
        self.assertEqual(response.status_code, 401)

    def test_admin_data_rejects_wrong_machine_key(self):
        response = self.client.get(
            "/api/admin/data/health", headers={"Authorization": "Bearer wrong"}
        )
        self.assertEqual(response.status_code, 401)

    def test_health_accepts_valid_machine_key(self):
        with patch.object(service, "health", return_value={"status": "ok"}):
            response = self.client.get("/api/admin/data/health", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ok")

    def test_security_tables_do_not_expose_records(self):
        with self.assertRaises(PermissionError):
            service.records("refresh_token", {})

    def test_unknown_table_is_rejected_before_database_access(self):
        with self.assertRaises(ValueError):
            service.records("user; DROP TABLE user", {})

    def test_delete_requires_exact_confirmation(self):
        with self.assertRaises(ValueError):
            service.delete_record("assessment", "7", "yes")

    def test_user_policy_only_allows_account_activation_update(self):
        policy = service.table_policy("user")
        self.assertEqual(policy.update_fields, ("is_active",))
        self.assertFalse(policy.deletable)
        self.assertIn("password", policy.hidden_fields)

    def test_retired_reference_tables_are_not_advertised(self):
        for table in (
            "genre_preset",
            "audio_quality_threshold",
            "user_genre_setting",
        ):
            with self.subTest(table=table):
                with self.assertRaises(ValueError):
                    service.table_policy(table)

    def test_new_settings_tables_are_read_only_in_admin_api(self):
        for table in ("amplifier_profile", "settings_recommendation"):
            with self.subTest(table=table):
                policy = service.table_policy(table)
                self.assertTrue(policy.readable)
                self.assertFalse(policy.creatable)
                self.assertFalse(policy.updatable)
                self.assertFalse(policy.deletable)

    def test_numeric_admin_values_are_bounded(self):
        column = {
            "name": "bass",
            "nullable": "NO",
            "data_type": "float",
            "column_type": "float",
            "max_length": None,
        }
        with self.assertRaises(ValueError):
            service._validated_value(101, column)
        self.assertEqual(service._validated_value(55, column), 55.0)

    def test_retired_create_route_audits_rejection(self):
        with patch.object(api, "audit") as audit:
            response = self.client.post(
                "/api/admin/data/tables/audio_quality_threshold/records",
                headers=self.headers,
                json={"threshold_name": "Studio"},
            )
        self.assertEqual(response.status_code, 400)
        audit.assert_called_once()

    def test_assessment_delete_cleans_owned_audio_artifacts(self):
        with patch.object(
            service,
            "delete_record",
            return_value={"id": "9", "owner_user_id": 3, "message": "Record deleted"},
        ), patch.object(api, "cleanup_audio_artifacts") as cleanup, patch.object(
            api, "audit"
        ):
            response = self.client.delete(
                "/api/admin/data/tables/assessment/records/9",
                headers=self.headers,
                json={"confirmation": "DELETE assessment:9"},
            )
        self.assertEqual(response.status_code, 200)
        cleanup.assert_called_once_with(3, 9)


if __name__ == "__main__":
    unittest.main()
