import os
from pathlib import Path
import time
import unittest
from unittest.mock import patch

from flask import g

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api

api.app.config["TESTING"] = True


class SecurityValidationTests(unittest.TestCase):
    def test_api_request_log_stores_sanitized_metadata(self):
        connection = unittest.mock.MagicMock()
        cursor = connection.cursor.return_value
        with api.app.test_request_context(
            "/api/audio-uploads?token=must-not-be-stored",
            method="POST",
            headers={"User-Agent": "KaraOK test"},
        ), patch.object(api, "get_db", return_value=connection):
            g.api_request_started = time.monotonic()
            g.authenticated_user_id = 7
            response = api.app.response_class(status=201)
            returned = api.complete_api_request_log(response)

        self.assertEqual(returned.status_code, 201)
        parameters = cursor.execute.call_args.args[1]
        self.assertEqual(
            parameters[0:5],
            (7, "POST", "/api/audio-uploads", "create_audio_upload", 201),
        )
        self.assertNotIn("token", parameters[2])
        connection.commit.assert_called_once()

    def test_password_policy_accepts_strong_password(self):
        self.assertEqual(api.validate_password("Correct-Horse-7"), "Correct-Horse-7")

    def test_password_policy_rejects_weak_password(self):
        with self.assertRaises(ValueError):
            api.validate_password("short")

    def test_temporary_password_meets_password_policy(self):
        temporary_password = api.generate_temporary_password()
        self.assertEqual(api.validate_password(temporary_password), temporary_password)
        self.assertEqual(len(temporary_password), 20)

    def test_email_is_normalized(self):
        self.assertEqual(api.clean_email("  User@Example.COM "), "user@example.com")

    def test_token_hash_is_deterministic_and_not_plaintext(self):
        digest = api.token_hash("secret-token")
        self.assertEqual(digest, api.token_hash("secret-token"))
        self.assertNotIn("secret-token", digest)
        self.assertEqual(len(digest), 64)

    def test_public_registration_rejects_privileged_role(self):
        with patch.object(api, "audit"):
            response = api.app.test_client().post(
                "/api/auth/register",
                json={
                    "name": "new-user",
                    "email": "user@example.com",
                    "password": "Correct-Horse-7",
                    "user_type": "admin",
                },
            )
        self.assertEqual(response.status_code, 400)
        self.assertIn("owner or technician accounts only", response.get_json()["error"])

    def test_public_registration_accepts_technician_role(self):
        connection = unittest.mock.MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = None
        cursor.lastrowid = 31
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "send_registration_otp"
        ) as send_otp, patch.object(api, "SMTP_HOST", "smtp.example.com"), patch.object(
            api, "SMTP_USERNAME", "user"
        ), patch.object(api, "SMTP_PASSWORD", "password"), patch.object(
            api, "SMTP_FROM", "no-reply@example.com"
        ):
            response = api.app.test_client().post(
                "/api/auth/register",
                json={
                    "name": "new-tech",
                    "email": "  Tech@Example.COM ",
                    "password": "Correct-Horse-7",
                    "user_type": "technician",
                },
        )
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["email"], "tech@example.com")
        insert_user = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO user" in call.args[0]
        )
        self.assertEqual(insert_user.args[1][1], "tech@example.com")
        self.assertEqual(insert_user.args[1][3], "technician")
        insert_otp = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO registration_otp" in call.args[0]
        )
        self.assertEqual(insert_otp.args[1][0], 31)
        send_otp.assert_called_once()
        self.assertEqual(send_otp.call_args.args[0], "tech@example.com")

    def test_registration_otp_schema_has_user_foreign_key(self):
        schema = (
            Path(__file__).resolve().parents[2] / "database" / "schema.sql"
        ).read_text(encoding="utf-8")
        otp_table = schema.split("CREATE TABLE IF NOT EXISTS registration_otp", 1)[1]
        self.assertIn("user_id INT NOT NULL", otp_table)
        self.assertIn("FOREIGN KEY (user_id) REFERENCES user(user_id)", otp_table)
        self.assertIn("email_verified_at DATETIME NULL", schema)

    def test_schema_persists_request_and_empirical_metadata(self):
        schema = (
            Path(__file__).resolve().parents[2] / "database" / "schema.sql"
        ).read_text(encoding="utf-8")
        self.assertIn("requires_password_change BOOLEAN", schema)
        self.assertIn("email_verified_at DATETIME NULL", schema)
        self.assertIn("CREATE TABLE IF NOT EXISTS api_request_log", schema)
        self.assertIn("analysis_purpose VARCHAR(40)", schema)
        self.assertIn("empirical_details JSON", schema)
        self.assertIn("worst_feature_status VARCHAR(40)", schema)
        self.assertIn("reference_recording_count INT", schema)
        self.assertIn("size_bytes BIGINT UNSIGNED", schema)
        self.assertIn("mime_type VARCHAR(100)", schema)
        self.assertIn(
            "UNIQUE KEY uq_audio_upload_assessment (assessment_id)", schema
        )
        upload_table = schema.split(
            "CREATE TABLE IF NOT EXISTS audio_upload", 1
        )[1].split("CREATE TABLE IF NOT EXISTS api_request_log", 1)[0]
        self.assertIn("assessment_id INT NOT NULL", upload_table)
        self.assertNotIn("user_id INT", upload_table)
        self.assertIn("ON DELETE CASCADE", upload_table)
        self.assertNotIn("CREATE TABLE IF NOT EXISTS password_reset_token", schema)

    def test_upload_history_derives_ownership_from_assessment(self):
        connection = unittest.mock.MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchall.return_value = []
        with api.app.test_request_context("/api/audio-uploads"), patch.object(
            api, "get_db", return_value=connection
        ):
            g.user_id = 7
            response = api.get_audio_uploads.__wrapped__()

        self.assertEqual(response.status_code, 200)
        statement, parameters = cursor.execute.call_args.args
        self.assertIn(
            "JOIN assessment a ON a.assessment_id = au.assessment_id",
            statement,
        )
        self.assertIn("WHERE a.user_id = %s", statement)
        self.assertNotIn("au.user_id", statement)
        self.assertEqual(parameters, (7,))

    def test_verification_marks_linked_user_email_as_verified(self):
        connection = unittest.mock.MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "registration_id": 9,
            "code_hash": api.token_hash("123456"),
            "attempts": 0,
            "user_id": 31,
            "username": "new-tech",
            "email": "tech@example.com",
            "role": "technician",
        }
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "auth_response", return_value=({"verified": True}, 201)
        ), patch.object(api, "audit"):
            response = api.app.test_client().post(
                "/api/auth/register/verify",
                json={"email": "tech@example.com", "code": "123456"},
            )

        self.assertEqual(response.status_code, 201)
        statements = "\n".join(
            call.args[0] for call in cursor.execute.call_args_list
        )
        self.assertIn("JOIN user ON user.user_id = registration_otp.user_id", statements)
        self.assertIn("UPDATE user SET email_verified_at", statements)
        self.assertNotIn("INSERT INTO user", statements)

    def test_login_rejects_unverified_email_account(self):
        connection = unittest.mock.MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "user_id": 31,
            "username": "new-tech",
            "email": "tech@example.com",
            "user_type": "technician",
            "password_hash": api.password_hasher.hash("Correct-Horse-7"),
            "is_active": True,
            "email_verified_at": None,
            "requires_password_change": False,
        }
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "audit"
        ):
            response = api.app.test_client().post(
                "/api/auth/login",
                json={
                    "identifier": "tech@example.com",
                    "password": "Correct-Horse-7",
                },
            )

        self.assertEqual(response.status_code, 401)

    def test_auth_token_has_required_security_claims(self):
        token, _ = api.issue_access_token(
            {"user_id": 7, "username": "owner", "email": "o@example.com", "user_type": "owner"}
        )
        payload = api.jwt.decode(
            token,
            api.JWT_SECRET,
            algorithms=["HS256"],
            issuer=api.JWT_ISSUER,
        )
        self.assertEqual(payload["sub"], "7")
        self.assertEqual(payload["role"], "owner")
        self.assertIn("jti", payload)

    def test_security_update_comparison_uses_epoch_seconds(self):
        payload = {"iat": 1_721_400_000}
        current = {"security_updated_at_epoch": 1_721_400_000}
        newer = {"security_updated_at_epoch": 1_721_400_001}
        self.assertFalse(api._token_precedes_security_update(payload, current))
        self.assertTrue(api._token_precedes_security_update(payload, newer))

    def test_forgot_password_replaces_password_and_revokes_sessions(self):
        connection = unittest.mock.MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {"id": 7}
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "send_temporary_password_email"
        ) as send_email, patch.object(api, "SMTP_HOST", "smtp.example.com"), patch.object(
            api, "SMTP_USERNAME", "user"
        ), patch.object(api, "SMTP_PASSWORD", "password"), patch.object(
            api, "SMTP_FROM", "no-reply@example.com"
        ), patch.object(api, "audit"):
            response = api.app.test_client().post(
                "/api/auth/forgot-password",
                json={"email": "user@example.com"},
            )

        self.assertEqual(response.status_code, 200)
        send_email.assert_called_once()
        self.assertTrue(connection.commit.called)
        statements = "\n".join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn("requires_password_change = TRUE", statements)
        self.assertIn("UPDATE refresh_token", statements)

    def test_reset_token_endpoint_is_removed(self):
        response = api.app.test_client().post(
            "/api/auth/reset-password",
            json={"token": "unused", "new_password": "Correct-Horse-7"},
        )
        self.assertEqual(response.status_code, 404)


if __name__ == "__main__":
    unittest.main()
