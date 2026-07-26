"""KaraOK backend application package."""

from .application import app


def create_app():
    """Return the configured Flask application.

    The factory-shaped entry point lets WSGI servers and tests avoid depending
    on the legacy top-level module.  A later configuration override can be
    applied directly to the returned Flask instance.
    """

    return app


__all__ = ["app", "create_app"]
