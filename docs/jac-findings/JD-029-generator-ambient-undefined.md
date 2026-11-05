# JD-029: The checker accepts `Generator` without an import, but at run time it is undefined

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-05, phase 1 / 1.4 S4
- **Category / severity:** Defect / Minor
- **Capability:** Tooling (`jac check`, `jac fmt`, `jac browse`, editor support)
- **Status:** open
- **Related:** JD-028 (the cast that needs `Generator`); upstream searched 2026-11-05: no matching issue
- **Cost:** 0.25 h; workaround: `import from typing { Generator }` (1 line)
- **Canary:** tests/canaries/jd_029_generator_ambient_undefined.jac

## Behaviour

`cast(Generator[int, None, None], x)` with no import of `Generator` passes `jac check`, and `jac run` then fails with `name 'Generator' is not defined`. The same expression with `Iterator` works both ways. The rules for these names are also inconsistent:

| Name | Without an import | `import from typing { … }` |
|---|---|---|
| `Iterator`, `Callable` | checks and runs | rejected: "is ambient and cannot be imported from 'typing'" (E1125) |
| `Generator` | checks, then `NameError` at run time | checks and runs |

## Expected

A name the checker treats as ambient exists at run time, or the checker reports it as undefined.

## Repro

`~/jac-repros/JD-029/g.jac`: `cast(Iterator[int], …)` runs, `cast(Generator[int, None, None], …)` passes `jac check` and fails at run time; `h.jac`: `import from typing { Generator }` is accepted.

## Analysis

It shows on the server path, as in the repro, whose generator function keeps the module there. In a module Jac compiles native, the same expression runs, because native code does not evaluate the cast.

A checker that passes a program which then fails on an undefined name defeats the point of the gate, and the asymmetry with `Iterator`/`Callable` (which must not be imported) makes the right spelling guesswork.

## Workaround

Import `Generator` from `typing` (`core/ai/answer.jac`).

## Canary

`tests/canaries/jd_029_generator_ambient_undefined.jac`: asserts `jac check` passes and `jac run` fails with the `NameError`.

## Upstream issue draft

(For the owner to review before posting.)

> **`Generator` is ambient to `jac check` but undefined at run time**
>
> jac 0.39.1. `print(cast(Generator[int, None, None], iter([1])))` with only `import from typing { cast }` passes `jac check`, then `jac run` fails with `name 'Generator' is not defined`. `Iterator` and `Callable` behave as true ambients (and importing them from `typing` is E1125), while `Generator` can be imported. Expected: consistent ambients, or E-level "undefined name" for `Generator` without an import.
