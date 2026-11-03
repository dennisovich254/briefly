"""Desktop profile: the shared UI in the native Jac window, server embedded (architecture §6.1)."""

import from ui.App { App }

def:pub app -> JsxElement {
    <App profile="desktop"/>
}
