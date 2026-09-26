"""Keep legacy module attribute overrides connected to extracted consumers.

Business modules import their actual dependencies. Only compatibility entry
points use this adapter: historical callers can still replace e.g. ``app.get_db``
without requiring the implementation to import the application backwards.
"""

import sys
from types import ModuleType


class _LegacyModule(ModuleType):
    def __setattr__(self, name, value):
        for module in self.__dict__.get("_legacy_consumers", {}).get(name, ()):
            ModuleType.__setattr__(module, name, value)
        ModuleType.__setattr__(self, name, value)


def connect_legacy_overrides(module):
    """Bind already imported, identically named dependencies to this facade."""
    consumers = {}
    modules = tuple(sys.modules.values())
    for name, value in tuple(vars(module).items()):
        if name.startswith("__"):
            continue
        matches = []
        for candidate in modules:
            if (
                isinstance(candidate, ModuleType)
                and candidate is not module
                and candidate.__name__.startswith("karaok.")
                and name in vars(candidate)
                and vars(candidate)[name] is value
            ):
                matches.append(candidate)
        if matches:
            consumers[name] = tuple(matches)
    module._legacy_consumers = consumers
    module.__class__ = _LegacyModule
