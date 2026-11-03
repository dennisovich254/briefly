# JD-001: `jac install` ignores `JAC_BUN` and always runs the bundled bun

- **Version:** jaclang 0.39.0 (also 0.38.3), Ubuntu 26.04, x86-64 Intel Celeron N4020 (no AVX2), both profiles
- **Found:** 2026-11-03, phase 0 / 0.3 scaffold
- **Category / severity:** Defect / Major
- **Capability:** Build and packaging (`jac build`)
- **Status:** open
- **Related:** JI-002 (bundled bun needs AVX2); Jac's own docs, `reference/plugins/jac-client.md`
- **Cost:** 1.5 h; workaround `scripts/swap_bundled_bun.sh` (45 lines) and a doctor check
- **Canary:** bench/jd_001_jac_bun_ignored.sh

## Behaviour

`jac install` (and so `jac create`, which runs it) installs npm dependencies with the bun bundled inside the Jac runtime (`<runtime>/site/jaclang/client/_bun/bun`), whatever `JAC_BUN` says. A bun first on `PATH` is not used either. On a CPU without AVX2 the bundled bun dies with `Illegal instruction` (exit 132, JI-002), so no client project (`web-app`, `desktop`) can install its dependencies:

```text
✖ Dependency installation failed after 1.5s
✗ npm dependencies failed: Failed to install packages: Failed to install dependencies
```

The 0.39.0 artifact router reads no environment override for bun (`jaclang/client/impl/js_runtime.impl.jac` probes only the sealed, checkout and kit copies; the only variable `jaclang/artifacts/` reads is `JAC_KIT_OMIT`).

## Expected

The bundled 0.39.0 reference says: "all JS tooling (installs, Expo/Metro, Vite) runs on the Bun runtime bundled with the `jac` binary (`JAC_BUN` overrides which bun is used)" and "Set `JAC_BUN` to substitute a specific bun binary" (`jac guide reference/plugins/jac-client`). AfriCinemas' JI-002 recorded `JAC_BUN` as a working workaround on 0.37.18.

## Repro

`~/jac-repros/JD-001/repro.sh`, the same script as the canary. It works on any CPU because it only checks whether the bun named by `JAC_BUN` is called:

```bash
work="$(mktemp -d)"; mkdir -p "$work/wrap"
cat > "$work/wrap/bun" <<WRAP
#!/usr/bin/env bash
echo "called: \$*" >> "$work/calls.log"
exec "$(command -v bun)" "\$@"
WRAP
chmod +x "$work/wrap/bun"
cd "$work" && jac create app --kind web-app --skip && cd app
JAC_BUN="$work/wrap/bun" jac install
test -s "$work/calls.log" || echo "JAC_BUN was never called"
```

On 0.39.0: install fails (on this CPU) and the wrapper is never called. On 0.38.3: install succeeds only because that runtime's bundled bun had already been swapped by hand (AfriCinemas' JI-002 workaround), and the wrapper is still never called.

## Analysis

The override seems to have been lost when bun became a probed artifact (`BunArtifact`: sealed, checkout, kit). `JAC_BUN` is still documented but no longer read. On AVX2 machines (CI runners, most laptops) nobody notices; on older CPUs every client build fails, and the error (JD-002 candidate: no cause shown, even with `-v`) gives no hint.

## Workaround

`scripts/swap_bundled_bun.sh` replaces the active runtime's bundled bun with bun's `linux-x64-baseline` build of the same version (1.3.11), keeping the original as `bun.avx2-original`. `_probe_bun` accepts it because it trusts the recorded version in `bun.artifact.json`. Needed once per Jac release (each extracts a new runtime). `scripts/doctor.sh` checks the runtime's own bun and points at the script. No product code is affected, so there is no switch.

## Canary

`bench/jd_001_jac_bun_ignored.sh`: exit 0 while `JAC_BUN` is ignored, exit 1 once it is honoured. Needs network for `jac install`; run it on each compiler upgrade (§21.5).

## Upstream issue draft

(For the owner to review before posting; search for an existing issue first.)

> **`JAC_BUN` is documented but ignored: `jac install` always runs the bundled bun**
>
> jac 0.39.0 (also 0.38.3), Linux x86-64. `reference/plugins/jac-client.md` says `JAC_BUN` overrides which bun is used, but `jac install` always runs `<runtime>/site/jaclang/client/_bun/bun`. On CPUs without AVX2 (e.g. Celeron N4020) that bun crashes with SIGILL, so client projects cannot install dependencies, and the error shown is only "Failed to install dependencies". Repro: point `JAC_BUN` at a wrapper that logs and execs a real bun, run `jac install` in a fresh `--kind web-app` project: the wrapper is never called. Suggested fix: honour `JAC_BUN` in the bun artifact probe (before sealed/checkout/kit), and/or ship or fetch the `-baseline` bun when the CPU lacks AVX2.
