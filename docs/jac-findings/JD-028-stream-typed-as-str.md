# JD-028: A `by llm(stream=True)` call is typed as `str`, so iterating its events fails `jac check`, and the reference's own example cannot run

- **Version:** jaclang 0.39.1 (byLLM bundled), Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-05, phase 1 / 1.4 S4
- **Category / severity:** Defect / Minor
- **Capability:** byLLM
- **Status:** open
- **Related:** JD-021 (type errors also block `jac run`); upstream searched 2026-11-05: no matching issue
- **Cost:** 0.5 h; workaround: `cast(Generator[StreamEvent, None, None], …)` at each streaming call (1 line)
- **Canary:** tests/canaries/jd_028_stream_typed_as_str.jac

## Behaviour

A streaming byLLM function is declared `-> str` (the guide: "`str` returns only") and returns a generator at run time: of string chunks with `stream=True`, of `StreamEvent`s with `stream=True, logging=True`. The checker types the call as the declared `str`, so:

- iterating `StreamEvent`s and reading `event.event_type` or `event.data` is `error[E1030]: Type "LiteralString" has no attribute "event_type"`;
- `next(gen)` is E1054 and `gen.close()` is E1030.

Because type errors also stop `jac run` (JD-021), the byLLM reference's own example in "Streaming with Logging (`StreamEvent`)", copied verbatim, fails `jac check` with six errors and does not run.

## Expected

The call to a `stream=True` function is typed as what it returns (`Generator[str, None, None]`, or `Generator[StreamEvent, None, None]` with `logging=True`), or the guide shows the declaration that type-checks.

## Repro

`~/jac-repros/S4-mock/docexample.jac`: the reference example verbatim. `jac check docexample.jac`: six E1030 errors; `jac run docexample.jac` stops on the first.

## Analysis

Streaming with `logging=True` is the path that reports token usage and cost, which a budgeted live answer needs (§10.5), so every Briefly answer stream hits this.

## Workaround

`core/ai/answer.jac` casts the call: `cast(Generator[StreamEvent, None, None], stream_answer(...))`, citing JD-028.

## Canary

`tests/canaries/jd_028_stream_typed_as_str.jac`: checks a two-line logged stream; asserts E1030 on `event_type`. Nothing is sent to a model: the file is only checked.

## Upstream issue draft

(For the owner to review before posting.)

> **`by llm(stream=True)` calls are typed as the declared `str`; the StreamEvent example in the byLLM reference fails `jac check` and won't run**
>
> jac 0.39.1. `def answer(q: str) -> str by llm(stream=True, logging=True);` then `for event in answer("q") { print(event.event_type); }` gives `E1030: Type "LiteralString" has no attribute "event_type"`; `next(...)` and `.close()` on the call fail too. Since type errors block `jac run`, the "Streaming with Logging (StreamEvent)" example copied from the reference doesn't run. Suggest typing such calls as `Generator[str, None, None]` / `Generator[StreamEvent, None, None]`.
