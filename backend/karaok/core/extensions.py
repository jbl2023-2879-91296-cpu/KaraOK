"""Flask extension initialization kept separate from business features."""

from flask import Flask, g
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

from .config import CORS_ORIGINS, RATELIMIT_STORAGE_URI


def configure_extensions(app: Flask) -> Limiter:
    CORS(app, resources={r"/api/*": {"origins": CORS_ORIGINS}})

    @app.after_request
    def preserve_auth_retry_after(response):
        # Flask-Limiter's headers run first and can substitute its own reset time.
        retry_after = getattr(g, "karaok_retry_after", None)
        if retry_after is not None:
            response.headers["Retry-After"] = str(retry_after)
        return response

    return Limiter(
        get_remote_address,
        app=app,
        storage_uri=RATELIMIT_STORAGE_URI,
        default_limits=["200 per hour"],
        headers_enabled=True,
        retry_after="delta-seconds",
    )
