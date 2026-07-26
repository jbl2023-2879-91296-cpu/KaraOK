"""Development server entry point for the packaged KaraOK API."""

import os

from karaok.application import JWT_SECRET
from karaok import create_app


if __name__ == "__main__":
    if not JWT_SECRET or len(JWT_SECRET) < 32:
        raise RuntimeError(
            "JWT_SECRET must be set to a random value of at least 32 characters"
        )
    create_app().run(
        host=os.getenv("APP_HOST", "127.0.0.1"),
        port=int(os.getenv("APP_PORT", "5000")),
        debug=os.getenv("FLASK_DEBUG", "false").lower() == "true",
    )
