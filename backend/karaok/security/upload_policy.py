"""Compatibility import for karaok.core.paths."""
import sys
from importlib import import_module
sys.modules[__name__] = import_module("karaok.core.paths")
