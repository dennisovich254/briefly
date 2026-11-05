# Benchmark results

Raw output of `bench/mem.jac`, one JSON file per batch, named `mem-<profile>-<phase>[-<label>]-<UTC time>.json`. Each file holds the machine, the commit, the budget, every run, and the median and range. Measured on the owner's laptop (Celeron N4020, 2 cores, 3.3 GiB, Ubuntu 26.04 GNOME on Wayland), jac 0.39.0.

## Jac 0.39.0 (plan 1.2, ADR 0001)

| File | What |
|---|---|
| `mem-desktop-idle-20261104T1220Z.json` | Desktop, final configuration (`[desktop.plugins] window = true`): PSS median 335.0 MB, USS 227.1 MB |
| `mem-lean-idle-20261104T1228Z.json` | Lean, Jac's default worker count, which picked 1 worker at that time: PSS 84.3 MB |
| `mem-lean-idle-1worker-20261104T1236Z.json` | Lean, `JAC_SERVE_WORKERS=1`: PSS 84.3 MB |

## Jac 0.39.1 (release report: docs/jac-findings/reports/release-0.39.1.md)

| File | What |
|---|---|
| `mem-desktop-idle-20261105T1016Z.json` | Desktop on 0.39.1: PSS median 353.2 MB, USS 237.4 MB |
| `mem-lean-idle-1worker-20261105T1024Z.json` | Lean, one worker, on 0.39.1: PSS 94.5 MB |

## Jac 0.39.1 with byLLM imported (plan 1.4)

| File | What |
|---|---|
| `mem-desktop-idle-byllm-20261105T1130Z.json` | Desktop once `core/ai/answer.jac` imports byLLM: PSS 373.2 MB (host 152.5, up 17) |
| `mem-lean-idle-1worker-byllm-20261105T1138Z.json` | Lean, one worker, with byLLM imported: PSS 97.9 MB (up 3.4) |

## Live answer latency (plan 1.4, ADR 0002)

| File | What |
|---|---|
| `stream-latency-20261105T1229Z.json` | 20 streamed answers on `claude-haiku-5-5`: first readable sentence cold 10.4 s, warm p50 1.16 s, p95 1.25 s; $0.0012 |
| `stream-latency-20261105T1231Z.json` | The same run repeated (it started by mistake when another script imported the bench): warm p50 1.17 s, p95 1.38 s; $0.0012 |

## Earlier batches of 2026-11-04, kept for the record

| File | What |
|---|---|
| `mem-desktop-idle-20261104T1116Z.json` | Desktop before the `[desktop.plugins]` table: PSS 319.3 MB, no USS column |
| `mem-desktop-idle-20261104T1157Z.json`, `mem-desktop-idle-20261104T1210Z.json` | Desktop, final configuration: 334.3 and 336.7 MB, no USS column |
| `mem-desktop-idle-noplugins-20261104T1202Z.json` | Desktop without the table again, two runs: 335.3 and 281.2 MB (host 123 and 71 MB). The 15 MB difference from the 1116Z batch is therefore not the plugin; PSS moves with what else maps the same libraries, which is why USS was added |
| `mem-lean-idle-20261104T1124Z.json` | Lean, Jac's default, which picked 2 workers at that time (3 processes): PSS 104.1 MB, RSS 258 MB |
