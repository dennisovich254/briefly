# JD-023: The desktop window API has no always-on-top, second window, minimise/restore or window events

- **Version:** jaclang 0.39.0, Ubuntu 26.04 (GNOME), x86-64, desktop profile
- **Found:** 2026-11-04, phase 1 / 1.2 S1b
- **Category / severity:** Missing capability / Minor
- **Capability:** Native desktop host and window SDK
- **Status:** open
- **Related:** upstream #9951 (the same request from another team; closed as not planned 2026-10-21)
- **Cost:** 0.5 h; workaround: none needed for the MVP (the meeting window is a browser window, §5.3)
- **Canary:** none (a missing capability: upstream #9951 records it; re-check at each upgrade)

## Behaviour

`app_window` from `@jac/desktop` has four methods: `set_title`, `set_size`, `fullscreen` and `terminate` (all of which work, with JD-022's workaround). `[desktop.window]` takes `title`, `width`, `height`, `min_width`, `min_height` and `resizable`. There is no way to:

- keep the window above others (always-on-top);
- open a second window (the host creates exactly one webview);
- minimise, maximise or restore, read or set the position, or focus the window;
- learn about window events (focus, blur, minimise, resize, close-requested) in client code.

`fullscreen` is the page's `document.documentElement.requestFullscreen()` evaluated from the host, not native window fullscreen.

The native host is built on the C `webview` library, whose `libwebview.so` (shipped in the artifact) exports `webview_get_window` and `webview_get_native_handle`, returning the GTK window. Jac's binding (`webview.jac` in the artifact) does not expose them, so an app cannot reach the window from Jac either.

## Expected

Architecture §21.3 lists the window behaviours to evaluate: size, fullscreen, always-on-top, a second window, focus, close/restore, global shortcuts and capture exclusion. §3 already noted that the guide documents only title, size, fullscreen and termination.

## Repro

`jac guide jac-desktop-app` (the plugin table and `[desktop.window]`), the runtime's `client/targets/desktop/plugin/built_in/window_plugin.jac` (the four commands), and `nm -D libwebview.so` in the built artifact.

## Analysis

The same request (#9951, from a team moving an Electron app to Jac) was closed as not planned. For Briefly's MVP the gap is Minor: the default meeting surface is the phone companion (§5.2), and the laptop window modes use "a compact separate top-level window … In the MVP this is a separate browser window" (§5.3). It becomes Major if the meeting window moves into the desktop app, where it would need collapse, move and focus control.

## Workaround

None needed for the MVP: the phone companion is the default, and the laptop meeting window is a browser window (§5.3). If the meeting window moves into the desktop app: GTK calls through `ctypes` on the window `libwebview.so` returns, from the in-process server code (an OS-boundary adapter, behind a switch, citing this finding), or GNOME's own "Always on Top" window menu, by hand.

## Canary

None: a missing capability. Re-checked at each upgrade (§21.5) against the plugin's command list.

## Upstream issue draft

#9951 already describes the request and was closed as not planned. Draft for the owner, as a comment there or a narrower issue:

> Briefly (an Ubuntu desktop app on jac 0.39.0) would use `app_window.set_always_on_top` and focus control for a small meeting window. `libwebview.so` already exports `webview_get_window`; exposing it (or a few GTK calls behind `app_window`) would unblock always-on-top, minimise/restore and focus without a full window-chrome API.
