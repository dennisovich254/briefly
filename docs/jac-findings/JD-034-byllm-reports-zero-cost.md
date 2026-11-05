# JD-034: byLLM reports a cost of 0 for a model missing from litellm's price table, instead of leaving it unset

- **Version:** jaclang 0.39.1 (byLLM bundled, litellm 1.102.4), model `claude-haiku-5-5`
- **Found:** 2026-11-05, phase 1 / 1.4 S4 (the first live answer)
- **Category / severity:** Defect / Minor
- **Capability:** byLLM
- **Status:** open
- **Related:** architecture §10.5 (budgets are enforced from usage); upstream searched 2026-11-05: no matching issue
- **Cost:** 0.25 h; workaround: treat a cost of 0 with non-zero token counts as unknown and price it from Briefly's own table (`bench/stream_latency.jac`)
- **Canary:** none (needs a live, paid call; re-checked by `bench/stream_latency.jac`, whose output shows the reported cost)

## Behaviour

A streamed `by llm(stream=True, logging=True)` answer from `claude-haiku-5-5` ends with a `usage` event whose cost is `0` (178 input and 80 output tokens; Anthropic's price for those is about $0.00006). A spend cap that trusted the reported cost would never stop.

## Expected

The byLLM release note on cost reporting: "A pricing-table miss leaves `cost` unset rather than failing the call." An unknown price should be absent (or `None`), never `0`, so a caller can tell "free" from "unknown".

## Repro

One live answer: `jac run bench/stream_latency.jac --runs 1` before the workaround printed `$0.00000` for a 258-token answer.

## Analysis

`claude-haiku-5-5` is newer than the bundled litellm's price table, which is the expected miss; reporting it as zero is what makes it dangerous. Any budget enforcement built on byLLM's `cost` fails open for new models.

## Workaround

Briefly prices tokens itself (`PRICES` in `bench/stream_latency.jac`, and the budget service in phase 4) and treats a reported `0` with tokens as unknown.

## Canary

None: it needs a paid call. `bench/stream_latency.jac` prints the cost it used for every answer.

## Upstream issue draft

(For the owner to review before posting.)

> **byLLM `usage` reports `cost: 0` for a model litellm can't price (docs say it stays unset)**
>
> jac 0.39.1. A logged stream from `claude-haiku-5-5` (178 input + 80 output tokens) ends with a `usage` event whose cost is 0. The release notes say a pricing-table miss leaves `cost` unset. Reporting 0 makes spend caps fail open for any model newer than the bundled litellm. Suggest `None`/absent for an unknown price.
