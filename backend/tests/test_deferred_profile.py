"""Minimal registration and deferred profile regression coverage (no live DB)."""
import unittest
from unittest.mock import MagicMock, patch
from contextlib import ExitStack
from tests.test_security import api
from karaok.core.accounts import _profile_response

FIELDS = ('first_name', 'last_name', 'address', 'city', 'state_province',
          'area_code', 'country', 'country_code', 'phone_number', 'birthday')


class DeferredProfileTests(unittest.TestCase):
    def setUp(self):
        api.limiter.reset()
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value
        self.cursor.fetchone.return_value = None
        self.cursor.lastrowid = 31

    def tearDown(self):
        api.limiter.reset()

    def test_minimal_signup_stores_null_details_and_hashed_email_code(self):
        with ExitStack() as stack:
            stack.enter_context(patch.object(api, 'get_db', return_value=self.connection))
            send = stack.enter_context(patch.object(api, 'send_registration_otp'))
            for key in ('SMTP_HOST', 'SMTP_USERNAME', 'SMTP_PASSWORD', 'SMTP_FROM'):
                stack.enter_context(patch.object(api, key, 'test-only'))
            with api.app.test_request_context('/api/auth/register', method='POST', json={
                'email': 'user@example.com', 'username': 'new-user', 'password': 'Good#A1b',
            }):
                response, status = api.register.__wrapped__()
        self.assertEqual(status, 202)
        self.assertNotIn('access_token', response.get_json())
        calls = self.cursor.execute.call_args_list
        params = next(c.args[1] for c in calls if 'INSERT INTO user' in c.args[0])
        self.assertEqual(params[1:3], (None, None))
        self.assertEqual(params[5:], (None,) * 10)
        self.assertTrue(api.password_hasher.verify(params[4], 'Good#A1b'))
        otp = next(c.args[1] for c in calls if 'INSERT INTO registration_otp' in c.args[0])
        self.assertEqual(otp[1], api.token_hash(send.call_args.args[1]))
        self.connection.commit.assert_called_once()

    def test_registration_email_delivery_failure_is_a_banner_error(self):
        import smtplib
        for failure in (smtplib.SMTPException("delivery failed"), OSError("unavailable")):
            with self.subTest(failure=type(failure).__name__):
                self.connection.reset_mock()
                with ExitStack() as stack:
                    stack.enter_context(patch.object(api, 'get_db', return_value=self.connection))
                    stack.enter_context(patch.object(api, 'send_registration_otp', side_effect=failure))
                    stack.enter_context(patch.object(api.app.logger, 'exception'))
                    for key in ('SMTP_HOST', 'SMTP_USERNAME', 'SMTP_PASSWORD', 'SMTP_FROM'):
                        stack.enter_context(patch.object(api, key, 'test-only'))
                    with api.app.test_request_context('/api/auth/register', method='POST', json={
                        'email': 'user@example.com', 'username': 'new-user', 'password': 'Good#A1b',
                    }):
                        response, status = api.register.__wrapped__()
                self.assertEqual(status, 503)
                self.assertEqual(response.get_json(), {'error': 'Unable to send verification email'})
                self.connection.rollback.assert_called_once()
                self.connection.commit.assert_not_called()
                self.cursor.close.assert_called_once()
                self.connection.close.assert_called_once()

    def test_login_missing_account_and_wrong_password_share_email_error(self):
        from argon2.exceptions import VerifyMismatchError
        message = 'Invalid email or password'
        for user in (None, {'user_id': 31, 'is_active': True,
                            'email_verified_at': object(), 'password_hash': 'test-hash'}):
            with self.subTest(existing=user is not None):
                self.cursor.fetchone.return_value = user
                with patch.object(api, 'get_db', return_value=self.connection), patch.object(
                    api, 'audit'
                ), patch.object(api, 'auth_response') as auth, patch.object(
                    type(api.password_hasher), 'verify', side_effect=VerifyMismatchError('mismatch')
                ) as verify, api.app.test_request_context('/api/auth/login', method='POST', json={
                    'email': 'user@example.com', 'password': 'Wrong#A1b',
                }):
                    response, status = api.login.__wrapped__()
                self.assertEqual(status, 401)
                self.assertEqual(response.get_json(), {
                    'error': message, 'errors': {'identifier': message, 'password': message},
                })
                auth.assert_not_called()
                self.assertEqual(verify.call_count, int(user is not None))

    def test_login_unverified_and_inactive_accounts_remain_blocked(self):
        for active, verified in ((False, object()), (True, None)):
            with self.subTest(active=active, verified=verified is not None):
                self.cursor.fetchone.return_value = {
                    'user_id': 31, 'is_active': active, 'email_verified_at': verified,
                }
                with patch.object(api, 'get_db', return_value=self.connection), patch.object(
                    api, 'audit'
                ), patch.object(api, 'auth_response') as auth, patch.object(
                    type(api.password_hasher), 'verify'
                ) as verify, api.app.test_request_context('/api/auth/login', method='POST', json={
                    'email': 'user@example.com', 'password': 'Good#A1b',
                }):
                    response, status = api.login.__wrapped__()
                self.assertEqual(status, 401)
                self.assertIn('error', response.get_json())
                auth.assert_not_called()
                verify.assert_not_called()

    def pending_user(self):
        return dict.fromkeys(FIELDS) | {
            'user_id': 31, 'username': 'new-user', 'email': 'user@example.com',
            'role': 'user', 'user_type': 'user', 'profile_image': None,
            'profile_image_mime': None, 'registration_id': 9,
            'code_hash': api.token_hash('123456'), 'attempts': 0,
        }

    def test_profile_display_name_uses_email_instead_of_generated_username(self):
        for username in ('user_' + 'a' * 32, 'legacy-name'):
            for first, last in ((None, None), ('', ''), ('  ', '  ')):
                with self.subTest(username=username, first=first, last=last):
                    user = dict(self.pending_user(), username=username,
                                first_name=first, last_name=last)
                    profile = _profile_response(user)
                    self.assertEqual(profile['name'], 'user@example.com')
                    self.assertEqual(profile['username'], username)
                    self.assertFalse(profile['profile_complete'])

    def test_profile_display_name_prefers_trimmed_first_and_last_names(self):
        for first, last, expected in (
            ('  New  ', '  User  ', 'New User'),
            ('  New  ', None, 'New'),
            (None, '  User  ', 'User'),
            ('  ', '  User  ', 'User'),
        ):
            with self.subTest(first=first, last=last):
                user = dict(self.pending_user(), username='user_' + 'a' * 32,
                            first_name=first, last_name=last)
                profile = _profile_response(user)
                self.assertEqual(profile['name'], expected)
                self.assertEqual(profile['first_name'], first)
                self.assertEqual(profile['last_name'], last)

    def test_otp_accepts_null_profile_and_consumes_code(self):
        self.cursor.fetchone.return_value = self.pending_user()
        with patch.object(api, 'get_db', return_value=self.connection), patch.object(
            api, 'auth_response', side_effect=lambda user, status: (_profile_response(user), status)
        ), patch.object(api, 'audit'), api.app.test_request_context(
            '/api/auth/register/verify', method='POST',
            json={'email': 'user@example.com', 'code': '123456'},
        ):
            user, status = api.verify_registration.__wrapped__()
        self.assertEqual(status, 201)
        self.assertFalse(user['profile_complete'])
        self.assertEqual(user['name'], 'user@example.com')
        for field in FIELDS:
            self.assertIsNone(user[field])
        statements = '\n'.join(c.args[0] for c in self.cursor.execute.call_args_list)
        self.assertIn('DELETE FROM registration_otp', statements)
        self.assertIn('expires_at > UTC_TIMESTAMP()', statements)
        self.assertIn('attempts < 5', statements)

    def test_wrong_code_increments_attempts_without_authenticating(self):
        self.cursor.fetchone.return_value = self.pending_user()
        with patch.object(api, 'get_db', return_value=self.connection), patch.object(
            api, 'auth_response'
        ) as auth, api.app.test_request_context('/api/auth/register/verify', method='POST',
            json={'email': 'user@example.com', 'code': '000000'}):
            _, status = api.verify_registration.__wrapped__()
        self.assertEqual(status, 400)
        auth.assert_not_called()
        self.assertIn('attempts = attempts + 1', self.cursor.execute.call_args.args[0])

    def test_missing_expired_or_exhausted_code_cannot_authenticate(self):
        with patch.object(api, 'get_db', return_value=self.connection), patch.object(
            api, 'auth_response'
        ) as auth, api.app.test_request_context('/api/auth/register/verify', method='POST',
            json={'email': 'user@example.com', 'code': '123456'}):
            _, status = api.verify_registration.__wrapped__()
        self.assertEqual(status, 400)
        auth.assert_not_called()

    def test_minimal_signup_still_rejects_admin_role_and_weak_password(self):
        for overrides in ({'user_type': 'admin'}, {'password': 'weak'}):
            with self.subTest(overrides=overrides), api.app.test_request_context(
                '/api/auth/register', method='POST', json={
                    'email': 'user@example.com', 'username': 'new-user',
                    'password': 'Good#A1b', **overrides,
                }), patch.object(api, 'get_db') as db:
                with self.assertRaises(ValueError):
                    api.register.__wrapped__()
                db.assert_not_called()


    def test_email_only_signup_retries_placeholder_collision(self):
        self.cursor.fetchone.side_effect = [None, {'user_id': 8}, None, None]
        with patch.object(api, 'get_db', return_value=self.connection), patch.object(
            api, 'send_registration_otp'
        ), patch.object(api, 'SMTP_HOST', 'test'), patch.object(
            api, 'SMTP_USERNAME', 'test'
        ), patch.object(api, 'SMTP_PASSWORD', 'test'), patch.object(
            api, 'SMTP_FROM', 'test'
        ), api.app.test_request_context('/api/auth/register', method='POST', json={
            'email': 'user@example.com', 'password': 'Good#A1b',
        }):
            _, status = api.register()
        self.assertEqual(status, 202)
        calls = self.cursor.execute.call_args_list
        candidates = [c.args[1][0] for c in calls if 'SELECT user_id FROM user WHERE username' in c.args[0]]
        self.assertEqual(len(candidates), 2)
        self.assertNotEqual(*candidates)
        params = next(c.args[1] for c in calls if 'INSERT INTO user' in c.args[0])
        self.assertEqual(params[0], candidates[-1])
        self.assertRegex(params[0], r'^user_[a-f0-9]{32}$')

    def test_email_only_retry_preserves_pending_username(self):
        self.cursor.fetchone.side_effect = [
            {'user_id': 31, 'username': 'legacy-name', 'email_verified_at': None},
            {'user_id': 31},
        ]
        with patch.object(api, 'get_db', return_value=self.connection), patch.object(
            api, 'send_registration_otp'
        ), patch.object(api, 'SMTP_HOST', 'test'), patch.object(
            api, 'SMTP_USERNAME', 'test'
        ), patch.object(api, 'SMTP_PASSWORD', 'test'), patch.object(
            api, 'SMTP_FROM', 'test'
        ), api.app.test_request_context('/api/auth/register', method='POST', json={
            'email': 'user@example.com', 'password': 'Good#A1b',
        }):
            _, status = api.register()
        self.assertEqual(status, 202)
        params = next(c.args[1] for c in self.cursor.execute.call_args_list
                      if 'SET username' in c.args[0])
        self.assertEqual(params[0], 'legacy-name')
        self.assertEqual(params[-1], 31)

    def test_auth_validation_returns_structured_fields_without_database(self):
        cases = [
            ('register', {'email': 'bad', 'password': 'Good#A1b'}, 'email'),
            ('register', {'email': 'user@example.com', 'password': 'weak'}, 'password'),
            ('register', {'username': '!', 'email': 'user@example.com'}, 'username'),
            ('verify_registration', {'email': 'user@example.com', 'code': 'abc'}, 'code'),
            ('login', {'identifier': '!bad', 'password': 'hello'}, 'identifier'),
            ('login', {'identifier': 'user@example.com', 'password': ''}, 'password'),
            ('forgot_password', {'email': 'bad'}, 'email'),
        ]
        for name, payload, field in cases:
            with self.subTest(name=name, field=field), patch.object(api, 'get_db') as db:
                with api.app.test_request_context('/api/auth/test', method='POST', json=payload):
                    response, status = getattr(api, name)()
                self.assertEqual(status, 400)
                body = response.get_json()
                self.assertEqual(body['field'], field)
                self.assertNotIn('field_errors', body)
                db.assert_not_called()


    def test_change_password_validation_uses_password_field_keys(self):
        import inspect
        from flask import g
        from karaok.auth.accounts import _field_errors
        view = _field_errors(inspect.unwrap(api.change_password))
        for payload, field in [
            ({'new_password': 'weak'}, 'new_password'),
            ({'new_password': 'Good#A1b'}, 'current_password'),
            ({'new_password': 'Good#A1b', 'current_password': 'Good#A1b'}, 'new_password'),
        ]:
            with self.subTest(field=field), patch.object(api, 'get_db') as db:
                with api.app.test_request_context('/api/auth/change-password', method='POST', json=payload):
                    g.requires_password_change = False
                    response, status = view()
                self.assertEqual(status, 400)
                self.assertEqual(response.get_json()['field'], field)
                db.assert_not_called()


    def test_error_helper_matches_single_and_multiple_field_contract(self):
        from karaok.auth.accounts import _auth_error
        with api.app.test_request_context():
            single, status = _auth_error('Invalid', 400, email='Invalid')
            multiple, _ = _auth_error('Invalid credentials', 401,
                                     identifier='Invalid', password='Invalid')
        self.assertEqual(status, 400)
        self.assertEqual(single.get_json(), {'error': 'Invalid', 'field': 'email'})
        self.assertEqual(multiple.get_json(), {
            'error': 'Invalid credentials',
            'errors': {'identifier': 'Invalid', 'password': 'Invalid'},
        })


class ProfileFieldErrorTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value
        self.cursor.fetchone.return_value = None

    @staticmethod
    def profile_payload(**overrides):
        return {
            "username": "new-user", "first_name": "New", "last_name": "User",
            "address": "123 Sample Street", "city": "Manila",
            "state_province": "Metro Manila", "area_code": "1000",
            "country": "Philippines", "country_code": "PH",
            "phone_number": "+639123456789", "birthday": "2000-01-02",
            **overrides,
        }

    def update_profile(self, payload):
        from flask import g
        with api.app.test_request_context("/api/users/me", method="PATCH", json=payload):
            g.user_id = 31
            # Bypass authentication only, retaining the response error decorator.
            return api.update_profile.__wrapped__()

    def test_email_is_immutable_with_structured_error_before_database_access(self):
        with patch.object(api, "get_db") as db:
            response, status = self.update_profile({"email": "changed@example.com"})
        self.assertEqual(status, 400)
        self.assertEqual(response.get_json(), {
            "error": "email cannot be changed", "field": "email",
        })
        db.assert_not_called()

    def test_profile_validation_reports_responsible_field_without_database_access(self):
        for overrides, field in [
            ({"username": "!invalid"}, "username"),
            ({"first_name": ""}, "first_name"),
            ({"last_name": None}, "last_name"),
            ({"address": "abc"}, "address"),
            ({"city": ""}, "city"),
            ({"state_province": ""}, "state_province"),
            ({"area_code": ""}, "area_code"),
            ({"country": ""}, "country"),
            ({"country_code": "12"}, "country_code"),
            ({"phone_number": "not a number"}, "phone_number"),
            ({"birthday": "not a date"}, "birthday"),
            ({"profile_image_base64": "invalid!", "profile_image_mime": "image/png"}, "profile_image"),
            ({"profile_image_base64": "aGVsbG8=", "profile_image_mime": "text/plain"}, "profile_image"),
        ]:
            with self.subTest(field=field, overrides=overrides), patch.object(api, "get_db") as db:
                response, status = self.update_profile(self.profile_payload(**overrides))
                self.assertEqual(status, 400)
                body = response.get_json()
                self.assertEqual(body["field"], field)
                self.assertIsInstance(body["error"], str)
                self.assertNotIn("errors", body)
                db.assert_not_called()

    def test_preflight_conflicts_report_username_or_phone_and_never_update(self):
        message = "Username or phone number is already in use"
        for conflict, field in [
            ({"username": "new-user", "phone_number": "+639999999999"}, "username"),
            ({"username": "other-user", "phone_number": "+639123456789"}, "phone_number"),
        ]:
            with self.subTest(field=field):
                self.connection.reset_mock()
                self.cursor.fetchone.return_value = conflict
                with patch.object(api, "get_db", return_value=self.connection), patch.object(api, "audit") as audit:
                    response, status = self.update_profile(self.profile_payload())
                self.assertEqual(status, 409)
                self.assertEqual(response.get_json(), {"error": message, "field": field})
                self.cursor.execute.assert_called_once()
                self.assertEqual(self.cursor.execute.call_args.args[1], (31, "new-user", "+639123456789"))
                self.connection.commit.assert_not_called()
                audit.assert_not_called()
                self.cursor.close.assert_called_once()
                self.connection.close.assert_called_once()

    def test_integrity_race_returns_both_fields_rolls_back_and_hides_database_details(self):
        from mysql.connector import IntegrityError
        message = "Username or phone number is already in use"
        # Cover failure before the preflight result exists, during the update,
        # and at commit. None of these paths may rely on a conflict row.
        for phase in ("select", "update", "commit"):
            with self.subTest(phase=phase):
                connection = MagicMock()
                cursor = connection.cursor.return_value
                cursor.rowcount = 1
                cursor.fetchone.side_effect = [None, {
                    **self.profile_payload(), "user_id": 31, "email": "user@example.com",
                    "user_type": "user", "profile_image": None, "profile_image_mime": None,
                }]
                error = IntegrityError("private-db-index: secret@example.com", errno=1062)
                if phase == "commit":
                    connection.commit.side_effect = error
                else:
                    cursor.execute.side_effect = [error] if phase == "select" else [None, error]
                with patch.object(api, "get_db", return_value=connection), patch.object(api, "audit") as audit:
                    response, status = self.update_profile(self.profile_payload())
                self.assertEqual(status, 409)
                self.assertEqual(response.get_json(), {
                    "error": message,
                    "errors": {"username": message, "phone_number": message},
                })
                self.assertNotIn("secret@example.com", response.get_data(as_text=True))
                self.assertNotIn("private-db-index", response.get_data(as_text=True))
                connection.rollback.assert_called_once()
                if phase != "commit":
                    connection.commit.assert_not_called()
                audit.assert_not_called()
                cursor.close.assert_called_once()
                connection.close.assert_called_once()

    def test_unchanged_active_profile_save_succeeds_with_zero_changed_rows(self):
        payload = self.profile_payload()
        stored = {
            **payload, "user_id": 31, "email": "user@example.com",
            "user_type": "user", "profile_image": None, "profile_image_mime": None,
        }
        self.cursor.rowcount = 0
        self.cursor.fetchone.side_effect = [None, stored]
        with patch.object(api, "get_db", return_value=self.connection), patch.object(api, "audit") as audit:
            response, status = self.update_profile(payload)
        self.assertEqual(status, 200)
        self.assertEqual(response.get_json()["user"]["username"], payload["username"])
        statements = self.cursor.execute.call_args_list
        self.assertIn("UPDATE user", statements[1].args[0])
        self.assertIn("is_active = TRUE", statements[1].args[0])
        self.assertIn("FROM user WHERE user_id = %s AND is_active = TRUE", statements[2].args[0])
        self.assertEqual(statements[2].args[1], (31,))
        self.connection.commit.assert_called_once()
        self.connection.rollback.assert_not_called()
        audit.assert_called_once()
        self.cursor.close.assert_called_once()
        self.connection.close.assert_called_once()

    def test_missing_or_inactive_profile_save_returns_404_without_commit(self):
        # Both an absent user and an inactive user are excluded by the lookup.
        # Also cover disappearance/deactivation after a changed-row update.
        for rowcount in (0, 1):
            with self.subTest(rowcount=rowcount):
                connection = MagicMock()
                cursor = connection.cursor.return_value
                cursor.rowcount = rowcount
                cursor.fetchone.side_effect = [None, None]
                with patch.object(api, "get_db", return_value=connection), patch.object(api, "audit") as audit:
                    response, status = self.update_profile(self.profile_payload())
                self.assertEqual(status, 404)
                self.assertEqual(response.get_json(), {"error": "Account is unavailable"})
                lookup = cursor.execute.call_args
                self.assertIn("FROM user WHERE user_id = %s AND is_active = TRUE", lookup.args[0])
                self.assertEqual(lookup.args[1], (31,))
                connection.rollback.assert_called_once()
                connection.commit.assert_not_called()
                audit.assert_not_called()
                cursor.close.assert_called_once()
                connection.close.assert_called_once()
