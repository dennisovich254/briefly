"""Desktop profile: the shared UI in the native Jac window, server embedded (architecture §6.1)."""

import from ui.App { App }
# The answer stream has no client RPC stub, so it registers through this entry-module import
# (jac-sv-streaming, "Registration").
import from core.ai.answer { answer_cancel, answer_stream }
# The phone link's endpoints (§5.6): the laptop's controls have no UI yet and the feed is a stream.
import from core.phone.link {
    phone_feed,
    phone_new_code,
    phone_push,
    phone_start,
    phone_status,
    phone_stop
}

def:pub app -> JsxElement {
    <App profile="desktop"/>
}
