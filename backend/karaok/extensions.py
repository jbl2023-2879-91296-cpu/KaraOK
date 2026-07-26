"""Flask extension initialization kept separate from business features."""

from flask import Flask
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

from .config import CORS_ORIGINS, RATELIMIT_STORAGE_URI


def configure_extensions(app: Flask) -> Limiter:
    CORS(app, resources={r"/api/*": {"origins": CORS_ORIGINS}})
    return Limiter(
        get_remote_address,
        app=app,
        storage_uri=RATELIMIT_STORAGE_URI,
        default_limits=["200 per hour"],
    )
