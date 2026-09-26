"""Compatibility import for karaok.admin.data.service."""
import sys
from karaok.admin.data import service as _implementation
sys.modules[__name__] = _implementation
