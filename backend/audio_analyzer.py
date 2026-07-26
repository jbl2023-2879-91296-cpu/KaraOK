"""Compatibility entry point for the packaged audio-analysis engine."""

import sys

from audio_engine import analyzer as _analyzer


if __name__ == "__main__":
    raise SystemExit(_analyzer.main())
else:
    sys.modules[__name__] = _analyzer
