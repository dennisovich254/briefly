# JD-010: The bun bundled in the Jac runtime needs AVX2, with no fallback for older CPUs

- **Version:** jaclang 0.39.0 (bundled bun 1.3.11), Ubuntu 26.04, x86-64 Intel Celeron N4020 (no AVX2), both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (re-test of JI-002; first hit in 0.3)
- **Category / severity:** Packaging/install / Minor
- **Capability:** Build and packaging (`jac build`)
- **Status:** open
- **Related:** JI-002 (AfriCinemas), still holding on 0.39.0; JD-001 (the documented `JAC_BUN` override that would avoid this is ignored); upstream searched 2026-11-04: no matching issue
- **Cost:** included in JD-001 (1.5 h); workaround `scripts/swap_bundled_bun.sh`
- **Canary:** bench/jd_010_bundled_bun_needs_avx2.sh

## Behaviour

The runtime's bundled bun (`<runtime>/site/jaclang/client/_bun/bun`, recorded as `{"version": "1.3.11"}` in `bun.artifact.json`) is bun's default x86-64 build, which uses AVX2. On a CPU without AVX2 it dies at once: `bun --version` gives `Illegal instruction (core dumped)`, exit 132. Every Jac command that runs bun (`jac install` for a client project, `jac create --kind web-app|desktop`, client builds) fails. Bun publishes a `-baseline` build for such CPUs, but Jac neither ships it nor picks it.

## Expected

The client tooling runs on any x86-64 CPU that Ubuntu supports, or Jac says why it can't. The `jac-client` reference says "all JS tooling (installs, Expo/Metro, Vite) runs on the Bun runtime bundled with the `jac` binary"; it names no CPU requirement.

## Repro

`bench/jd_010_bundled_bun_needs_avx2.sh` locates the active runtime and runs its original bundled bun (kept as `bun.avx2-original` by the workaround). On the owner's Celeron N4020: exit 132 (SIGILL).

## Analysis

JI-002 holds unchanged since 0.37.18. On its own this would have a documented escape hatch (`JAC_BUN`), but JD-001 removed it, so the two together block every client build on such CPUs. The desktop artifact Jac builds does not run bun, so end users are not affected; developers and build machines are.

## Workaround

`scripts/swap_bundled_bun.sh` replaces the runtime's bundled bun with the same version's `-baseline` build after each Jac install or upgrade, keeping the original as `bun.avx2-original`. `scripts/doctor.sh` checks the bun Jac really runs.

## Canary

`bench/jd_010_bundled_bun_needs_avx2.sh`: exit 0 while the original bundled bun crashes on this CPU, exit 2 on CPUs with AVX2 (not testable). Mutation-checked: pointed at the swapped baseline bun, it exits 1.

## Upstream issue draft

(For the owner to review before posting.)

> **The bundled bun is the AVX2 build: every client command fails with SIGILL on CPUs without AVX2**
>
> jac 0.39.0, Linux x86-64, Intel Celeron N4020 (no AVX2). `<runtime>/site/jaclang/client/_bun/bun --version` dies with `Illegal instruction` (exit 132), so `jac install`, `jac create --kind web-app` and client builds fail with only "Failed to install dependencies". Bun ships a `-baseline` x86-64 build for these CPUs. Suggest shipping or fetching it when `/proc/cpuinfo` lacks `avx2`. The documented `JAC_BUN` override would work around it, but it is ignored (separate issue).
