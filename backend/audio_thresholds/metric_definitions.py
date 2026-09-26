"""Compatibility import for karaok.core.thresholds.metric_definitions."""
import sys
from importlib import import_module
sys.modules[__name__] = import_module("karaok.core.thresholds.metric_definitions")
