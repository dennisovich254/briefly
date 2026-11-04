# JD-015: Four layout quirks in `jac fmt` (behaviour is preserved)

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (candidates noted in 0.2–0.3)
- **Category / severity:** Defect / Cosmetic
- **Capability:** Tooling (`jac check`, `jac fmt`, `jac browse`, editor support)
- **Status:** open
- **Related:** JD-009 (`--lintfix` moving a comment); upstream #8769 (a `--lintfix` rewrite that changes meaning); upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: none needed (the output is accepted as Jac's style)
- **Canary:** tests/canaries/jd_015_fmt_layout_quirks.jac

## Behaviour

1. **Continued `glob` lists are indented by 9 spaces.** A list spread over lines after `glob NAMES: list[str] = [` gets its items at 9 spaces and its closing bracket at 5, where every other construct uses 4.
2. **A multi-line dict with a trailing comma collapses to one line that keeps the comma:** `settings = {"alpha": 1, "beta": 2,};`. (In 0.2 the same input gained a blank line before the closing brace instead.)
3. **`assert x, msg` becomes `assert x , msg`**, with a space before the comma.
4. **A long expression inside an f-string's braces is split across lines inside the braces:**

   ```jac
   print(
       f"the items were {', '.join(
           sorted(
               item.upper()
               for item in items
               if item.startswith('a') or item.startswith('b')
           )
       )} today"
   );
   ```

## Expected

Consistent 4-space continuation, no space before a comma, and either a multi-line dict or a one-line dict without the dangling comma. Splitting inside f-string braces is valid on the bundled Python 3.14, but splitting the string or the call outside the braces is easier to read.

## Repro

`~/jac-repros/JD-015/`: `q1_glob.jac`, `q2_dict.jac`, `q3_assert.jac`, `q4_fstring.jac` with their originals (`*.orig`). Every case still runs after `jac fmt`; the two that print (`q2`, `q4`) print the same before and after, and `jac fmt --check` accepts the formatted `q1` and `q3`.

## Analysis

The plan asked whether these were a formatter-safety question. On these cases they are not: behaviour is preserved, and the formatter accepts its own output. They are layout issues only, but they show up in this repository's own code (`scripts/check_findings.jac` has quirk 1, and the test files have quirk 3).

## Workaround

None needed. The hooks accept `jac fmt` output as it is.

## Canary

`tests/canaries/jd_015_fmt_layout_quirks.jac`: formats each case and asserts the quirk is still there; it fails, naming the case, when one changes.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac fmt` layout quirks: 9-space glob continuation, `assert x , msg`, one-line dict keeping its trailing comma, splits inside f-string braces**
>
> jac 0.39.0. (1) `glob NAMES: list[str] = [\n "a",\n "b"\n];` formats its items at 9 spaces and `]` at 5. (2) A multi-line dict literal with a trailing comma collapses to `{"alpha": 1, "beta": 2,}`. (3) `assert x, "msg"` becomes `assert x , "msg"`. (4) A long expression inside f-string braces is split across lines inside the braces. Behaviour is preserved in each case; repro files attached.
