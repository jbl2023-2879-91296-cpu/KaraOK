"""Compatibility import for karaok.core.thresholds.control_priors."""
import sys
from importlib import import_module
sys.modules[__name__] = import_module("karaok.core.thresholds.control_priors")
