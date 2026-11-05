# JD-033: The first byLLM call in a process spends about 10 s loading litellm before any request

- **Version:** jaclang 0.39.1 (byLLM bundled, litellm 1.102.4), Ubuntu 26.04, Celeron N4020 (2 cores, 3.3 GiB); both profiles
- **Found:** 2026-11-05, phase 1 / 1.4 S4 (the latency bench's mock mode)
- **Category / severity:** Performance/resource / Minor
- **Capability:** byLLM
- **Status:** open
- **Related:** JD-032 (the same packages, missing from the artifact); architecture §13 (typed first useful draft: p50 ≤ 2 s, p95 ≤ 4 s; warm start ≤ 5 s); upstream searched 2026-11-05: no matching issue
- **Cost:** 0.5 h; workaround: load byLLM's provider packages in the background at server start (to do with the answer UI)
- **Canary:** none (a measurement: `bench/stream_latency.jac` reports the cold first answer on every run)

## Behaviour

`jac run bench/stream_latency.jac --mock` runs `core/ai/answer.jac`'s streamed answer on `MockLLM`, so no request leaves the machine. The first answer in the process took 9.9–10.7 s to its first sentence in three runs; every later answer took about 5 ms. A bare `import litellm` under `jac run` took 15.4 s once on the same laptop. byLLM loads litellm on first use, and even `MockLLM` goes through it (0.4).

## Expected

A live answer's first useful sentence within §13's 4 s (p95), including the first answer after the app starts. The byLLM guides do not mention the load time or a way to warm it.

## Repro

`jac run bench/stream_latency.jac --mock --runs 4`: the `cold` figure is the first answer, the p50/p95 the rest. `~/jac-repros/JD-033/import_time.jac` times the import alone.

## Analysis

The cost is litellm's import on a slow CPU, paid inside the first `by llm()` call, so it lands on the first question a user asks after launching the app, which is the worst moment in a standup. It is litellm's, but byLLM decides when it happens.

## Workaround

Import byLLM's provider path in a background thread when the server starts, so the first answer finds it loaded; this moves the cost into start-up memory (desktop host +17 MB already with byLLM imported, 1.4's measurement) and out of the answer. To build with the answer UI (phase 4), and to measure against the 5 s warm-start target.

## Canary

None: `bench/stream_latency.jac` reports the cold first answer separately on every run.

## Upstream issue draft

(For the owner to review before posting.)

> **byLLM: the first `by llm()` call in a process spends ~10 s importing litellm; document or offer a warm-up**
>
> jac 0.39.1 on a 2-core Celeron: the first call of a streamed `by llm()` function (even against `MockLLM`) takes about 10 s before its first chunk; later calls take milliseconds. `import litellm` alone took 15 s under `jac run`. For interactive apps the first question after launch pays it. Suggest a documented warm-up (for example a `byllm.preload()`), or loading the provider lazily per provider rather than all of litellm.
