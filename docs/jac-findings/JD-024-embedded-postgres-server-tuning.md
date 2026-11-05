# JD-024: The desktop app's single-user PostgreSQL is tuned for 256 connections, about 78 MB of idle memory, with no knob

- **Version:** jaclang 0.39.0 (bundled PostgreSQL 18.6), Ubuntu 26.04, x86-64, Celeron N4020 with 3.3 GiB, desktop profile (and the lean profile once it uses the graph)
- **Found:** 2026-11-04, phase 1 / 1.2 S1b
- **Category / severity:** Performance/resource / Major
- **Capability:** Graph persistence and walkers
- **Status:** open
- **Related:** architecture §13 (idle budget 300 MB desktop, 200 MB lean); upstream searched 2026-11-04: no matching issue
- **Cost:** 1 h; workaround: none inside Jac (the settings are constants)
- **Canary:** none (a measurement: `bench/mem.jac` records the PostgreSQL share on every run)

## Behaviour

The desktop app misses its idle memory budget: median **335.0 MB PSS** against 300 MB (five runs, range 328.5–336.0; 581 MB summed RSS; 227 MB USS). By process group: host 123 MB, WebKit 110 MB, **PostgreSQL 102 MB**. The app does not use the graph yet; the cluster starts anyway and holds two idle connections. On 0.39.1 the desktop is 353.2 MB (JD-027) and the settings are unchanged.

Jac starts every embedded cluster, the desktop app's single-user one included, with `max_connections=256` and `max_pred_locks_per_transaction=1024` on the command line (constants `PG_MAX_CONNECTIONS` and `PG_MAX_PRED_LOCKS_PER_TXN` in `jaclang/data/pgembed.jac`), so the predicate-lock table is sized for 262,144 entries at start-up. Measured on a scratch cluster with the artifact's own PostgreSQL (idle, no connections):

| Settings | PSS |
|---|---|
| Jac's: 256 connections, 1024 predicate locks, `shared_buffers` 128 MB | 94.1 MB |
| Jac's connection settings, `shared_buffers` 16 MB | 86.4 MB |
| 20 connections, 64 predicate locks, `shared_buffers` 128 MB | 22.0 MB |
| 20 connections, 64 predicate locks, `shared_buffers` 16 MB | 15.7 MB |

Sizing the connection settings for one user saves about 72 MB, which would bring the desktop app to about 263 MB, inside its budget. `shared_buffers` alone is worth about 8 MB.

## Expected

A per-app desktop cluster serves one user and one process. The settings should be sized for that, or be configurable (`[desktop]` or `[scale.database]` keys, or environment variables). Architecture §13 requires a budget miss to be recorded with the per-process breakdown, which is this entry.

## Repro

`jac run bench/mem.jac desktop` (results: `bench/results/mem-desktop-idle-20261104T1220Z.json`). The scratch-cluster comparison starts `pgdist/bin/postgres` from the artifact on a fresh `initdb` with each set of `-c` options and sums the PSS of its processes after 15 s.

## Analysis

The tuning is right for a served multi-user app (Jac runs request transactions SERIALIZABLE, and its own diagnostic warns that a small predicate-lock pool fails under concurrent load), and wrong for a desktop app with one user. Because the options are passed on the command line, the cluster's `postgresql.auto.conf` cannot override them; only `shared_buffers` can be changed that way. The lean profile, once it uses the graph, shares the machine-wide development-style cluster with the same settings: 84 MB for a one-worker lean server plus about 94 MB for the cluster is about 178 MB against its 200 MB budget.

## Workaround

None inside Jac. Options recorded for the ADR: accept the miss and report upstream; lower `shared_buffers` through `postgresql.auto.conf` (about 8 MB); or patch the runtime constants, which the Jac-first rule rules out without a switch and which the sealed artifact may not pick up anyway.

## Canary

None: `bench/mem.jac` measures the PostgreSQL group on every run and fails when the total is over budget.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop per-app Postgres uses server tuning (max_connections=256, max_pred_locks_per_transaction=1024): about 78 MB extra idle memory, no way to change it**
>
> jac 0.39.0. A desktop build's own cluster starts with `-c max_connections=256 -c max_pred_locks_per_transaction=1024` (`PG_MAX_CONNECTIONS`, `PG_MAX_PRED_LOCKS_PER_TXN`). For a single-user app this costs most of the cluster's idle memory: 94 MB PSS on an idle scratch cluster versus 22 MB with 20 connections and 64 predicate locks. On a 4 GB laptop it is the difference between missing and meeting a 300 MB idle budget. Suggest single-user defaults for desktop clusters, or `[desktop]`/environment overrides for the two settings.
