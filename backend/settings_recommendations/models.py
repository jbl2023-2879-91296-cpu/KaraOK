"""Compatibility import for shared recommendation value objects."""
import sys
from karaok.core import recommendation_models as _models
sys.modules[__name__] = _models
