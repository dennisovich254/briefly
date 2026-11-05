# JD-031: When a client leaves a streamed response, the server never closes the endpoint's generator

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, both profiles (`jac run` of a sealed service, one worker)
- **Found:** 2026-11-05, phase 1 / 1.4 S4
- **Category / severity:** Defect / Major
- **Capability:** Real-time delivery (host events, WebSockets, streams)
- **Status:** open
- **Related:** architecture §10.1 (cancellation is required of the live path), §11.3 (`answer.cancel`); upstream searched 2026-11-05: no matching issue
- **Cost:** 1 h; workaround: a per-request registry and `answer_cancel` that closes the byLLM stream directly (about 25 lines)
- **Canary:** bench/jd_031_abandoned_stream_never_closed.sh

## Behaviour

A `def:protect` endpoint that reports a generator streams it as SSE, one frame per `yield` (`jac-sv-streaming`). When the client disconnects partway (here after about 1 s of a 20-chunk stream, 0.5 s per chunk), the server produces one more chunk and then stops iterating, but it does not close the generator: its `finally` block had still not run 10, 30 and 60 s later, while other requests were served normally. It ran only when the server shut down.

A generator left suspended keeps whatever it holds. With a byLLM stream inside, that is the open connection to the model provider, which goes on generating, and billing for, an answer nobody reads, until its own timeouts end it (`read_timeout` 90 s between chunks, `timeout` 600 s for the call).

## Expected

Closing the generator when the client goes away, so `finally` blocks and context managers run and the provider stream is closed; that is what §10.1's cancellation requirement needs from the transport.

## Repro

`~/jac-repros/S4-sse/` (and the canary): a service with `def:protect slow_stream(n)` whose generator logs each yield and `closed` in `finally`. `timeout 1.2 curl -N …/function/slow_stream`, then read the log.

## Analysis

The server seems to stop at the failed write and drop its reference to the iterator without calling `close()`. Answers on a 4 GB laptop and a small API budget make this costly: every abandoned answer keeps generating until it finishes or times out.

## Workaround

`core/ai/answer.jac` keeps each open byLLM stream by request ID; `answer_cancel` (the §11.3 `answer.cancel` command) closes it directly, which closes the provider's stream, and the frame generator then ends with a `cancelled` frame. The answer UI (phase 4) must call `answer_cancel` when the user stops or leaves an answer; `tests/ai/answer_tests.jac` checks that cancelling closes the stream. A client that disappears without cancelling still leaves its stream open until byLLM's timeouts end it.

## Canary

`bench/jd_031_abandoned_stream_never_closed.sh`: builds the repro, disconnects a client, and exits 0 while the generator's `finally` has not run 20 s later. No model is called.

## Upstream issue draft

(For the owner to review before posting.)

> **A streamed (SSE) endpoint's generator is never closed when the client disconnects**
>
> jac 0.39.1. `def:protect slow_stream(n: int) { def frames -> Generator[str, None, None] { try { for i in range(n) { time.sleep(0.5); yield f"chunk {i}"; } } finally { log("closed"); } } report frames(); }` served from a sealed app. A client that disconnects after about 1 s: the server yields one more chunk, then stops, but `finally` doesn't run (still not after 60 s; only at shutdown). With an LLM stream inside, the provider connection stays open and keeps generating. Expected: `close()` the generator when the write fails or the client disconnects.
