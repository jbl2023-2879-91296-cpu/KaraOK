"""Compatibility import for karaok.admin.data.reports."""
import sys
from karaok.admin.data import reports as _implementation
sys.modules[__name__] = _implementation
