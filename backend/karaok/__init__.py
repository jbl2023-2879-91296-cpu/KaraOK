"""KaraOK backend application package."""

def create_app():
    """Return the configured Flask application.

    The factory-shaped entry point lets WSGI servers and tests avoid depending
    on the legacy top-level module.  A later configuration override can be
    applied directly to the returned Flask instance.
    """

    from .application import app

    return app


def __getattr__(name):
    if name == "app":
        return create_app()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = ["app", "create_app"]
