import os
import unittest


os.environ.setdefault(
    "JWT_SECRET",
    "test-only-secret-that-is-at-least-32-characters",
)

import app as api


class ModularStructureTests(unittest.TestCase):
    def test_feature_blueprints_own_public_routes(self):
        endpoints = {
            rule.endpoint
            for rule in api.app.url_map.iter_rules()
            if str(rule).startswith("/api")
        }
        self.assertTrue(
            {
                "system.health",
                "auth.login",
                "users.get_users",
                "assessments.get_audio_tests",
                "audio_analysis.create_audio_upload",
                "genre_settings.get_genre_settings",
                "audit.get_audit_logs",
                "admin_data.health",
                "admin_data.records",
            }.issubset(endpoints)
        )

    def test_legacy_entry_point_exposes_packaged_application(self):
        self.assertEqual(api.app.import_name, "karaok.application")


if __name__ == "__main__":
    unittest.main()
