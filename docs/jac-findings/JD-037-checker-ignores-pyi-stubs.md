# JD-037: `jac check` ignores a `.pyi` stub beside its `.py`, so calls into a stub-typed library are typed `object` and refused

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64
- **Found:** 2026-11-05, phase 1 / 1.5 S7 (`segno`, for the phone link's QR code)
- **Category / severity:** Defect / Minor
- **Capability:** Python interoperability
- **Status:** open
- **Related:** upstream searched 2026-11-05: no matching issue
- **Cost:** 0.75 h; workaround: an `as` cast at each call (`bench/phone_link.jac`)
- **Canary:** tests/canaries/jd_037_checker_ignores_pyi_stubs.jac

## Behaviour

`segno` (a QR code library) ships inline stubs: `segno/__init__.pyi` declares `def make_qr(...) -> QRCode` beside an unannotated `__init__.py`. In Jac, `segno.make_qr(url).terminal()` fails `jac check` with `E1030: Type "object" has no attribute "terminal"`, and `jac run` refuses the file with the same error.

Reduced: a module `stubmod.py` with an unannotated `def make(): return Code()` and a `stubmod.pyi` declaring `def make() -> Code: ...`; `stubmod.make().show()` in Jac is typed `object` (E1030). The same for a package (`stubpkg/__init__.py` plus `__init__.pyi`). Annotating the `.py` itself fixes it, so the checker reads the `.py` and ignores the stub; with an unannotated `.py` it types the return as `object`, not `any`.

## Expected

`jac-python-interop`: the checker "resolves it via PEP 561 from the project's `.jac/venv`", and the fix it gives for an untyped source is to "type the source (`.pyi` stub)". PEP 561 puts a stub ahead of the source it sits beside. The same guide says untyped returns "arrive as `any`", not `object`.

## Repro

`~/jac-repros/stubfwd/`: `stubmod.py` and `stubmod.pyi` as above, and `s.jac`:

```jac
import stubmod;

with entry {
    stubmod.make().show();
}
```

`jac check s.jac` reports E1030 on `show`; `jac run s.jac` refuses to run.

## Analysis

Many typed libraries ship `.pyi` stubs beside untyped sources (segno, and any package built with stub generation), and the guide's own advice for untyped code is to add one. Both fail: such code cannot be called without a cast or a suppression at every call.

## Workaround

Cast the result to the stub's type, as the guide's untyped-boundary playbook allows: `qr = segno.make_qr(url, error="m") as segno.QRCode;` (`bench/phone_link.jac`).

## Canary

`tests/canaries/jd_037_checker_ignores_pyi_stubs.jac`: writes `stubmod.py`, `stubmod.pyi` and a Jac caller into a throwaway project; asserts `jac check` reports E1030 for the stub-typed call.

## Upstream issue draft

(For the owner to review before posting.)

> **Type checker ignores a `.pyi` stub next to its `.py` (PEP 561), typing calls as `object`**
>
> jac 0.39.1. `stubmod.py` (unannotated `def make(): return Code()`) with `stubmod.pyi` (`def make() -> Code: ...`): from Jac, `stubmod.make().show()` fails `jac check` with E1030 `Type "object" has no attribute "show"`, and `jac run` refuses the file. Same for a package's `__init__.pyi`. Annotating the `.py` fixes it, so the stub is not read. Real case: `segno.make_qr(...)` (segno ships `__init__.pyi`). The interop guide says stubs resolve via PEP 561 and recommends a `.pyi` to type untyped code; it also says untyped returns arrive as `any`, but they arrive as `object`.
