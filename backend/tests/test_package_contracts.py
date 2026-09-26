"""Behavioral compatibility gates for the package extraction."""

import ast
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
import inspect
from unittest.mock import MagicMock, patch


ROOT = Path(__file__).resolve().parents[1]


class PackageContractTests(unittest.TestCase):
    def test_admin_implementation_imports_without_application(self):
        result = subprocess.run(
            [sys.executable, "-c", (
                "import sys; from karaok.admin import users, logs; "
                "from karaok.admin.data import service, reports; "
                "assert 'karaok.application' not in sys.modules; "
                "assert not any(n.startswith('karaok.audio_pipeline') for n in sys.modules); "
                "assert service.quote_identifier('assessment') == '`assessment`'"
            )], cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_only_public_pipeline_interface_is_imported_by_consumers(self):
        for path in (ROOT / "karaok").rglob("*.py"):
            relative = path.relative_to(ROOT).with_suffix("")
            parts = relative.parts
            if "audio_pipeline" in parts:
                continue
            package = ".".join(parts if parts[-1] == "__init__" else parts[:-1])
            package = package.removesuffix(".__init__")
            for node in ast.walk(ast.parse(path.read_text())):
                if isinstance(node, ast.ImportFrom):
                    module = node.module or ""
                    if node.level:
                        module = importlib.util.resolve_name("." * node.level + module, package)
                    targets = [module]
                    if module == "karaok.audio_pipeline":
                        targets = [module + "." + alias.name for alias in node.names]
                elif isinstance(node, ast.Import):
                    targets = [alias.name for alias in node.names]
                else:
                    continue
                for target in targets:
                    if parts[1] == "core" and target.startswith("karaok."):
                        with self.subTest(path=str(relative), target=target):
                            self.assertTrue(target.startswith("karaok.core."))
                    if target.startswith("karaok.audio_pipeline"):
                        with self.subTest(path=str(relative), target=target):
                            self.assertEqual(target, "karaok.audio_pipeline.pipeline")
                            self.assertNotIn(parts[1], {"core", "results"})

    def test_feature_modules_do_not_import_application_backwards(self):
        feature_roots = ("core", "auth", "users", "audio_pipeline", "results", "admin", "system", "modules")
        for feature in feature_roots:
            for path in (ROOT / "karaok" / feature).rglob("*.py"):
                for node in ast.walk(ast.parse(path.read_text())):
                    if isinstance(node, ast.ImportFrom):
                        imports_application = (
                            (node.module or "").endswith("application")
                            or any(alias.name == "application" for alias in node.names)
                        )
                    elif isinstance(node, ast.Import):
                        imports_application = any(
                            alias.name == "karaok.application" for alias in node.names
                        )
                    else:
                        continue
                    with self.subTest(path=str(path.relative_to(ROOT)), line=node.lineno):
                        self.assertFalse(imports_application)

    def test_pipeline_public_interface_imports_without_application(self):
        result = subprocess.run(
            [sys.executable, "-c", (
                "import sys; from karaok.audio_pipeline import pipeline; "
                "assert 'karaok.application' not in sys.modules; "
                "assert 'karaok.modules.settings_recommendations.service' not in sys.modules; "
                "dump = {'analysis': {}, 'empirical_quality': "
                "{'overall_score': 88.0, 'overall_status': 'good'}}; "
                "summary = pipeline.summarize_audio_analysis(dump); "
                "assert summary['score'] == 88.0; "
                "assert summary['status'] == 'Acceptable'"
            )], cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_record_writer_persists_prepared_summary_without_analysis(self):
        from karaok.results import records

        connection = MagicMock()
        summary = {
            "score": 88.0, "status": "Acceptable", "noise_level": -42.0,
            "distortion_level": 4.0, "bass": 30.0, "treble": 10.0,
            "loudness": -14.0, "sharpness": 0.2, "flatness": 0.03,
            "empirical_quality": {
                "overall_status": "good", "worst_feature_status": "good",
                "worst_features": [], "algorithm_version": "1.0.0",
                "quality_profile_version": "saved-version",
                "artifact_checksum": "unused",
                "quality_profile_checksum": "a" * 64,
                "reference_recording_count": 30,
            },
        }
        # No raw analysis: the persistence boundary must not recompute it.
        dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "visualizations": {"waveform": "7/11/w.png", "spectrogram": "7/11/s.png"},
        }
        with patch.object(records, "get_db", return_value=connection):
            result = records.save_audio_analysis(11, 13, dump, summary=summary)
        self.assertEqual(result["score"], 88.0)
        statements = connection.cursor.return_value.execute.call_args_list
        insert = next(call for call in statements if "INSERT INTO audio_analysis_result" in call.args[0])
        self.assertEqual(insert.args[1][:4], (11, 88.0, -42.0, 4.0))
        self.assertEqual(insert.args[1][14:16], ("saved-version", "a" * 64))
        connection.commit.assert_called_once()

    def test_results_import_without_application_or_pipeline(self):
        result = subprocess.run(
            [sys.executable, "-c", (
                "import sys; from karaok.results import records, presentation, profiles, recommendations; "
                "assert 'karaok.application' not in sys.modules; "
                "assert not any(n.startswith('karaok.audio_pipeline') for n in sys.modules); "
                "row = presentation._enrich_audio_test_row({'score': 88.0, 'status': 'Acceptable'}); "
                "assert row['empirical_quality']['overall_score'] == 88.0"
            )], cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_configuration_override_reaches_and_restores_core_consumers(self):
        import app as api

        original = api.MAX_PROFILE_IMAGE_BYTES
        png = {"profile_image_base64": "iVBORw0KGgo=", "profile_image_mime": "image/png"}
        self.assertEqual(api._clean_profile_image(png)[0], b"\x89PNG\r\n\x1a\n")
        with patch.object(api, "MAX_PROFILE_IMAGE_BYTES", 1):
            with self.assertRaises(ValueError):
                api._clean_profile_image(png)
        self.assertEqual(api.MAX_PROFILE_IMAGE_BYTES, original)
        self.assertEqual(api._clean_profile_image(png)[0], b"\x89PNG\r\n\x1a\n")

    def test_threshold_compatibility_import_does_not_bootstrap_flask(self):
        result = subprocess.run(
            [sys.executable, "-c", (
                "import sys; from audio_thresholds import load_thresholds; "
                "assert load_thresholds()['algorithm_version']; "
                "assert 'karaok.application' not in sys.modules"
            )], cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_core_can_be_imported_without_bootstrapping_flask(self):
        result = subprocess.run(
            [sys.executable, "-c", (
                "import sys; from karaok.core import config, database, validation; "
                "assert 'karaok.application' not in sys.modules; "
                "assert config.BACKEND_DIR.name == 'backend'; "
                "assert validation.clean_text(' valid ', 'value', 1, 10) == 'valid'"
            )],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_routes_and_legacy_signatures_match_before_extraction(self):
        import app as api

        expected = json.loads((ROOT / "tests/fixtures/backend_contract.json").read_text())
        routes = sorted(
            [str(rule), sorted(rule.methods), rule.endpoint]
            for rule in api.app.url_map.iter_rules()
        )
        self.assertEqual(routes, expected["routes"])
        signatures = {
            name: str(inspect.signature(getattr(api, name)))
            for name in expected["signatures"]
        }
        self.assertEqual(signatures, expected["signatures"])
        self.assertEqual({
            name: str(inspect.signature(getattr(api, name).__init__))
            for name in expected["constructors"]
        }, expected["constructors"])
