# JD-038: `jac run lean` puts the dev server, which proxies the whole API, on every interface; `[serve] host` and `--host 127.0.0.1` do not reach it

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, lean profile in dev mode (`jac run lean`)
- **Found:** 2026-11-05, phase 1 / 1.5 S7 (the owner's first phone test answered "not found")
- **Category / severity:** Defect / Major
- **Capability:** Several clients of one app
- **Status:** open
- **Related:** JD-035 (no session-scoped LAN listener); upstream searched 2026-11-05: no matching issue
- **Cost:** 1.5 h; workaround: run the built lean app (`jac build lean && jac run dist/briefly.jab`) whenever the laptop is on a network others share, and for the phone link
- **Canary:** bench/jd_038_dev_server_on_every_interface.sh

## Behaviour

`jac run lean` is dev mode for a web app (`jac run --show lean`: "equivalent: jac run lean --dev"). It starts the Jac API server on `127.0.0.1:8001`, as `[serve] host` says, and Vite on port 8000, which serves the page and proxies the API routes to it. Vite listens on `*:8000`. From the laptop's Wi-Fi address, `/` 200, `/docs` 200, `/graph` 200, `POST /function/app_info` 200, and `/user/register` validates the body (422 for `{}`): the whole app, registration included, is on the network.

`jac run lean --host 127.0.0.1` changes nothing for Vite (still `*:<port>`). The cause is in `vite_bundler.impl.jac`: for a web app the generated config sets `host: true`, and `_build_vite_dev_command` appends a bare `--host` (all interfaces) whenever no host is passed; the web target and `jac run` call `start_dev_server` without one. Only the desktop dev path passes `127.0.0.1`.

In dev mode the Jac server itself serves no page: `GET /phone` on it answers 404 `"in dev the client is served by the dev server on the web port"`, also with `--no-dev`. So the phone gate, which forwards to the Jac server, had no page to give the phone.

## Expected

`jac run --help`: "`--host HOST` Interface to bind (serving only; default [serve] host, 0.0.0.0). Use 127.0.0.1 to keep a dev server off the network." The dev server should bind the `--host` / `[serve] host` address, as the desktop dev path already does.

## Repro

In any web-app project with `[serve] host = "127.0.0.1"`: `jac run --host 127.0.0.1` (dev mode), then `ss -ltn` shows the API on `127.0.0.1:<api>` and Vite on `*:<web>`; `curl http://<lan-ip>:<web>/docs` answers 200 from another machine.

## Analysis

The dev server is how a developer runs the app every day, often on shared Wi-Fi. With registration open and the API proxied, anyone on that network can create an account and call the app's authenticated endpoints; for Briefly that includes `answer_stream`, which spends the owner's Claude budget. Nothing in the project's configuration can prevent it, and the documented flag says it does.

## Workaround

Do not use dev mode on a shared network: run the built lean app (`jac build lean && jac run dist/briefly.jab`), which serves the page from the Jac server on `127.0.0.1` (checked by `scripts/smoke_lean.sh`), or the desktop app. `bench/phone_link.jac` refuses to start against the dev server and says so.

## Canary

`bench/jd_038_dev_server_on_every_interface.sh`: starts `jac run lean --host 127.0.0.1` and exits 0 while Vite still listens on every interface.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac run --dev` binds Vite (which proxies the whole API) on all interfaces; `--host 127.0.0.1` and `[serve] host` are ignored for it**
>
> jac 0.39.1, web app. `jac run --host 127.0.0.1` (dev mode) puts the API on `127.0.0.1:<api>` but Vite on `*:<web>`, and Vite proxies `/function`, `/user`, `/docs`, `/graph`… to the API, so the whole app (registration included) is reachable from the network. `vite_bundler.impl.jac` sets `host: true` for non-desktop dev and `_build_vite_dev_command` appends a bare `--host` when none is passed; `jac run` and the web target never pass one. `--help` says `--host 127.0.0.1` keeps a dev server off the network. Suggest passing the resolved serve host to `start_dev_server`, as the desktop dev path does with `127.0.0.1`.
