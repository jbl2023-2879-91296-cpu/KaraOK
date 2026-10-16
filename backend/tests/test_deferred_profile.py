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

    def pending_user(self):
        return dict.fromkeys(FIELDS) | {
            'user_id': 31, 'username': 'new-user', 'email': 'user@example.com',
            'role': 'user', 'user_type': 'user', 'profile_image': None,
            'profile_image_mime': None, 'registration_id': 9,
            'code_hash': api.token_hash('123456'), 'attempts': 0,
        }

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
        self.assertEqual(user['name'], 'new-user')
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
