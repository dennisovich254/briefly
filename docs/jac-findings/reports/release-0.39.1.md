# Release report: Jac 0.39.0 → 0.39.1

- **Date:** 2026-11-05, between spikes S1a (1.3) and S4 (1.4); the owner chose to upgrade before S4 (plan §2.5)
- **Release:** jac 0.39.1, published 2026-11-04. The GitHub release has no notes beyond the install command; the 35 commits between `v0.39.0` and `v0.39.1` were read instead.
- **Machine:** the owner's laptop (Celeron N4020, 2 cores, 3.3 GiB, Ubuntu 26.04 GNOME on Wayland), plus the CI runners (`ubuntu-latest`, and a fresh `ubuntu:24.04` container for the clean install)

## What changed in Jac that matters to Briefly

| Change | Effect here |
|---|---|
| JacPython is the only Python; stock CPython dropped (#10494) | Likely cause of the memory growth below (JD-027) |
| `[serve]` read strictly from `jac.toml`, profiles and `jac.local.toml` (#10417) | None yet: Briefly has no `[serve]` table (ADR 0001 adds one worker for the lean profile in phase 2) |
| A failed write after a request's commit is answered, not hidden or re-run (#10565) | Related to JI-042, which did not reproduce on 0.39.0 either |
| `jac check` finds the entry the kernel analysed however its path is spelled (#10442) | JD-005 unchanged: a bare `jac check` still skips files no app imports |
| Native compilation fixes (int of an optional, unwind records, getattr aliases, …) | JD-004 unchanged: the canary still segfaults |

## Upgrade steps and what they cost

1. `scripts/install_jac.sh` (after setting `.jac-version` and `jac.toml` to 0.39.1): the release asset and its checksum verified, installed.
2. The new runtime's bundled bun is again the AVX2 build: `scripts/swap_bundled_bun.sh` swapped it (JD-001, JD-010), then `scripts/doctor.sh` passed.
3. `jac install`; `jac clean --cache` for the project's compiled cache.
4. `jac check`, lint and the warnings ratchet: clean, 0 warnings. No code change was needed.

## Findings

Every canary was re-run on 0.39.1: the 15 test canaries (`scripts/test.sh`, 56 tests, all passing) and the bench canaries `jd_001`, `jd_003`, `jd_010`, `jd_011`, `jd_020` and `jd_022`. Each still reproduces, so every testable finding holds. The findings without canaries were checked by hand: JD-008 (`jac precommit --install` still replaces framework hooks), JD-009's second case (`--lintfix` still splits a `with entry` block), JD-014 (#10319 still open, no targeted send), JD-023 (the window plugin still has four commands) and JD-024 (`PG_MAX_CONNECTIONS = 256`, `PG_MAX_PRED_LOCKS_PER_TXN = 1024`).

| | Count |
|---|---|
| Fixed by 0.39.1 | 0 |
| Still holding | 26 (JD-001 to JD-026) |
| New | 1: JD-027 (Minor) |

## Measurements

Idle, five runs each, `bench/mem.jac`, PSS median (USS):

| | 0.39.0 | 0.39.1 | Change | Budget |
|---|---|---|---|---|
| Desktop, all processes | 335.0 MB (227.1) | 353.2 MB (237.4) | +18.2 MB | 300 MB: missed by 53 MB |
| host / WebKit / PostgreSQL | 123 / 110 / 102 | 135 / 114 / 104.5 | +12 / +4 / +2.5 | |
| Lean server, one worker | 84.3 MB (79.1) | 94.5 MB (83.6) | +10.2 MB | 200 MB |
| Jac's web-app scaffold, served, one worker | 90.0 MB (89.9) | 103.5 MB (103.4) | +13.5 MB | (JD-027's repro) |
| Desktop artifact, compressed / installed | 180 / 260 MB | 189 / 270 MB | +9 / +10 MB | |

Idle CPU stayed at 0.0–0.1 %. The window SDK check (`WINDOW_PLUGIN=explicit bench/window_sdk.sh`) and the local install check (`bench/install_check.sh local`, 1 → 2 across a restart) pass; the `clean-install` CI job runs on the upgrade PR.

## Decisions

None change. ADR 0001 still holds: the desktop's miss is mostly JD-024 (about 72 MB) and the regression widens it; the lean profile's estimate with PostgreSQL rises from 178 to about 190 MB, still under its 200 MB budget, and becomes a measurement in phase 3.
