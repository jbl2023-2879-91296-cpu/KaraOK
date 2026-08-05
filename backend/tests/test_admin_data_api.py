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


api.app.config["TESTING"] = True


class AdminDataApiTests(unittest.TestCase):
    def setUp(self):
        self.client = api.app.test_client()
        self.headers = {"Authorization": f"Bearer {API_KEY}"}

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

    def test_create_route_audits_success(self):
        with patch.object(service, "create_record", return_value={"id": 4}), patch.object(
            api, "audit"
        ) as audit:
            response = self.client.post(
                "/api/admin/data/tables/genre_preset/records",
                headers=self.headers,
                json={"genre_name": "Jazz"},
            )
        self.assertEqual(response.status_code, 201)
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
