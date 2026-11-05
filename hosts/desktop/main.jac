"""Desktop profile: the shared UI in the native Jac window, server embedded (architecture §6.1)."""

import from ui.App { App }
# The answer stream has no client RPC stub, so it registers through this entry-module import
# (jac-sv-streaming, "Registration").
import from core.ai.answer { answer_cancel, answer_stream }

def:pub app -> JsxElement {
    <App profile="desktop"/>
}
