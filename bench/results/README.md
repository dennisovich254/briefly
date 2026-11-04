# Benchmark results

Raw output of `bench/mem.jac`, one JSON file per batch, named `mem-<profile>-<phase>[-<label>]-<UTC time>.json`. Each file holds the machine, the commit, the budget, every run, and the median and range. Measured on the owner's laptop (Celeron N4020, 2 cores, 3.3 GiB, Ubuntu 26.04 GNOME on Wayland), jac 0.39.0.

## Current (plan 1.2, ADR 0001)

| File | What |
|---|---|
| `mem-desktop-idle-20261104T1220Z.json` | Desktop, final configuration (`[desktop.plugins] window = true`): PSS median 335.0 MB, USS 227.1 MB |
| `mem-lean-idle-20261104T1228Z.json` | Lean, Jac's default worker count, which picked 1 worker at that time: PSS 84.3 MB |
| `mem-lean-idle-1worker-20261104T1236Z.json` | Lean, `JAC_SERVE_WORKERS=1`: PSS 84.3 MB |

## Earlier batches of the same day, kept for the record

| File | What |
|---|---|
| `mem-desktop-idle-20261104T1116Z.json` | Desktop before the `[desktop.plugins]` table: PSS 319.3 MB, no USS column |
| `mem-desktop-idle-20261104T1157Z.json`, `mem-desktop-idle-20261104T1210Z.json` | Desktop, final configuration: 334.3 and 336.7 MB, no USS column |
| `mem-desktop-idle-noplugins-20261104T1202Z.json` | Desktop without the table again, two runs: 335.3 and 281.2 MB (host 123 and 71 MB). The 15 MB difference from the 1116Z batch is therefore not the plugin; PSS moves with what else maps the same libraries, which is why USS was added |
| `mem-lean-idle-20261104T1124Z.json` | Lean, Jac's default, which picked 2 workers at that time (3 processes): PSS 104.1 MB, RSS 258 MB |
