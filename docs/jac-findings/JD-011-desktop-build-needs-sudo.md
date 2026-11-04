# JD-011: The desktop build installs system packages with sudo, and without them ends in a traceback that does not name them

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, desktop profile
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (re-test of JI-005; the traceback was noted in 0.3)
- **Category / severity:** Packaging/install / Minor
- **Capability:** Build and packaging (`jac build`)
- **Status:** open
- **Related:** JI-005 (AfriCinemas), still holding on 0.39.0; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: install the packages once (`sudo apt-get install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`), and the same line in CI
- **Canary:** bench/jd_011_desktop_build_needs_sudo.sh

## Behaviour

On a machine without the WebKitGTK development packages, `jac build` of a desktop app builds the client bundle, prints `Updating system package index (administrator access required)`, and runs `/usr/bin/sudo -n /usr/bin/apt-get update` itself. Without passwordless sudo, it ends with:

```
sudo: interactive authentication is required
✖ Error: Build failed: Command '['/usr/bin/sudo', '-n', '/usr/bin/apt-get', 'update']' returned non-zero exit status 1.
Traceback (most recent call last):
  ... 10 frames through desktop_target, webview_shell, toolchains/system ...
subprocess.CalledProcessError: Command '['/usr/bin/sudo', '-n', '/usr/bin/apt-get', 'update']' returned non-zero exit status 1.
```

The output never says which packages are missing or which command to run, so the developer has to read Jac's source (`toolchains/impl/system.impl.jac`, `install_linux_packages`) to find out.

## Expected

The build stops with the missing packages and the exact command to install them (`sudo apt-get install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`), and no traceback. A build tool installing system packages with sudo, unasked, is also surprising; asking first, or only printing the command, would be safer.

## Repro

`~/jac-repros/JD-011/`: a fresh `jac create d --kind desktop`, then `jac build` with a `pkg-config` that always fails first on `PATH` (simulating the missing packages on a machine that has them). Full output in `build-nopkg.log`.

## Analysis

JI-005 holds: the desktop target needs root once per machine. The traceback makes it look like a crash rather than a missing prerequisite, which matters for the clean-machine install in 1.3 and for anyone following `CONTRIBUTING.md`.

## Workaround

`CONTRIBUTING.md` (setup step 4) and the CI `build-desktop` job install the packages first. `scripts/doctor.sh` could check them; noted for 1.3.

## Canary

`bench/jd_011_desktop_build_needs_sudo.sh`: the repro above; exit 0 while the build reaches for sudo and ends in a traceback without the package names. Mutation-checked: with the real `pkg-config`, the build succeeds and the canary exits 1.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop build without WebKitGTK dev packages runs `sudo apt-get` itself, then dies in a traceback that never names the packages**
>
> jac 0.39.0, Ubuntu x86-64. On a machine without `libwebkit2gtk-4.1-dev` (simulated with a failing `pkg-config` first on PATH), `jac build` of a `--kind desktop` project runs `sudo -n apt-get update`; without passwordless sudo it fails with a 10-frame Python traceback ending in `CalledProcessError`. Expected: a one-line error naming the missing packages and the install command (`sudo apt-get install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`), and no unasked sudo.
