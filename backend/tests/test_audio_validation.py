import os
import tempfile
import unittest
import wave

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api


class AudioValidationTests(unittest.TestCase):
    def test_valid_wav_duration_is_read_from_file(self):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp:
            path = temp.name
        try:
            with wave.open(path, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(8000)
                wav.writeframes(b"\x00\x00" * 16000)
            self.assertEqual(api.audio_duration_seconds(path), 2)
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


if __name__ == "__main__":
    unittest.main()
