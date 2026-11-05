# JD-030: The desktop bridge has `window.__jac.on(event, …)`, but app code has no way to emit an event to it

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, desktop profile
- **Found:** 2026-11-05, phase 1 / 1.4 S4
- **Category / severity:** Missing capability / Minor
- **Capability:** Real-time delivery (host events, WebSockets, streams)
- **Status:** open
- **Related:** JD-014 (no targeted WebSocket send); upstream #6566 (the plugin IPC feature, closed); upstream searched 2026-11-05: no matching issue
- **Cost:** 0.5 h; workaround: the authenticated response stream (SSE), which §11.3 lists third
- **Canary:** none (a missing capability; re-checked at each upgrade against the runtime's `PluginHost`)

## Behaviour

The desktop host injects `window.__jac.invoke(plugin, command, args)` and `window.__jac.on(event, callback)` into the page (the `jac-desktop` reference, "OS capabilities"). The runtime has a `PluginHost.emit(event, payload)` (`client/targets/desktop/plugin/plugin_host.jac`) that evaluates `window.__jac.__emit__(event, payload)` in the webview, but nothing calls it, no SDK or server API exposes it, and the plugin base class (`desktop_plugin.jac`) gives a plugin no handle to it. So the page can listen for host events that app code can never send.

## Expected

Architecture §11.3 puts "native desktop-host events" first among the delivery mechanisms for streamed answers. A documented way for server code in the desktop app (which runs in-process) to emit an event to its window would provide it.

## Repro

`grep -rn "\.emit(" <runtime>/site/jaclang/client/targets/desktop/` finds no caller of `PluginHost.emit`; the desktop guide and the `jac-desktop` reference document `on` but no emitter.

## Analysis

The capability is half-built: the listening side and the low-level push exist. For Briefly it costs little, because the response stream works for both the desktop window and the phone, and §11.3 keeps one mechanism for both.

## Workaround

Answers stream as an authenticated Jac response stream (`answer_stream`, SSE).

## Canary

None: re-checked at each upgrade by looking for a public emitter.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop: `window.__jac.on(event, cb)` has no emitter reachable from app code**
>
> jac 0.39.1. The desktop bridge lets the page subscribe with `window.__jac.on`, and `PluginHost.emit` can push `window.__jac.__emit__(event, payload)` into the webview, but nothing calls `emit` and no API exposes it to the app's (in-process) server code or to plugins. Suggest an `emit_host_event(event, payload)` for server code in desktop apps, which would give streamed output a native path.
