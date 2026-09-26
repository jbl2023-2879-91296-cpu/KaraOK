"""Compatibility import for karaok.core.validation."""

import sys
from importlib import import_module

sys.modules[__name__] = import_module("karaok.core.validation")
