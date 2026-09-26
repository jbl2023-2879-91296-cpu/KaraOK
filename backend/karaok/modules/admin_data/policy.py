"""Compatibility import for karaok.admin.data.policy."""
import sys
from karaok.admin.data import policy as _implementation
sys.modules[__name__] = _implementation
