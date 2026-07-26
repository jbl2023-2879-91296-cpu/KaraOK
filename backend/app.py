"""Backward-compatible KaraOK API entry point.

Application code lives in the :mod:`karaok` package.  Replacing this module in
``sys.modules`` intentionally preserves the historical ``import app as api``
contract used by scripts and tests, including their ability to patch module
dependencies during isolated tests.
"""

import os
import sys

from karaok import application as _application


if __name__ == "__main__":
    if not _application.JWT_SECRET or len(_application.JWT_SECRET) < 32:
        raise RuntimeError(
            "JWT_SECRET must be set to a random value of at least 32 characters"
        )
    _application.app.run(
        host=os.getenv("APP_HOST", "127.0.0.1"),
        port=int(os.getenv("APP_PORT", "5000")),
        debug=os.getenv("FLASK_DEBUG", "false").lower() == "true",
    )
else:
    sys.modules[__name__] = _application
