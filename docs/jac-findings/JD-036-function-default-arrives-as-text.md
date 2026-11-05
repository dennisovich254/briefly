# JD-036: An omitted argument of a served function receives the text of its default, so `False` runs as the truthy "False"

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, lean profile and `JacTestClient`
- **Found:** 2026-11-05, phase 1 / 1.5 S7 (`phone_start(tls: bool = False)` served HTTPS when called with `{}`)
- **Category / severity:** Defect / Major
- **Capability:** Server endpoints (`walker:pub`, `def:pub`)
- **Status:** open
- **Related:** upstream [jaseci-labs/jac#10602](https://github.com/jaseci-labs/jac/issues/10602) (open, filed 2026-11-05 by another user, with the cause: `introspect_callable` records `str(param.default)`)
- **Cost:** 1 h; workaround: no served function declares a default (guard test `tests/served_defaults_tests.jac`)
- **Canary:** tests/canaries/jd_036_function_default_arrives_as_text.jac

## Behaviour

`POST /function/defaults` with `{}` (or no body), on a lean server and through `JacTestClient` alike:

```jac
def:pub defaults(
    off: bool = False, on: bool = True, n: int = 3, x: float = 0.5, s: str = "a", maybe: int | None = None
) -> dict[str, str] { ... return type and repr of each ... }
```

| Parameter | Declared default | Received |
|---|---|---|
| `off` | `False` | `str:'False'` (truthy) |
| `on` | `True` | `str:'True'` |
| `n` | `3` | `str:'3'` |
| `x` | `0.5` | `str:'0.5'` |
| `s` | `"a"` | `str:'a'` |
| `maybe` | `None` | `str:'None'` (truthy) |

The call answers 200 and nothing is logged. A walker's `has` defaults are not affected (`walker:pub Defaults { has off: bool = False; }` gets `bool:False`). Passing the argument explicitly works.

## Expected

A parameter the caller omits takes its declared default, as in any function call; `jac-sv-endpoints` presents function parameters as the endpoint's typed body.

## Repro

`~/jac-repros/JD-036/`: the function above in `main.jac`, `[serve] host = "127.0.0.1"`, then `JAC_SERVE_WORKERS=1 jac run --serve --port 8768 main.jac` and `curl -X POST localhost:8768/function/defaults -H 'Content-Type: application/json' -d '{}'`.

## Analysis

Silent and dangerous: every boolean switch declared off runs as on, and every optional argument declared `None` runs as a non-empty string. In Briefly it turned the phone link's plain-HTTP default into HTTPS; the opposite default would have silently dropped TLS. Upstream #10602 traces it to `ModuleIntrospector.introspect_callable` storing `str(param.default)` and `bind_parameters` passing that text through; the same strings appear in `/openapi.json`.

## Workaround

Every argument of a `def:pub` or `def:protect` function is required (`phone_start(tls: bool)`); `tests/served_defaults_tests.jac` fails on any served function that declares a default.

## Canary

`tests/canaries/jd_036_function_default_arrives_as_text.jac`: a throwaway project with `def:pub flag(on: bool = False)`, called through `JacTestClient` with `{}`; asserts `on` arrives as `str:'False'`.

## Upstream issue draft

None needed: #10602 reports it with the cause and a fix. Optionally add our table (every scalar type and `None`) and that `JacTestClient` behaves the same, as a comment there.
