"""Set test defaults before any test module imports the API."""

import os


os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")
