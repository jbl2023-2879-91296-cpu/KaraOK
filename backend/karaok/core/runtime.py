"""Shared Flask instance and extensions; feature modules do not own startup."""

from flask import Flask
from werkzeug.middleware.proxy_fix import ProxyFix

from .config import MAX_AUDIO_BYTES, TRUST_PROXY
from .extensions import configure_extensions


app = Flask("karaok.application")
if TRUST_PROXY:
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
limiter = configure_extensions(app)
app.config["MAX_CONTENT_LENGTH"] = MAX_AUDIO_BYTES + (1024 * 1024)
