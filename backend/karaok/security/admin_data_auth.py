"""Compatibility import for admin data authorization."""
import sys
from karaok.auth import admin_data as _implementation
sys.modules[__name__] = _implementation
