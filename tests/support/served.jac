"""The copy of a module that a JacTestClient serves (JD-025).

JacTestClient loads the app's modules again under `_jac_app_<hash>.`, so a test that patches its own
import (for example the model an endpoint uses) changes nothing the client serves. This finds the
served copy, so a test can patch that one instead. Call it after the client's first request.
"""
import sys;
import types;

def served_module(name: str) -> types.ModuleType {
    matches = [
        module
        for (key, module) in sys.modules.items()
        if key.startswith("_jac_app_") and key.endswith("." + name)
    ];
    if len(matches) != 1 {
        raise LookupError(f"expected one served copy of {name}, found {len(matches)}");
    }
    return matches[0];
}
