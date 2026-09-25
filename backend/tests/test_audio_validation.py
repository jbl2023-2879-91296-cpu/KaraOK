import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import wave

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api


class AudioValidationTests(unittest.TestCase):
    def setUp(self):
        self.previous_testing = api.app.config.get("TESTING", False)
        api.app.config["TESTING"] = True
        self.client = api.app.test_client()
        token, _ = api.issue_access_token(
            {"user_id": 7, "user_type": "user"}
        )
        self.headers = {"Authorization": f"Bearer {token}"}

    def tearDown(self):
        api.app.config["TESTING"] = self.previous_testing

    def _post_authenticated_audio(self, extension, audio_bytes=b"MThd"):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.side_effect = [
            None,
            {
                "role": "user",
                "is_active": True,
                "email_verified_at": "2026-09-03T00:00:00Z",
                "security_updated_at_epoch": None,
                "requires_password_change": False,
            },
        ]
        with patch.object(api, "get_db", return_value=connection), patch.object(
            api, "audit"
        ):
            return self.client.post(
                "/api/audio-uploads",
                data={
                    "audio": (
                        io.BytesIO(audio_bytes),
                        f"sample.{extension}",
                    ),
                    "duration_seconds": "20",
                },
                headers=self.headers,
                content_type="multipart/form-data",
            )

    def test_symbolic_midi_uploads_explain_that_rendered_audio_is_required(self):
        message = (
            "MIDI event files are not rendered audio. Record the karaoke machine "
            "playback or select WAV, MP3, M4A, AAC, OGG, or FLAC."
        )
        for extension in ("mid", "midi"):
            for path in ("/api/guest/audio-analysis", "/api/audio-uploads"):
                with self.subTest(extension=extension, path=path):
                    response = (
                        self.client.post(
                            path,
                            data={
                                "audio": (
                                    io.BytesIO(b"MThd"),
                                    f"sample.{extension}",
                                )
                            },
                            content_type="multipart/form-data",
                        )
                        if path == "/api/guest/audio-analysis"
                        else self._post_authenticated_audio(extension)
                    )
                    self.assertEqual(response.status_code, 400)
                    self.assertEqual(response.get_json()["error"], message)

    def test_unrelated_extension_retains_generic_rejection(self):
        response = self._post_authenticated_audio("txt")
        self.assertEqual(response.status_code, 415)
        self.assertEqual(response.get_json()["error"], "Unsupported audio format")

    def test_short_upload_rejected_with_duration_guidance_for_guest_and_user(self):
        audio = io.BytesIO()
        with wave.open(audio, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(8000)
            wav.writeframes(b"\x00\x00" * 8000)
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            api, "AUDIO_UPLOAD_DIR", os.path.abspath(temporary)
        ), patch.object(api, "run_audio_analyzer") as analyzer:
            for guest in (True, False):
                with self.subTest(guest=guest):
                    response = self.client.post(
                        "/api/guest/audio-analysis",
                        data={"audio": (io.BytesIO(audio.getvalue()), "short.wav"),
                              "duration_seconds": "20"},
                        content_type="multipart/form-data",
                    ) if guest else self._post_authenticated_audio("wav", audio.getvalue())
                    self.assertEqual(response.status_code, 422)
                    self.assertEqual(response.get_json()["error"],
                                     "Audio duration must be between 10 and 300 seconds")
            analyzer.assert_not_called()
            self.assertEqual(list(Path(temporary).rglob("*.wav")), [])

    def test_valid_wav_duration_is_read_from_file(self):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp:
            path = temp.name
        try:
            with wave.open(path, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(8000)
                wav.writeframes(b"\x00\x00" * 80000)
            self.assertEqual(api.audio_duration_seconds(path), 10)
        finally:
            os.remove(path)

    def test_corrupted_audio_is_rejected(self):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp:
            temp.write(b"not audio")
            path = temp.name
        try:
            with self.assertRaises(ValueError):
                api.audio_duration_seconds(path)
        finally:
            os.remove(path)

    def test_duration_limits_are_checked_before_rounding(self):
        for seconds in (0, 1, 9.99, 300.01, float("nan"), float("inf")):
            with self.subTest(seconds=seconds):
                info = MagicMock()
                info.info.length = seconds
                with patch.object(api, "MutagenFile", return_value=info):
                    with self.assertRaises(ValueError):
                        api.audio_duration_seconds("recording.wav")
        for seconds, expected in ((10, 10), (20.2, 20), (300, 300)):
            with self.subTest(seconds=seconds):
                info = MagicMock()
                info.info.length = seconds
                with patch.object(api, "MutagenFile", return_value=info):
                    self.assertEqual(api.audio_duration_seconds("recording.wav"), expected)

    def test_deleted_assessment_cleans_upload_and_analysis_artifacts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            upload_root = root / "uploads"
            analysis_root = root / "analysis"
            upload_path = upload_root / "7" / "recording.wav"
            analysis_path = analysis_root / "7" / "11"
            upload_path.parent.mkdir(parents=True)
            analysis_path.mkdir(parents=True)
            upload_path.write_bytes(b"audio")
            (analysis_path / "analysis_dump.json").write_text(
                "{}", encoding="utf-8"
            )

            with patch.object(
                api, "AUDIO_UPLOAD_DIR", str(upload_root)
            ), patch.object(
                api, "ANALYSIS_OUTPUT_DIR", str(analysis_root)
            ):
                api.cleanup_audio_artifacts(7, 11, str(upload_path))

            self.assertFalse(upload_path.exists())
            self.assertFalse(analysis_path.exists())

    def test_cleanup_rejects_upload_path_outside_configured_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            upload_root = root / "uploads"
            outside = root / "outside.wav"
            outside.write_bytes(b"keep")
            with patch.object(
                api, "AUDIO_UPLOAD_DIR", str(upload_root)
            ), patch.object(
                api, "ANALYSIS_OUTPUT_DIR", str(root / "analysis")
            ):
                with self.assertRaises(RuntimeError):
                    api.cleanup_audio_artifacts(7, 11, str(outside))
            self.assertTrue(outside.exists())


if __name__ == "__main__":
    unittest.main()
