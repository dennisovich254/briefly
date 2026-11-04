# JD-022: Without a `[desktop.plugins]` table, every `app_window` call fails with "Plugin 'jac.window' is not registered"

- **Version:** jaclang 0.39.0, Ubuntu 26.04 (GNOME, Wayland with XWayland), x86-64, desktop profile
- **Found:** 2026-11-04, phase 1 / 1.2 S1b (first seen in 0.3)
- **Category / severity:** Defect / Minor
- **Capability:** Native desktop host and window SDK
- **Status:** open
- **Related:** upstream searched 2026-11-04: no matching issue
- **Cost:** 1 h (in 0.3 the error was taken for a mistake in a hand-written call); workaround `[desktop.plugins] window = true` in `jac.toml` (2 lines)
- **Canary:** bench/jd_022_window_plugin_not_registered.sh

## Behaviour

`bench/window_sdk.sh` builds a fresh `jac create --kind desktop` app whose page calls `app_window.set_title`, `set_size`, `fullscreen` and `terminate` from `@jac/desktop`:

| `jac.toml` | Result |
|---|---|
| no `[desktop.plugins]` table (the scaffold's default) | every call throws `Plugin 'jac.window' is not registered`; the window keeps its title and size, and `terminate` does not close the app |
| `[desktop.plugins]` with `window = true` | all four work: the title changes, the window resizes to exactly 700x500, `fullscreen` fills the 1366x768 screen, `terminate` closes the app and its PostgreSQL stops |

## Expected

`jac guide jac-desktop-app`, "Security gating": "**`window`, `path`, `notification`, `dialog` are enabled by default**; `shell` is deny-all by default." So the default configuration should register `jac.window`.

## Repro

`bench/window_sdk.sh` (default) and `WINDOW_PLUGIN=explicit bench/window_sdk.sh`. The generated `main.jac` is in the script.

## Analysis

The defaults appear to apply only when a `[desktop.plugins]` table exists; with no table at all the host is built with `"plugins": {}` (seen in 0.3's generated host config), so nothing is registered. Only `window` was checked; `path`, `notification` and `dialog` are probably affected the same way.

## Workaround

Briefly's `jac.toml` has `[desktop.plugins] window = true`, with a comment citing JD-022.

## Canary

`bench/jd_022_window_plugin_not_registered.sh`: runs `bench/window_sdk.sh` in the default configuration and exits 0 while the calls fail with "not registered". Mutation-checked: the explicit configuration passes every check.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop: default plugins aren't registered unless `[desktop.plugins]` exists; `app_window.*` throws "Plugin 'jac.window' is not registered"**
>
> jac 0.39.0, Linux. In a fresh `jac create --kind desktop` project, `await app_window.set_title("x")` (and `set_size`, `fullscreen`, `terminate`) throws `Plugin 'jac.window' is not registered`. Adding `[desktop.plugins]\nwindow = true` makes all four work. The desktop guide says `window`, `path`, `notification` and `dialog` are enabled by default.
