import os
import unittest
from pathlib import Path


os.environ.setdefault(
    "JWT_SECRET",
    "test-only-secret-that-is-at-least-32-characters",
)

import app as api


ROOT = Path(__file__).resolve().parents[2]


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
                "audit.get_audit_logs",
                "admin_data.health",
                "admin_data.records",
            }.issubset(endpoints)
        )

    def test_legacy_genre_settings_route_is_removed(self):
        response = api.app.test_client().get("/api/genre-settings")
        self.assertEqual(response.status_code, 404)

    def test_legacy_entry_point_exposes_packaged_application(self):
        self.assertEqual(api.app.import_name, "karaok.application")

    def test_public_docs_name_settings_generation_safety_and_sources(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("Adjusted amplifier settings", readme)
        self.assertIn("Record Again to Verify", readme)
        self.assertIn("docs/settings-profile-sources.md", readme)


if __name__ == "__main__":
    unittest.main()
