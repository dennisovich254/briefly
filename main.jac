"""Lean profile: the shared UI served by `jac run lean` in an existing browser (architecture §6.1).

This entry sits at the project root, not in hosts/lean/, because JacTestClient cannot serve a
nested entry (JD-002). Move it back once the JD-002 canary shows the fix.
"""

import from ui.App { App }

def:pub app -> JsxElement {
    <App profile="lean"/>
}
