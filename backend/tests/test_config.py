import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


BACKEND_ROOT = Path(__file__).resolve().parents[1]


class ConfigTests(unittest.TestCase):
    def test_explicit_environment_file_is_loaded_instead_of_local_dotenv(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            environment_file = Path(temporary_directory) / "integration.env"
            environment_file.write_text(
                "SMTP_HOST=smtp.integration.invalid\n",
                encoding="utf-8",
            )
            environment = os.environ.copy()
            for name in (
                "SMTP_HOST",
                "SMTP_USERNAME",
                "SMTP_PASSWORD",
                "SMTP_FROM",
            ):
                environment.pop(name, None)
            environment["KARAOK_ENV_FILE"] = str(environment_file)

            result = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    (
                        "from karaok.config import SMTP_HOST; "
                        "raise SystemExit(0 if SMTP_HOST == "
                        "'smtp.integration.invalid' else 3)"
                    ),
                ],
                cwd=BACKEND_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(
                result.returncode,
                0,
                "backend configuration ignored the explicit environment file",
            )

    def test_normal_smtp_environment_remains_available_without_override(self):
        environment = os.environ.copy()
        environment.pop("KARAOK_ENV_FILE", None)
        environment.update(
            {
                "SMTP_HOST": "smtp.normal.invalid",
                "SMTP_USERNAME": "normal-user",
                "SMTP_PASSWORD": "normal-password",
                "SMTP_FROM": "normal@example.invalid",
            }
        )

        result = subprocess.run(
            [
                sys.executable,
                "-c",
                (
                    "from karaok.config import (SMTP_HOST, SMTP_USERNAME, "
                    "SMTP_PASSWORD, SMTP_FROM); expected = "
                    "('smtp.normal.invalid', 'normal-user', "
                    "'normal-password', 'normal@example.invalid'); "
                    "raise SystemExit(0 if (SMTP_HOST, SMTP_USERNAME, "
                    "SMTP_PASSWORD, SMTP_FROM) == expected else 3)"
                ),
            ],
            cwd=BACKEND_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(
            result.returncode,
            0,
            "normal SMTP environment configuration no longer reaches the app",
        )


if __name__ == "__main__":
    unittest.main()
