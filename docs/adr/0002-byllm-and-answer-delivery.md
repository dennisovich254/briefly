# ADR 0002: Every Claude call stays on byLLM, and answers stream as an authenticated response stream

- **Status:** Proposed (accepted when the owner merges the 1.4 pull request)
- **Date:** 2026-11-05
- **Decides:** architecture §18 A05 (byLLM for every Claude call; the SDK only per logged finding) and the §11.3 delivery mechanism
- **Evidence:** spike S4, plan 1.4: `tests/ai/`, `bench/live_checks.jac`, `bench/results/stream-latency-20261105T1229Z.json` and `-1231Z.json`, JD-028 to JD-034

## Context

§10.1 needs six things of the live answer path: streamed output, cancellation, timeouts, token usage, image input and structured output. Each was tested through byLLM on MockLLM (`tests/ai/`, 9 tests) and once live on `claude-haiku-5-5` (`bench/live_checks.jac`):

| Need | byLLM | Live result |
|---|---|---|
| Streaming | `stream=True, logging=True`; needs a cast to type-check (JD-028) | first readable sentence: warm p50 1.16 s, p95 1.25 s (20 answers; a repeat run 1.17 / 1.38 s); the first answer in a process 10.2–10.4 s (JD-033) |
| Cancellation | close the stream generator | first chunk at 0.8 s, then cancelled |
| Timeouts | `timeout=` per call, `LLMTimeout` | raised after 0.5 s on a 0.2 s deadline |
| Token usage | `usage` event at the end of a logged stream | counts are right; cost is reported as 0 for this model (JD-034) |
| Image input | `Image(...)` argument | read a drawn test failure correctly in 2.9 s |
| Structured output | an `obj` return type, retried when malformed | a typed answer with three citations |

The §13 target for a typed answer's first useful draft (p50 ≤ 2 s, p95 ≤ 4 s) is met with a wide margin once warm. The cold first answer misses it because byLLM loads litellm on first use (JD-033). The whole live evaluation cost $0.0027.

For delivery, §11.3 orders three mechanisms. Native host events cannot be emitted by app code (JD-030); WebSockets cannot target one client (JD-014); an authenticated Jac response stream (SSE from a `def:protect` endpoint that reports a generator) works for the desktop window and the phone alike, rejects an unauthenticated client (401), but is never closed by the server when its client leaves (JD-031).

## Decision

1. **Every Claude call stays on byLLM (A05 confirmed).** No capability failed, so no call path moves behind `llm=sdk`. The defects found are worked around in Briefly's own code, each citing its finding: the stream cast (JD-028), the `Generator` import (JD-029), explicit cancellation (JD-031) and Briefly's own token pricing (JD-034).
2. **Answers are delivered as an authenticated response stream** (`answer_stream`, SSE), with `answer_cancel` as the §11.3 `answer.cancel` command, which closes the byLLM stream directly. The UI calls it whenever an answer is stopped or left. No event-poll fallback is needed.
3. **The live-answer model is `claude-haiku-5-5`**, verified available to the owner's key, with answers capped at 300 output tokens. The stronger preparation profile (§10.1) is chosen when preparation is built (phase 4).
4. **byLLM's provider packages load when the server starts**, in the background, so the first question after launch does not pay JD-033's ten seconds (built with the answer UI in phase 4, measured against the 5 s warm-start target).

## Consequences

- The installed desktop app cannot make a byLLM call until its packaging ships byLLM's Python packages (JD-032, Major). That is a packaging task (the clean-install job, phase 8), not a reason to leave byLLM.
- A client that disappears without cancelling leaves its provider stream running until byLLM's timeouts (90 s idle, 600 s per call) end it (JD-031). The cap of 300 output tokens bounds what such an answer can cost.
- `bench/stream_latency.jac` and `bench/live_checks.jac` are re-run at each compiler upgrade; both check the key against the free model list first and carry spend caps (the owner's API budget is small).
