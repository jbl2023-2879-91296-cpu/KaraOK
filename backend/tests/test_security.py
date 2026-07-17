import os
import unittest
from unittest.mock import patch

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api


class SecurityValidationTests(unittest.TestCase):
    def test_password_policy_accepts_strong_password(self):
        self.assertEqual(api.validate_password("Correct-Horse-7"), "Correct-Horse-7")

    def test_password_policy_rejects_weak_password(self):
        with self.assertRaises(ValueError):
            api.validate_password("short")

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
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "send_registration_otp"
        ), patch.object(api, "SMTP_HOST", "smtp.example.com"), patch.object(
            api, "SMTP_USERNAME", "user"
        ), patch.object(api, "SMTP_PASSWORD", "password"), patch.object(
            api, "SMTP_FROM", "no-reply@example.com"
        ):
            response = api.app.test_client().post(
                "/api/auth/register",
                json={
                    "name": "new-tech",
                    "email": "tech@example.com",
                    "password": "Correct-Horse-7",
                    "user_type": "technician",
                },
            )
        self.assertEqual(response.status_code, 202)
        inserted_values = cursor.execute.call_args_list[-1].args[1]
        self.assertEqual(inserted_values[3], "technician")

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


if __name__ == "__main__":
    unittest.main()
