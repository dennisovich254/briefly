# JD-026: The desktop artifact is a bare directory that needs `libwebkit2gtk-4.1-0` installed by root, and nothing says so

- **Version:** jaclang 0.39.0; artifact built on GitHub's `ubuntu-latest` runner, installed in a fresh `ubuntu:24.04` container; desktop profile
- **Found:** 2026-11-04, phase 1 / 1.3 S1a
- **Category / severity:** Packaging/install / Minor
- **Capability:** Build and packaging (`jac build`)
- **Status:** open
- **Related:** JD-011 (the build side of the same packages); the desktop guide's "per-OS packaging/signing (phase 5)" note and upstream #6436; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: document the runtime package (`CONTRIBUTING.md`, the release notes); a `.deb` later
- **Canary:** none (recorded on every PR by the clean-install CI job, whose report lists what a clean system lacks)

## Behaviour

`jac build desktop` produces a directory (`.jac/client/desktop/desktop/`: the `briefly` binary, `libwebview.so`, `app.jab`, `dist/`, a bundled PostgreSQL in `pgdist/`, and a launcher). It is 260 MB unpacked, 180 MB as a `.tar.gz`. On a fresh Ubuntu 24.04 (92 packages) it does not start: `ldd` reports `libgtk-3.so.0`, `libgdk-3.so.0`, `libglib-2.0.so.0`, `libgobject-2.0.so.0`, `libwebkit2gtk-4.1.so.0` and `libjavascriptcoregtk-4.1.so.0` missing. Installing `libwebkit2gtk-4.1-0` (158 dependencies, as root) resolves them all; after that the app runs as an ordinary user, keeps its graph across restarts and starts with no network (`bench/install_check.sh`, the `clean-install` job).

The artifact declares none of this: there is no package metadata, the launcher does not check, and the desktop guide says only "Ship the whole directory" and that the app uses "the OS's own web engine".

Two smaller observations from the same run:

- The bundled PostgreSQL carries its optional modules (PL/Perl, PL/Python linked against Python 3.6, PL/Tcl, `postgres_fdw`, `file_fdw`, ecpg), whose libraries are absent on a clean system. The app never loads them, and they are 6.2 MB of the 123 MB `pgdist/`.
- The launcher (`briefly-launch.sh`) adds `../../../venv/lib/python*/site-packages` to `JAC_DESKTOP_DEPS`: in the build tree that is the project's own `.jac/venv`. Installed elsewhere the path does not exist and is skipped; the app does not need it today, but a build tested only in place can depend on the development environment without anyone noticing.

## Expected

Either a package (`.deb`) that declares `libwebkit2gtk-4.1-0`, or at least the desktop guide's output section naming the runtime packages per distribution, and a launcher that says what is missing instead of failing to load a library.

## Repro

The `clean-install` job in `.github/workflows/ci.yml`: `bench/install_check.sh install` in `ubuntu:24.04` lists the missing libraries before and after installing `libwebkit2gtk-4.1-0`.

## Analysis

Packaging per OS is on Jac's roadmap (the guide's "In progress" note). Until then every Jac desktop app shares this gap: the artifact works on a developer's machine, which has the build packages, and fails on a user's until they install a package they have no way to know about.

## Workaround

Document it: `CONTRIBUTING.md` and Briefly's install notes name `libwebkit2gtk-4.1-0`. A `.deb` with the dependency is a candidate for phase 8 (release).

## Canary

None as a test: the `clean-install` job reports the missing libraries on every PR, so a change shows up in its summary.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop artifact: document (or declare) the runtime packages; a clean Ubuntu 24.04 needs `libwebkit2gtk-4.1-0`**
>
> jac 0.39.0. The directory `jac build` produces for a `kind = "desktop"` app does not start on a fresh Ubuntu 24.04: GTK 3 and WebKitGTK 4.1 are missing. `apt-get install libwebkit2gtk-4.1-0` (158 dependencies) fixes it. The desktop guide says "Ship the whole directory" but doesn't name the runtime packages. Suggest listing them in the guide's output section and having the launcher report a missing library by package name, until per-OS packaging lands. Also: the bundled Postgres ships PL/Python (linked against Python 3.6), PL/Perl and PL/Tcl, which can't load on a clean system and aren't needed.
