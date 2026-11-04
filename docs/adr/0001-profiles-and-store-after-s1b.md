# ADR 0001: The desktop profile stays primary, the lean profile runs one worker, and the graph stays the only store

- **Status:** Proposed (accepted when the owner merges the 1.2 pull request)
- **Date:** 2026-11-04
- **Decides:** architecture §18 A02 (native desktop primary, lean fallback) and A07 (the graph as the single store; `store=files` only if S1 fails)
- **Evidence:** spike S1b, plan 1.2: `bench/results/mem-*-idle-20261104*.json`, JD-020 to JD-024

## Context

§13 sets idle budgets of 300 MB for the desktop profile and 200 MB for the lean profile, counting every process of the assistant, PostgreSQL included, and 600/500 MB during a meeting. Measured on the owner's laptop (Celeron N4020, 2 cores, 3.3 GiB, Ubuntu 26.04 GNOME on Wayland), jac 0.39.0, five runs each, 60 s settle and a 30 s window (`bench/results/README.md` lists every batch):

| Profile | PSS median (range) | USS | Summed RSS | Breakdown (PSS) | Idle budget |
|---|---|---|---|---|---|
| Desktop | **335.0 MB** (328.5–336.0) | 227.1 MB | 581 MB | host 123, WebKit 110, PostgreSQL 102 | 300 MB: **missed by 35 MB** |
| Lean, one worker | 84.3 MB (84.3–84.3) | 79.1 MB | 94 MB | server only (1 process) | 200 MB |
| Lean, two workers (Jac's default earlier in the day) | 104.1 MB (102.5–106.5) | not measured | 258 MB | server only (3 processes) | 200 MB |

Idle CPU is 0.0–0.2 % in every run (budget 2 %). The desktop window and its database are up 3.1–4.4 s after launch (warm-start target 5 s). PSS is the figure used against the budgets: summed RSS counts shared pages once per process, which for 11 PostgreSQL processes overstates the cost. PSS itself moves with what else on the machine maps the same libraries (one desktop run measured 281 MB, with the host at 71 MB instead of 123), so USS, private memory only, is reported as the floor; even that floor is 227 MB.

Jac's default worker count for a served app depends on free memory at start: the same lean artifact ran two workers in one batch and one in the next. A personal server should not change shape with the machine's load.

The lean app does not touch the graph yet, so no PostgreSQL ran for it. With the graph it uses Jac's machine-wide cluster, which costs about 94 MB idle with Jac's settings (JD-024's scratch measurement): about **178 MB** for a one-worker lean server.

The desktop's PostgreSQL is 102 MB of the 335, and most of that is JD-024: Jac starts the desktop app's single-user cluster with server settings (256 connections, 1024 predicate locks per transaction) that cost about 72 MB at idle and cannot be changed from the app. With single-user settings the desktop profile would be about 263 MB.

## Decision

1. **The desktop profile stays the primary build and the evaluation target (A02 confirmed).** The idle miss is recorded as JD-024 (Major) with the per-process breakdown, as §13 requires, and reported upstream. Daily standups may use the desktop profile: the miss is 12 % at idle, mostly Jac's PostgreSQL tuning, and the meeting budget (600 MB) leaves about 265 MB of headroom. The meeting-phase measurement decides that finally (below).
2. **The lean profile serves with one worker** (`[serve]` worker count 1, applied when the lean profile is built out in phase 2). A single-user server gains nothing from a second worker, which costs about 20 MB, and pinning the count stops it from changing with free memory.
3. **The graph stays the only store in both profiles (A07 confirmed); `store=files` is not needed.** With PostgreSQL the lean profile is estimated at 178 MB against 200 MB. That estimate becomes a measurement as soon as the lean app writes to the graph (phase 3), and the switch to `store=files` stays the documented fallback if it does not hold.

## Consequences

- `bench/mem.jac` stays the gate: it fails while the desktop median is over budget, so the miss stays visible on every run until Jac changes (JD-024's upstream issue) or the app adds memory.
- **Not measured yet:** the meeting phase (§13: Meet and VS Code open during a 15-minute call, five runs after a reboot). Briefly has no audio or speech-to-text yet, so meeting-phase numbers now would measure an idle app beside Meet. They move to 1.6 (S3, speech-to-text), where they mean something: `jac run bench/mem.jac both --phase meeting`, run by the owner during a real call.
- **Not measured:** the CEF engine (`[desktop] engine = "cef"`), which the plan lists as optional. It bundles Chromium, which is unlikely to be lighter than WebKitGTK; it is left for a release report if WebKit becomes the problem.
- The desktop's PostgreSQL survives SIGTERM (JD-020), which matters for a laptop that is logged out with the app open; it is tracked separately and does not change this decision.
