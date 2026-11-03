# JD-003: In a workspace, the desktop build appends another app's name to `[desktop] identifier`

- **Version:** jaclang 0.39.0, Ubuntu 26.04, desktop profile
- **Found:** 2026-11-03, phase 0 / 0.3 scaffold
- **Category / severity:** Defect / Minor
- **Capability:** Native desktop host and window SDK
- **Status:** open
- **Related:** none
- **Cost:** 0.5 h; no workaround code
- **Canary:** bench/jd_003_desktop_identifier_suffix.sh

## Behaviour

In a workspace with a `desktop` app and a `web-app` app, `jac build desktop` generates a host (`.jac/client/desktop/desktop/host.jac`) that boots with `identifier = "<[desktop] identifier>.<web app name>"`. Briefly's desktop app, built from `[apps.desktop]` with `identifier = "io.github.dennisovich254.briefly"`, keeps its graph and embedded PostgreSQL under:

```text
~/.local/share/io.github.dennisovich254.briefly.lean/   # ".lean" is the *other* app's name
```

Renaming the web app to `zzz` in a minimal workspace gives `org.example.repro.zzz`, so the suffix follows the web app, not the desktop app being built.

## Expected

`jac guide jac-desktop-app`: "App state (graph, session) lives in a per-user, per-app directory: `$XDG_DATA_HOME/<identifier>` (or `~/.local/share/<identifier>`) on Linux". Either the identifier as configured, or, if a per-app suffix is intended in a workspace, the desktop app's own name (`.desktop`).

## Repro

`~/jac-repros/JD-003/proj/` (the canary builds the same workspace in a temp directory):

```toml
[apps.desktop]
kind = "desktop"
entry-point = "hosts.desktop.main"

[apps.zzz]
kind = "web-app"
entry-point = "main"

[desktop]
identifier = "org.example.repro"
```

`jac build desktop`, then `grep -o 'identifier[^,]*' .jac/client/desktop/desktop/host.jac` shows `org.example.repro.zzz`.

## Analysis

The desktop app has an embedded backend; in a workspace the server app it embeds appears to be the `web-app`, and its name is used for the per-app data identity. The effect is a misleading data-directory name, and moving or renaming the web app would move the desktop app's data. Not investigated further in 0.3.

## Workaround

None needed yet: the data stays in a per-user directory. Release notes and the onboarding/retention docs must name the real path while this holds.

## Canary

`bench/jd_003_desktop_identifier_suffix.sh`: exit 0 while the identifier ends in the web app's name. Needs the desktop build packages; run on each compiler upgrade (§21.5).

## Upstream issue draft

(For the owner to review before posting; search for an existing issue first.)

> **Desktop app in a workspace uses another app's name in its identifier / data directory**
>
> jac 0.39.0. Workspace with `[apps.desktop] kind = "desktop"`, `[apps.zzz] kind = "web-app"`, `[desktop] identifier = "org.example.repro"`. `jac build desktop` generates a host that boots with `identifier = "org.example.repro.zzz"`, so the desktop app's graph and Postgres live in `~/.local/share/org.example.repro.zzz`. Expected `org.example.repro` (as the desktop guide says) or a suffix naming the desktop app itself.
