import unittest
from datetime import datetime, timedelta, timezone
from threading import Event
from unittest.mock import MagicMock, patch
from uuid import uuid4

from mysql.connector import Error

import app as api
from karaok.auth import accounts
from karaok.auth.otp import code_digest
from karaok.security.throttle import AuthThrottle, MemoryThrottleStore


class AuthHardeningTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(api.app.config, TESTING=True))
        api.limiter.reset()
        self.addCleanup(api.limiter.reset)
        self.now = 1000
        self.enterContext(patch.object(accounts, "auth_throttle", AuthThrottle(
            MemoryThrottleStore(), clock=lambda: self.now
        )))
        self.enterContext(patch.object(api, "audit"))
        self.enterContext(patch.object(accounts, "_mail_available", return_value=True))

    def test_bursts_escalate_and_reset_without_blocking_other_devices(self):
        now = 1000
        throttle = AuthThrottle(MemoryThrottleStore(), clock=lambda: now)

        def hit(device="a" * 32):
            return throttle.check("login", email="a@gmail.com", device_id=device, ip="192.0.2.1")

        for delay in (30, 60):
            for _ in range(5):
                self.assertTrue(hit().allowed)
            self.assertEqual(hit().retry_after, delay)
            self.assertTrue(hit("b" * 32).allowed)
            now += delay - 1
            self.assertEqual(hit().retry_after, 1)
            now += 1
        now += 901
        for _ in range(5):
            self.assertTrue(hit().allowed)
        self.assertEqual(hit().retry_after, 30)

    def test_domain_is_exact_and_gmail_aliases_are_canonical(self):
        from karaok.core.email_policy import canonical_email, clean_registration_email

        self.assertEqual(clean_registration_email(" A.B+x@GoogleMail.com "), "a.b+x@googlemail.com")
        self.assertEqual(canonical_email("a.b+x@googlemail.com"), "ab@gmail.com")
        with self.assertRaisesRegex(ValueError, "email domain"):
            clean_registration_email("a@sub.gmail.com")

    def test_otp_digest_is_scoped_to_purpose_challenge_and_email(self):
        first = code_digest("registration", "a" * 32, "a@gmail.com", "123456")
        self.assertNotEqual(first, code_digest("password_reset", "a" * 32, "a@gmail.com", "123456"))
        self.assertNotEqual(first, code_digest("registration", "b" * 32, "a@gmail.com", "123456"))
        self.assertNotEqual(first, code_digest("registration", "a" * 32, "b@gmail.com", "123456"))

    def test_verification_checks_bound_email_and_challenge_before_consuming(self):
        from karaok.auth.otp import verify_challenge

        cursor = MagicMock()
        cursor.fetchone.return_value = {
            "user_id": 1, "code_hash": code_digest("registration", "a" * 32, "a@gmail.com", "123456"),
        }
        outcome = verify_challenge(
            cursor, purpose="registration", challenge_id="a" * 32, email="b@gmail.com", code="123456",
        )
        self.assertIsNone(outcome)
        self.assertEqual(cursor.execute.call_args_list[0].args[1][:3], ("a" * 32, "b@gmail.com", "b@gmail.com"))
        self.assertIn("SET attempts = attempts + 1", cursor.execute.call_args_list[1].args[0])

    def test_forgot_password_returns_a_challenge_and_preserves_password(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.side_effect = [None, {"user_id": 1}, None]
        with patch.object(api, "get_db", return_value=connection), patch.object(accounts, "send_reset_otp"):
            client = api.app.test_client()
            absent = client.post("/api/auth/forgot-password", json={"email": "absent@gmail.com"})
            present = client.post("/api/auth/forgot-password", json={"email": "present@gmail.com"})
        self.assertEqual(absent.status_code, present.status_code)
        self.assertEqual(absent.status_code, 202)
        self.assertEqual(absent.get_json().keys(), present.get_json().keys())
        self.assertEqual(absent.get_json()["message"], present.get_json()["message"])
        for response in (absent, present):
            body = response.get_json()
            self.assertEqual(body["expires_at"] - body["server_time"], 600)
            self.assertEqual(body["resend_available_at"] - body["server_time"], 300)
        self.assertFalse(any("SET password" in call.args[0] for call in cursor.execute.call_args_list))

    def test_register_commits_before_background_smtp_and_never_waits_for_it(self):
        connection = MagicMock()
        connection.cursor.return_value.fetchone.return_value = None
        connection.cursor.return_value.lastrowid = 1
        started, release, done = Event(), Event(), Event()
        commit_observed = []

        def mail(*_):
            commit_observed.append(connection.commit.called)
            started.set()
            release.wait(3)
            done.set()

        with patch.object(api, "get_db", return_value=connection), patch.object(
            accounts, "send_registration_otp", side_effect=mail,
        ):
            try:
                response = api.app.test_client().post("/api/auth/register", json={
                    "email": "a@gmail.com", "password": "Good#A1b",
                })
                self.assertEqual(response.status_code, 202)
                self.assertTrue(started.wait(1))
                self.assertFalse(done.is_set())
                self.assertEqual(commit_observed, [True])
            finally:
                release.set()
                done.wait(1)

    def test_full_queue_is_retryable_without_creating_a_challenge(self):
        with patch.object(accounts, "MailReservation") as reservation, patch.object(api, "get_db") as db:
            reservation.return_value.__enter__.return_value.available = False
            with api.app.test_request_context("/api/auth/register", method="POST", json={
                "email": "a@gmail.com", "password": "Good#A1b",
            }):
                response, status, headers = accounts.register()
        self.assertEqual(status, 503)
        self.assertEqual(headers["Retry-After"], "30")
        self.assertEqual(response.get_json()["retry_after"], 30)
        db.assert_not_called()

    def test_reset_consumes_code_and_revokes_sessions_in_the_password_transaction(self):
        email, challenge_id, code = "a@gmail.com", "a" * 32, "123456"
        connection = MagicMock()
        cursor = connection.cursor.return_value
        user = {"user_id": 1, "password": accounts.password_hasher.hash("Old#Pass1")}
        cursor.fetchone.side_effect = [
            user, {"user_id": 1, "code_hash": code_digest("password_reset", challenge_id, email, code)},
            user, None,
        ]
        with patch.object(api, "get_db", return_value=connection), patch.object(accounts, "enqueue_mail") as mail:
            client = api.app.test_client()
            payload = {"email": email, "challenge_id": challenge_id, "code": code, "new_password": "New#Pass1"}
            response = client.post("/api/auth/forgot-password/reset", json=payload)
            again = client.post("/api/auth/forgot-password/reset", json=payload)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(again.status_code, 400)
        self.assertEqual(again.get_json()["field"], "code")
        updates = [call for call in cursor.execute.call_args_list if "SET password = " in call.args[0]]
        self.assertEqual(len(updates), 1)
        self.assertTrue(accounts.password_hasher.verify(updates[0].args[1][0], "New#Pass1"))
        statements = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertTrue(any("UPDATE refresh_token" in sql for sql in statements))
        self.assertTrue(any("DELETE FROM password_reset_otp" in sql for sql in statements))
        mail.assert_called_once()

    def test_two_devices_can_rotate_refresh_tokens_independently(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        expiry = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=1)
        row = {"user_id": 1, "is_active": True, "email_verified_at": expiry,
               "expires_at": expiry, "revoked_at": None}
        cursor.fetchone.side_effect = [dict(row, token_id=2), dict(row, token_id=3)]
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "auth_response", return_value=({"access_token": "new"}, 200),
        ):
            client = api.app.test_client()
            for token, device in (("token-a", "a"), ("token-b", "b")):
                response = client.post("/api/auth/refresh", json={"refresh_token": token},
                                       headers={"X-KaraOK-Device": device * 32})
                self.assertEqual(response.status_code, 200)
        revoked = [call.args[1] for call in cursor.execute.call_args_list if "UPDATE refresh_token" in call.args[0]]
        self.assertEqual(revoked, [(2,), (3,)])

    def test_otp_send_gate_uses_account_independent_cooldowns_and_hourly_cap(self):
        for send in range(4):
            allowed = accounts.auth_throttle.reserve_otp_send("registration", "a@gmail.com")
            self.assertTrue(allowed.allowed)
            self.now += 1
            blocked = accounts.auth_throttle.reserve_otp_send("registration", "a@gmail.com")
            self.assertEqual(blocked.retry_after, 2699 if send == 3 else 299)
            self.now += 299
        self.assertTrue(accounts.auth_throttle.reserve_otp_send("registration", "b@gmail.com").allowed)

    def test_login_burst_returns_the_same_retry_deadline_in_header_and_body(self):
        connection = MagicMock()
        connection.cursor.return_value.fetchone.return_value = None
        payload = {"identifier": "a@gmail.com", "password": "Valid#Pass1"}
        with patch.object(api, "get_db", return_value=connection) as db:
            client = api.app.test_client()
            for _ in range(5):
                result = client.post("/api/auth/login", json=payload, headers={"X-KaraOK-Device": "a" * 32})
                self.assertEqual(result.status_code, 401)
            db.reset_mock()
            blocked = client.post("/api/auth/login", json=payload, headers={"X-KaraOK-Device": "a" * 32})
            db.assert_not_called()
            separate = client.post("/api/auth/login", json=payload, headers={"X-KaraOK-Device": "b" * 32})
        self.assertEqual(blocked.status_code, 429)
        self.assertEqual(blocked.headers["Retry-After"], "30")
        self.assertEqual(blocked.get_json()["retry_after"], 30)
        self.assertEqual(separate.status_code, 401)

    def test_one_device_cannot_send_codes_to_many_emails(self):
        connection = MagicMock()
        connection.cursor.return_value.fetchone.return_value = None
        connection.cursor.return_value.lastrowid = 1
        with (
            patch.object(api, "get_db", return_value=connection),
            patch.object(accounts, "_submit_otp_mail", return_value=True) as queued,
        ):
            client = api.app.test_client()

            def register(index, device):
                return client.post(
                    "/api/auth/register",
                    json={"email": f"test.sender.{index}@gmail.com", "password": "Valid#Pass1"},
                    headers={"X-KaraOK-Device": device},
                )

            for index in range(10):
                self.assertEqual(register(index, "a" * 32).status_code, 202)
            self.now += 1800
            blocked = register(10, "a" * 32)
            self.assertEqual(blocked.status_code, 429)
            self.assertEqual(blocked.get_json()["retry_after"], 1800)
            self.assertEqual(blocked.headers["Retry-After"], "1800")
            self.assertEqual(queued.call_count, 10)
            self.assertEqual(register(11, "b" * 32).status_code, 202)
            self.now += 1800
            self.assertEqual(register(12, "a" * 32).status_code, 202)

    def test_ip_hourly_otp_cap_covers_rotating_device_ids(self):
        connection = MagicMock()
        connection.cursor.return_value.fetchone.return_value = None
        with (
            patch.object(api, "get_db", return_value=connection),
            patch.object(accounts, "_submit_otp_mail", return_value=True) as queued,
        ):
            client = api.app.test_client()

            def request_code(index, resend=False, ip="192.0.2.1"):
                path = "/api/auth/forgot-password"
                payload = {"email": f"test.sender.{index}@gmail.com"}
                if resend:
                    path = "/api/auth/register/resend"
                    payload["challenge_id"] = "a" * 32
                return client.post(
                    path,
                    json=payload,
                    headers={"X-KaraOK-Device": uuid4().hex},
                    environ_overrides={"REMOTE_ADDR": ip},
                )

            for index in range(30):
                self.assertEqual(request_code(index, resend=index % 2 == 0).status_code, 202)
            self.now += 900
            blocked = request_code(30)
            self.assertEqual(blocked.status_code, 429)
            self.assertEqual(blocked.get_json()["retry_after"], 2700)
            self.assertEqual(queued.call_count, 30)
            self.assertEqual(request_code(31, ip="192.0.2.2").status_code, 202)

    def test_otp_send_reservation_fails_open_on_db_error(self):
        store = MagicMock()
        store.update.side_effect = Error("database unavailable")
        store.update_many.side_effect = Error("database unavailable")
        throttle = AuthThrottle(store)
        with patch.object(api.app.logger, "exception") as log:
            self.assertTrue(throttle.reserve_otp_send("registration", "a@gmail.com").allowed)
            self.assertTrue(throttle.reserve_otp_sender(device_id="a" * 32, ip="192.0.2.1").allowed)
        self.assertEqual(log.call_count, 2)

    def test_absent_or_invalid_device_ids_share_the_ip_fallback_budget(self):
        throttle = accounts.auth_throttle
        for _ in range(10):
            self.assertTrue(throttle.reserve_otp_sender(device_id=None, ip="192.0.2.1").allowed)
        blocked = throttle.reserve_otp_sender(device_id="invalid", ip="192.0.2.1")
        self.assertEqual(blocked.retry_after, 3600)
        self.assertTrue(throttle.reserve_otp_sender(device_id="a" * 32, ip="192.0.2.1").allowed)
        self.assertTrue(throttle.reserve_otp_sender(device_id=None, ip="192.0.2.2").allowed)

    def test_resend_rotates_the_code_after_the_cooldown(self):
        from karaok.auth.otp import ResendTooSoon, resend_challenge

        email, challenge_id, old_code = "a@gmail.com", "a" * 32, "123456"
        sent = datetime.fromtimestamp(1000, timezone.utc).replace(tzinfo=None)
        cursor = MagicMock()
        cursor.fetchone.return_value = {
            "challenge_id": challenge_id,
            "last_sent_at": sent,
            "send_count_window_start": sent,
            "send_count": 1,
            "code_hash": code_digest("registration", challenge_id, email, old_code),
        }
        params = {"purpose": "registration", "user_id": 1, "email": email, "challenge_id": challenge_id}
        with patch("karaok.auth.otp.time.time", return_value=1299):
            with self.assertRaises(ResendTooSoon) as raised:
                resend_challenge(cursor, **params)
        self.assertEqual(raised.exception.retry_after, 1)
        with patch("karaok.auth.otp.time.time", return_value=1300):
            rotated = resend_challenge(cursor, **params)
        self.assertEqual(rotated.challenge_id, challenge_id)
        self.assertNotEqual(rotated.code, old_code)
        self.assertEqual(rotated.expires_at, 1900)
        self.assertEqual(rotated.resend_available_at, 1600)
