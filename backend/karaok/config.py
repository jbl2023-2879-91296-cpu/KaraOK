"""Compatibility import for karaok.core.config."""

import sys
from importlib import import_module

sys.modules[__name__] = import_module("karaok.core.config")
