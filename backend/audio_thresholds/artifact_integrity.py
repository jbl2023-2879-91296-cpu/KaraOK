"""Compatibility import for karaok.core.thresholds.artifact_integrity."""
import sys
from importlib import import_module
sys.modules[__name__] = import_module("karaok.core.thresholds.artifact_integrity")
